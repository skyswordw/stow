import AppKit

/// Archives people opened, newest first: the welcome window's Recent list and File › Open Recent.
///
/// Stow is sandboxed, so each entry keeps a security-scoped bookmark made while the archive was
/// open; reopening resolves it, which also follows a file that was moved or renamed. Entries whose
/// file is gone (or in the Trash) are hidden rather than forgotten: a disconnected drive can come back.
/// NSDocumentController's recents aren't used: Stow has no NSDocument, and its list can't be read
/// back for the welcome window without going through its own menu.
@Observable
final class RecentArchives {
    struct Entry: Codable, Identifiable, Equatable {
        var path: String
        var openedAt: Date
        var bookmark: Data?

        var id: String { path }
        var url: URL { URL(filePath: path) }
        var name: String { url.lastPathComponent }
        var folder: URL { url.deletingLastPathComponent() }
    }

    static let limit = 10
    static let key = "recent.archives"

    /// Every remembered archive, newest first, including ones that are missing right now.
    private(set) var entries: [Entry] = []
    /// Paths found missing at the last `refresh()`.
    private var missing: Set<String> = []
    /// Nil keeps the list in memory only (demo scenes, previews).
    private let defaults: UserDefaults?
    /// Showing `preview` entries: their files don't exist, so they're never checked.
    private var isPreview = false

    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        if let data = defaults?.data(forKey: Self.key),
           let stored = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = stored
        }
        refresh()
    }

    /// What the welcome window and the menu show.
    var visible: [Entry] { entries.filter { !missing.contains($0.path) } }

    /// Puts `url` at the top. Call while the archive's security scope is active, so the bookmark
    /// can carry it.
    func add(_ url: URL, at date: Date = .now) {
        let path = Self.key(for: url)
        let bookmark = (try? url.bookmarkData(options: .withSecurityScope)) ?? (try? url.bookmarkData())
        entries.removeAll { $0.path == path }
        entries.insert(Entry(path: path, openedAt: date, bookmark: bookmark), at: 0)
        entries = Array(entries.prefix(Self.limit))
        missing.remove(path)
        save()
    }

    func remove(_ entry: Entry) {
        entries.removeAll { $0.path == entry.path }
        save()
    }

    func clear() {
        isPreview = false
        entries = []
        missing = []
        save()
    }

    /// Follows moved files and notes which ones are gone. Cheap: at most `limit` bookmarks.
    func refresh() {
        guard !isPreview else { return }
        var seen: Set<String> = []
        var changed = false
        var refreshed: [Entry] = []
        missing = []
        for var entry in entries {
            if let (url, isStale) = Self.resolve(entry) {
                let path = Self.key(for: url)
                if path != entry.path || isStale {
                    entry.path = path
                    if let fresh = Self.withScope(url, { try? $0.bookmarkData(options: .withSecurityScope) }) {
                        entry.bookmark = fresh
                    }
                    changed = true
                }
            }
            // Two entries can end up pointing at the same file once a move is followed.
            guard seen.insert(entry.path).inserted else { changed = true; continue }
            if !Self.exists(entry) { missing.insert(entry.path) }
            refreshed.append(entry)
        }
        entries = refreshed
        if changed { save() }
    }

    /// The URL to open, with its security scope ready to be claimed. Nil when the file is gone.
    func url(for entry: Entry) -> URL? {
        let url = Self.resolve(entry)?.url ?? entry.url
        guard Self.withScope(url, { FileManager.default.fileExists(atPath: $0.path) }), !Self.isInTrash(url) else {
            missing.insert(entry.path)
            return nil
        }
        return url
    }

    /// Fake entries for design review; nothing is saved and nothing is checked on disk.
    func preview(_ items: [(path: String, openedAt: Date)]) {
        entries = items.map { Entry(path: $0.path, openedAt: $0.openedAt) }
        missing = []
        isPreview = true
    }

    private func save() {
        guard let defaults else { return }
        if entries.isEmpty {
            defaults.removeObject(forKey: Self.key)
        } else if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: Self.key)
        }
    }

    // MARK: - Files

    /// One spelling per file: /var and /private/var, `..` and `.` all name the same archive.
    static func key(for url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func resolve(_ entry: Entry) -> (url: URL, isStale: Bool)? {
        guard let bookmark = entry.bookmark else { return nil }
        var isStale = false
        for options: URL.BookmarkResolutionOptions in [[.withSecurityScope, .withoutUI], [.withoutUI]] {
            if let url = try? URL(resolvingBookmarkData: bookmark, options: options, bookmarkDataIsStale: &isStale) {
                return (url, isStale)
            }
        }
        return nil
    }

    private static func exists(_ entry: Entry) -> Bool {
        let url = resolve(entry)?.url ?? entry.url
        return !isInTrash(url) && withScope(url) { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// A trashed archive's bookmark still resolves; people think of it as gone.
    private static func isInTrash(_ url: URL) -> Bool {
        url.pathComponents.contains(".Trash") || url.pathComponents.contains(".Trashes")
    }

    private static func withScope<T>(_ url: URL, _ body: (URL) -> T) -> T {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return body(url)
    }
}

extension RecentArchives.Entry {
    /// "~/Downloads" — the real home, not the sandbox container's.
    var folderDisplay: String {
        let home = FolderAccess.home.standardizedFileURL.path
        let path = folder.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    /// Relative date; anything under a minute reads "now" rather than counting seconds.
    func openedDisplay(now: Date = .now) -> String {
        let date = now.timeIntervalSince(openedAt) < 60 ? now : openedAt
        return date.formatted(.relative(presentation: .named, unitsStyle: .wide))
    }
}
