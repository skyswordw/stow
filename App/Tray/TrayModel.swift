import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Collect publishes one complete directory. Failed copies stay private and are removed;
/// an exclusive rename never replaces a destination created while the inputs were copying.
nonisolated enum TrayCollection {
    struct RetainedCopies: Error {
        let folder: URL
        let copyError: any Error
        let cleanupError: any Error
    }

    struct RecursiveDestination: LocalizedError {
        var errorDescription: String? {
            String(localized: "Choose a destination outside the folders being collected.")
        }
    }

    static func copy(_ urls: [URL], named name: String, into parent: URL,
                     fileManager: FileManager = .default) throws -> URL {
        let resolvedParent = parent.resolvingSymlinksInPath().standardizedFileURL.path
        for url in urls {
            let source = url.resolvingSymlinksInPath().standardizedFileURL
            if (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
               resolvedParent == source.path || resolvedParent.hasPrefix(source.path + "/") {
                throw RecursiveDestination()
            }
        }
        let destination = parent.appending(path: name, directoryHint: .isDirectory)
        let staging = parent.appending(path: ".stow-collect-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
        do {
            for url in urls {
                let child = TrayRules.freeName(url.lastPathComponent, in: staging, fileManager: fileManager)
                try fileManager.copyItem(at: url, to: staging.appending(path: child))
            }
            guard renamex_np(staging.path, destination.path, UInt32(RENAME_EXCL)) == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            return destination
        } catch {
            let copyError = error
            do { try fileManager.removeItem(at: staging) }
            catch { throw RetainedCopies(folder: staging, copyError: copyError, cleanupError: error) }
            throw copyError
        }
    }
}

/// One thing on the Tray: a real file or folder, or a sample row for design review.
nonisolated struct TrayItem: Identifiable, Hashable, Sendable {
    let id = UUID()
    var name: String
    var size: Int64
    var url: URL?
    var isFolder = false

    init(name: String, size: Int64, url: URL? = nil, isFolder: Bool = false) {
        self.name = name
        self.size = size
        self.url = url
        self.isFolder = isFolder
    }

    init(url: URL) {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .fileSizeKey])
        let folder = values?.isDirectory == true && values?.isPackage != true
        self.init(name: url.lastPathComponent, size: Int64(values?.fileSize ?? 0), url: url, isFolder: folder)
    }

    var contentType: UTType {
        if isFolder { return .folder }
        return UTType(filenameExtension: (name as NSString).pathExtension) ?? .data
    }

    var isArchive: Bool { ArchiveTypes.type(forFileName: name) != nil }
}

/// The Tray's border, chosen in Settings › General.
nonisolated enum TrayBorder: String, CaseIterable, Identifiable, Sendable {
    case accent, blue, green, pink, purple, graphite
    var id: Self { self }

    var title: String {
        switch self {
        case .accent: String(localized: "Accent")
        case .blue: String(localized: "Blue")
        case .green: String(localized: "Green")
        case .pink: String(localized: "Pink")
        case .purple: String(localized: "Purple")
        case .graphite: String(localized: "Graphite")
        }
    }

    var color: Color {
        switch self {
        case .accent: .accentColor
        case .blue: .blue
        case .green: .green
        case .pink: .pink
        case .purple: .purple
        case .graphite: .gray
        }
    }
}

/// Pure rules the Tray follows; kept apart from AppKit so they can be tested.
nonisolated enum TrayRules {
    /// Idle times offered in Settings, in seconds; 0 means never hide by itself.
    static let idleChoices: [Int] = [0, 10, 30, 60, 300]

    /// Whether an unpinned Tray should tuck itself away now.
    static func shouldHide(lastActivity: Date, now: Date, idleSeconds: Int, pinned: Bool,
                           isDragging: Bool, isHovered: Bool) -> Bool {
        guard idleSeconds > 0, !pinned, !isDragging, !isHovered else { return false }
        return now.timeIntervalSince(lastActivity) >= TimeInterval(idleSeconds)
    }

    /// New URLs to append, skipping ones already there (by standardized path) and repeats.
    static func newURLs(_ urls: [URL], existing: [URL]) -> [URL] {
        var seen = Set(existing.map { $0.standardizedFileURL.path })
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    /// The items a drop or Add Files… named, whether they were just added or already on the Tray.
    static func matching(_ urls: [URL], in items: [TrayItem]) -> Set<UUID> {
        let paths = Set(urls.map { $0.standardizedFileURL.path })
        return Set(items.filter { $0.url.map { paths.contains($0.standardizedFileURL.path) } ?? false }.map(\.id))
    }

    /// Click selection, Finder style: plain replaces, ⌘ toggles, ⇧ extends from the anchor.
    static func select(_ id: UUID, in order: [UUID], current: Set<UUID>, anchor: UUID?,
                       command: Bool, shift: Bool) -> (selection: Set<UUID>, anchor: UUID?) {
        if shift, let anchor, let from = order.firstIndex(of: anchor), let to = order.firstIndex(of: id) {
            let range = Set(order[min(from, to)...max(from, to)])
            return (command ? current.union(range) : range, anchor)
        }
        if command {
            var next = current
            if next.contains(id) { next.remove(id) } else { next.insert(id) }
            return (next, id)
        }
        return ([id], id)
    }

    /// "New Folder", "New Folder 2", … — the first name not already in `folder`.
    static func freeName(_ base: String, in folder: URL, fileManager: FileManager = .default) -> String {
        var name = base, number = 1
        while fileManager.fileExists(atPath: folder.appending(path: name).path) {
            number += 1
            name = "\(base) \(number)"
        }
        return name
    }

    /// The folder's children, folders first, then by name — what browsing into a folder shows.
    static func children(of folder: URL, fileManager: FileManager = .default) -> [TrayItem] {
        let urls = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                                                         options: [.skipsHiddenFiles])) ?? []
        return urls.map(TrayItem.init(url:)).sorted {
            if $0.isFolder != $1.isFolder { return $0.isFolder }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}
