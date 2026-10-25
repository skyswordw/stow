import Foundation

/// Where a folder or archive made from gathered items goes: Collect into a Folder and Pack's
/// Save Here follow the same rule, so people can tell in advance.
///
/// - Every item from one folder: that folder.
/// - Items from several folders: the folder people last chose for such a mix, if any. Otherwise
///   there is no default and people choose; Stow doesn't guess among the folders.
nonisolated enum GatherDestination {
    /// A folder the items come from, and how many of them.
    struct Source: Equatable, Sendable {
        let folder: URL
        let count: Int
    }

    /// The folders the items live in, in the order they first appear.
    static func sources(of urls: [URL]) -> [Source] {
        var order: [URL] = []
        var counts: [String: Int] = [:]
        for url in urls {
            let folder = url.standardizedFileURL.deletingLastPathComponent()
            if counts[folder.path] == nil { order.append(folder) }
            counts[folder.path, default: 0] += 1
        }
        return order.map { Source(folder: $0, count: counts[$0.path] ?? 0) }
    }

    /// The folder to suggest; nil means ask.
    static func suggestion(for urls: [URL], remembered: URL?) -> URL? {
        let sources = sources(of: urls)
        if sources.count == 1 { return sources[0].folder }
        return sources.isEmpty ? nil : remembered
    }

    /// A remembered choice, not a preference, so Reset All Settings leaves it (see `SettingsKeys.resettable`).
    static let key = "destination.severalFolders"

    static func remembered(in store: UserDefaults = .standard) -> URL? {
        guard let path = store.string(forKey: key), !path.isEmpty else { return nil }
        return URL(filePath: path, directoryHint: .isDirectory)
    }

    /// Remembers `folder` only for items from several folders: choosing for one folder's items
    /// says nothing about where a mix should go.
    static func remember(_ folder: URL, for urls: [URL], in store: UserDefaults = .standard) {
        guard sources(of: urls).count > 1 else { return }
        store.set(folder.standardizedFileURL.path, forKey: key)
    }

    /// "~/Desktop/Field Trip" — how a folder is told apart from another of the same name.
    static func abbreviated(_ folder: URL) -> String {
        let path = folder.standardizedFileURL.path, home = realHome
        return path == home || path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    /// The person's real home, as `FolderAccess.home` finds it (the sandbox points `NSHomeDirectory()` into the container).
    private static var realHome: String {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir { return String(cString: dir) }
        return NSHomeDirectory()
    }
}
