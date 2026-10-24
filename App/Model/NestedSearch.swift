import Foundation
import Observation

/// A search match inside an archive that sits in the one being browsed (issue #21).
nonisolated struct NestedHit: Hashable, Sendable {
    /// The archive inside the open one.
    let container: ArchiveEntry
    /// The match, at its path inside `container`.
    let inner: ArchiveEntry

    /// How the match shows in the results: under the container's name, like a folder
    /// ("Earlier Rounds/Old Explorations.7z/Round 1/Logo.png").
    var entry: ArchiveEntry {
        var entry = ArchiveEntry(path: container.path + "/" + inner.path, isFolder: inner.isFolder,
                                 size: inner.size, packedSize: inner.packedSize, modified: inner.modified)
        entry.isHelper = inner.isHelper
        return entry
    }
}

/// An omission is coverage information, not a search result or a request to unlock.
nonisolated struct NestedSearchOmission: Identifiable, Equatable, Sendable {
    enum Reason: Equatable, Sendable {
        case passwordRequired, readFailure, archiveSizeLimit, totalSizeLimit, archiveCountLimit

        var description: String {
            switch self {
            case .passwordRequired: String(localized: "Password required")
            case .readFailure: String(localized: "Could not read archive")
            case .archiveSizeLimit: String(localized: "Archive size limit")
            case .totalSizeLimit: String(localized: "Total search size limit")
            case .archiveCountLimit: String(localized: "Archive count limit")
            }
        }
    }

    let container: ArchiveEntry
    let reason: Reason
    var id: String { container.id }
}

/// Search one level into the archives inside an archive. Each inner archive is extracted to the
/// preview cache and listed once, the first time someone searches; after that a search is a scan
/// like any other. Only one level deep: open an inner archive to search the ones inside it.
@MainActor
@Observable
final class NestedSearch {
    /// Reads the entries of one inner archive (`entry`, inside `archive`).
    typealias Loader = @MainActor (_ entry: ArchiveEntry, _ archive: Archive) async throws -> [ArchiveEntry]

    /// Limits that keep a search from turning into an extraction of everything.
    static let maxArchives = 40
    static let maxArchiveSize: Int64 = 512 * 1_024 * 1_024
    static let maxTotalSize: Int64 = 2 * 1_024 * 1_024 * 1_024

    private(set) var indexes: [(container: ArchiveEntry, search: SearchIndex)] = []
    private(set) var pending: Int
    /// Inner archives that couldn't be read (a password, damage) or were over the limits.
    var skipped: Int { omissions.count }
    private(set) var omissions: [NestedSearchOmission] = []
    private let candidates: [ArchiveEntry]

    init(archive: Archive) {
        let all = archive.index.visible.filter { !$0.isFolder && $0.kind == .archive }.sorted { $0.path < $1.path }
        let partition = Self.partition(all)
        candidates = partition.picked
        omissions = partition.omitted
        pending = candidates.count
    }

    /// The inner archives that fit the limits, in path order.
    static func within(_ archives: [ArchiveEntry]) -> [ArchiveEntry] {
        partition(archives).picked
    }

    private static func partition(_ archives: [ArchiveEntry]) -> (picked: [ArchiveEntry], omitted: [NestedSearchOmission]) {
        var total: Int64 = 0
        var picked: [ArchiveEntry] = []
        var omitted: [NestedSearchOmission] = []
        for entry in archives {
            let reason: NestedSearchOmission.Reason?
            if picked.count >= maxArchives { reason = .archiveCountLimit }
            else if entry.size > maxArchiveSize { reason = .archiveSizeLimit }
            else if entry.size > maxTotalSize - total { reason = .totalSizeLimit }
            else { reason = nil }
            if let reason {
                omitted.append(NestedSearchOmission(container: entry, reason: reason))
            } else {
                total += max(0, entry.size)
                picked.append(entry)
            }
        }
        return (picked, omitted)
    }

    var isLoading: Bool { pending > 0 }
    var isEmpty: Bool { candidates.isEmpty }

    /// Lists every inner archive in turn; `progress` runs after each so results can grow.
    func load(in archive: Archive, with loader: Loader, progress: @MainActor () -> Void) async {
        for container in candidates {
            guard !Task.isCancelled else { return }
            do {
                let entries = try await loader(container, archive)
                guard !Task.isCancelled else { return }
                let search = SearchIndex(total: entries.count)
                await search.build(entries) { _ in }
                guard !Task.isCancelled else { return }
                indexes.append((container, search))
            } catch {
                let failure = EngineError(error).failure
                guard !Task.isCancelled, !(error is CancellationError), failure != .cancelled else { return }
                let reason: NestedSearchOmission.Reason =
                    failure == .passwordRequired || failure == .wrongPassword ? .passwordRequired : .readFailure
                omissions.append(NestedSearchOmission(container: container, reason: reason))
            }
            pending -= 1
            progress()
        }
    }

    /// Matches inside the inner archives read so far, grouped by archive in path order.
    func search(_ query: String, includingHelpers: Bool) async -> [NestedHit] {
        var hits: [NestedHit] = []
        for (container, search) in indexes {
            guard !Task.isCancelled else { return [] }
            hits += await search.search(query, includingHelpers: includingHelpers).map { NestedHit(container: container, inner: $0) }
        }
        return hits
    }
}
