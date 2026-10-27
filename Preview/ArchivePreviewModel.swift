import Foundation
import Synchronization

/// What the Quick Look extension shows for an archive in Finder: a header, a one-line Checkup and
/// the file tree. Built from the same `Archive` the browser uses, so names, sizes and findings match.
nonisolated struct ArchivePreviewModel: Sendable {
    struct Row: Identifiable, Sendable {
        let id: String
        let name: String
        let depth: Int
        let isFolder: Bool
        let size: Int64
    }

    var name: String
    var format: ArchiveFormat
    var fileCount: Int
    var folderCount: Int
    var totalSize: Int64
    var packedSize: Int64?
    var isEncrypted: Bool
    var headline: CheckupFinding
    var cautionCount: Int
    /// Folders first, then files, depth-first — capped so a huge archive still opens instantly.
    var rows: [Row]
    var hiddenRowCount: Int

    static let rowLimit = 1_500

    init(archive: Archive, rowLimit: Int = Self.rowLimit) {
        name = archive.name
        format = archive.format
        let files = archive.files
        fileCount = files.count
        folderCount = archive.entries.count - files.count
        totalSize = archive.totalSize
        packedSize = archive.packedSize
        isEncrypted = archive.isEncrypted
        headline = Self.headline(of: archive.checkup)
        cautionCount = archive.checkup.count { $0.severity == .caution }

        var children: [String: [ArchiveEntry]] = [:]
        for entry in archive.entries { children[entry.parent, default: []].append(entry) }
        for key in children.keys {
            children[key]?.sort { lhs, rhs in
                if lhs.isFolder != rhs.isFolder { return lhs.isFolder }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        }
        var rows: [Row] = []
        var hidden = 0
        // Iterative depth-first walk: archives can nest deeper than the stack likes.
        var stack: [(ArchiveEntry, Int)] = (children[""] ?? []).reversed().map { ($0, 0) }
        while let (entry, depth) = stack.popLast() {
            if rows.count < rowLimit {
                rows.append(Row(id: entry.path, name: entry.name, depth: depth,
                                isFolder: entry.isFolder, size: entry.size))
            } else {
                hidden += 1
            }
            if entry.isFolder {
                stack += (children[entry.path] ?? []).reversed().map { ($0, depth + 1) }
            }
        }
        self.rows = rows
        hiddenRowCount = hidden
    }

    /// The finding that matters most: a caution, then anything Stow handled, then the rest.
    static func headline(of findings: [CheckupFinding]) -> CheckupFinding {
        let order: [CheckupFinding.Severity] = [.caution, .handled, .info, .fine]
        for severity in order {
            if let finding = findings.first(where: { $0.severity == severity }) { return finding }
        }
        return CheckupFinding(severity: .fine, title: String(localized: "Names and sizes look normal"), detail: "")
    }

    var summary: String {
        var parts = [String(localized: "\(fileCount) files")]
        if folderCount > 0 { parts.append(String(localized: "\(folderCount) folders")) }
        parts.append(totalSize.bytes)
        return parts.joined(separator: " · ")
    }
}

/// What the preview shows instead when listing isn't possible or takes too long.
nonisolated struct ArchivePreviewFallback: Sendable {
    enum Reason: Sendable, Equatable {
        /// Names are encrypted too (7-Zip "encrypt file names"); nothing can be listed without the password.
        case encrypted
        /// Listing took longer than Quick Look should wait — usually a big .tar.xz that must be read end to end.
        case tooSlow
        case unreadable(String)
    }

    var name: String
    var format: ArchiveFormat
    var size: Int64
    var reason: Reason

    var title: String {
        switch reason {
        case .encrypted: String(localized: "Encrypted archive")
        case .tooSlow: String(localized: "Too large to list here")
        case .unreadable: String(localized: "Can’t list this archive")
        }
    }

    var message: String {
        switch reason {
        case .encrypted: String(localized: "Even the file names are protected. Open it in Stow and enter the password to see what’s inside.")
        case .tooSlow: String(localized: "Reading the whole archive would take a while. Open it in Stow to browse while it loads.")
        case .unreadable(let message): message
        }
    }

    var symbol: String {
        switch reason {
        case .encrypted: "lock.fill"
        case .tooSlow: "hourglass"
        case .unreadable: "questionmark.folder"
        }
    }
}

nonisolated enum ArchivePreviewContent: Sendable {
    case listed(ArchivePreviewModel)
    case fallback(ArchivePreviewFallback)
}

/// Lists an archive through the engine, giving up after `timeout`. List only — Quick Look never extracts.
nonisolated enum ArchivePreviewLoader {
    static let timeout: Duration = .seconds(3)

    static func load(_ url: URL, timeout: Duration = Self.timeout,
                     list: @escaping @Sendable (URL) async throws -> ArchiveListing) async -> ArchivePreviewContent {
        let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        let format = ArchiveFormat.infer(fromName: url.lastPathComponent) ?? .other
        func fallback(_ reason: ArchivePreviewFallback.Reason) -> ArchivePreviewContent {
            .fallback(ArchivePreviewFallback(name: url.lastPathComponent, format: format, size: size, reason: reason))
        }
        // A race rather than a task group: a group would wait for a listing that can't be cancelled.
        let listing = Task { () -> Result<ArchiveListing, EngineError> in
            do { return .success(try await list(url)) } catch { return .failure(EngineError(error)) }
        }
        let result = await withCheckedContinuation { (continuation: CheckedContinuation<Result<ArchiveListing, EngineError>?, Never>) in
            let once = ContinuationBox(continuation)
            Task {
                let value = await listing.value
                once.resume(returning: value)
            }
            Task {
                try? await Task.sleep(for: timeout)
                once.resume(returning: nil)
            }
        }
        if result == nil { listing.cancel() }
        switch result {
        case nil:
            return fallback(.tooSlow)
        case .failure(let error) where error.failure == .passwordRequired || error.failure == .wrongPassword:
            return fallback(.encrypted)
        case .failure(let error):
            return fallback(.unreadable(error.message))
        case .success(let listing):
            return .listed(ArchivePreviewModel(archive: Archive(listing: listing, url: url)))
        }
    }

    private nonisolated final class ContinuationBox: Sendable {
        private let lock: Mutex<CheckedContinuation<Result<ArchiveListing, EngineError>?, Never>?>

        init(_ continuation: CheckedContinuation<Result<ArchiveListing, EngineError>?, Never>) {
            lock = Mutex(continuation)
        }

        func resume(returning result: Result<ArchiveListing, EngineError>?) {
            lock.withLock { $0.take() }?.resume(returning: result)
        }
    }
}
