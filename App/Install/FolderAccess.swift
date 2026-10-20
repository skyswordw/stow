import AppKit

/// Stow is sandboxed: it can only write where someone pointed it. Installing needs a few fixed
/// folders — /Applications, ~/Library/Fonts, or whatever a disk image's "drag here" shortcut names —
/// so the first install into one asks once with an Open panel already showing that folder, and
/// remembers the answer as an app-scoped security-scoped bookmark. No helper, no Full Disk Access;
/// the grant covers that one folder and can be withdrawn with `forget(_:)`.
enum FolderAccess {
    /// A folder Stow may write to until `release()`.
    struct Grant {
        let url: URL
        fileprivate let scoped: Bool

        func release() {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
    }

    /// The person's real home (the sandbox points `NSHomeDirectory()` into the container).
    static var home: URL {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return URL(filePath: String(cString: dir), directoryHint: .isDirectory)
        }
        return URL(filePath: NSHomeDirectory(), directoryHint: .isDirectory)
    }

    static var applications: URL { URL(filePath: "/Applications", directoryHint: .isDirectory) }
    static var userFonts: URL { home.appending(path: "Library/Fonts", directoryHint: .isDirectory) }

    /// Tests and design review install into a scratch folder instead (`-StowInstallFolder <path>`).
    static var override: URL? {
        UserDefaults.standard.string(forKey: "StowInstallFolder").map { URL(filePath: $0, directoryHint: .isDirectory) }
    }

    /// Write access to `folder`: already writable, remembered, or asked for now. Declining throws
    /// `.cancelled`; a folder this account can't change (not an administrator) says so.
    static func request(_ folder: URL, purpose: String) async throws(EngineError) -> Grant {
        if canWrite(folder) { return Grant(url: folder, scoped: false) }
        if let remembered = remembered(folder) { return remembered }
        guard let grant = await ask(folder, purpose: purpose) else { throw EngineError(.cancelled) }
        guard canWrite(grant.url) else {
            grant.release()
            forget(folder)
            let name = FileManager.default.displayName(atPath: grant.url.path)
            throw EngineError(.failed, "This account can’t add things to “\(name)”. Ask an administrator, or install somewhere else.")
        }
        return grant
    }

    /// Whether a grant for `folder` is stored.
    static func isRemembered(_ folder: URL) -> Bool { bookmarks[key(folder)] != nil }

    static func forget(_ folder: URL) {
        var all = bookmarks
        all[key(folder)] = nil
        bookmarks = all
    }

    // MARK: -

    private static let defaultsKey = "install.folderBookmarks"

    private static var bookmarks: [String: Data] {
        get { UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Data] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    private static func key(_ folder: URL) -> String { folder.standardizedFileURL.path }

    private static func remembered(_ folder: URL) -> Grant? {
        guard let data = bookmarks[key(folder)] else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI],
                                 relativeTo: nil, bookmarkDataIsStale: &stale),
              url.startAccessingSecurityScopedResource() else {
            forget(folder)
            return nil
        }
        if stale { save(url, for: folder) }
        guard canWrite(url) else {
            url.stopAccessingSecurityScopedResource()
            forget(folder)
            return nil
        }
        return Grant(url: url, scoped: true)
    }

    private static func ask(_ folder: URL, purpose: String) async -> Grant? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = folder
        panel.prompt = "Allow"
        panel.message = "\(purpose) Stow asks once for “\(FileManager.default.displayName(atPath: folder.path))” and remembers it."
        let response = if let window = NSApp.keyWindow {
            await panel.beginSheetModal(for: window)
        } else {
            panel.runModal()
        }
        guard response == .OK, let chosen = panel.url else { return nil }
        // Someone may navigate elsewhere; a different folder is fine, it just isn't remembered for this one.
        let scoped = chosen.startAccessingSecurityScopedResource()
        if chosen.standardizedFileURL.path == folder.standardizedFileURL.path { save(chosen, for: folder) }
        return Grant(url: chosen, scoped: scoped)
    }

    private static func save(_ url: URL, for folder: URL) {
        guard let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil,
                                               relativeTo: nil) else { return }
        var all = bookmarks
        all[key(folder)] = data
        bookmarks = all
    }

    /// The sandbox's answer, not the file system's permission bits: try it.
    static func canWrite(_ folder: URL) -> Bool {
        let probe = folder.appending(path: ".stow-access-\(UUID().uuidString)")
        guard mkdir(probe.path, 0o700) == 0 else { return false }
        rmdir(probe.path)
        return true
    }
}
