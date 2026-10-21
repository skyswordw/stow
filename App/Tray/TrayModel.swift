import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// One thing on the Tray: a real file or folder, or a sample row for design review.
struct TrayItem: Identifiable, Hashable {
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
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        let folder = values?.isDirectory == true && values?.isPackage != true
        self.init(name: url.lastPathComponent, size: url.fileSize, url: url, isFolder: folder)
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

    /// Where Collect into a Folder puts the folder: beside the first item.
    static func collectionParent(for urls: [URL]) -> URL? {
        urls.first?.deletingLastPathComponent()
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
