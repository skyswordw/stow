import AppKit

/// Folders people have allowed Stow to write in. Stow is sandboxed: Extract Here and Quick Compress
/// put results next to the original, and installs go to /Applications, ~/Library/Fonts or a disk
/// image's "drag here" folder — all places a sandboxed app can't write by default.
///
/// The first time something needs such a folder, Stow shows an Open panel already pointing at it
/// and says why; choosing Allow grants that folder and everything inside it, remembered as a
/// security-scoped bookmark. Choosing a different folder uses it once and remembers nothing.
/// There is one list of grants for every feature, shown (with Remove) in Settings › Integration.
/// No helper, no Full Disk Access. (See README › Sandbox and Finder actions, Installing from a sandbox.)
@Observable
final class FolderAccess {
    static let shared = FolderAccess()

    /// Injectable OS boundary for bookmark persistence and balanced scope-lifetime tests.
    struct Bookmarks {
        var resolve: @MainActor (Data) throws -> (url: URL, stale: Bool)
        var create: @MainActor (URL) throws -> Data
        var start: @MainActor (URL) -> Bool
        var stop: @MainActor (URL) -> Void

        static let live = Bookmarks(resolve: { data in
            var stale = false
            let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI],
                              bookmarkDataIsStale: &stale)
            return (url, stale)
        }, create: { try $0.bookmarkData(options: .withSecurityScope) },
        start: { $0.startAccessingSecurityScopedResource() }, stop: { $0.stopAccessingSecurityScopedResource() })
    }

    enum Purpose {
        case extract(String)
        case compress
        case open(String)
        /// Installs and other one-off writes say what they're for in their own words.
        case explained(String)

        func message(for folder: URL) -> String {
            switch self {
            case .extract(let name): String(localized: "Stow can only write in folders you allow. Choose Allow to let Stow extract “\(name)” here — and next time, extract anything in this folder without asking.")
            case .compress: String(localized: "Stow can only write in folders you allow. Choose Allow to let Stow save the archive here — and next time, compress anything in this folder without asking.")
            case .open(let name): String(localized: "Choose Allow to let Stow open “\(name)” and other archives in this folder.")
            case .explained(let reason): String(localized: "\(reason) Stow asks once for “\(FileManager.default.displayName(atPath: folder.path))” and remembers it.")
            }
        }
    }

    /// Granted folders whose scope is active (they stay active while Stow runs).
    private(set) var grants: [URL] = []

    /// The Settings demo substitutes only the displayed list, never active authorization.
    private var demoGrants: [URL]?
    var displayedGrants: [URL] { demoGrants ?? grants }

    /// The `settings` scene's `-StowLongLists YES`: fictional grants to lay out, never stored.
    func showGrantsForDemo(_ folders: [URL]) {
        demoGrants = folders
    }

    func removeDisplayedGrant(_ folder: URL) {
        if demoGrants != nil {
            demoGrants?.removeAll { $0 == folder }
        } else {
            revoke(folder)
        }
    }
    private let defaults: UserDefaults
    private let bookmarks: Bookmarks
    private static let key = "FolderGrants"
    /// Where the install flow kept its grants before there was one list.
    private static let legacyInstallKey = "install.folderBookmarks"

    init(defaults: UserDefaults = .standard, bookmarks: Bookmarks = .live) {
        self.defaults = defaults
        self.bookmarks = bookmarks
        var stored = defaults.array(forKey: Self.key) as? [Data] ?? []
        let legacy = (defaults.dictionary(forKey: Self.legacyInstallKey) as? [String: Data]).map { Array($0.values) } ?? []
        stored += legacy
        var dropped = !legacy.isEmpty
        for data in stored {
            guard let resolved = try? bookmarks.resolve(data),
                  !grants.contains(resolved.url), bookmarks.start(resolved.url) else {
                dropped = true
                continue
            }
            if resolved.stale { dropped = true }
            grants.append(resolved.url)
        }
        if dropped {
            save()
            defaults.removeObject(forKey: Self.legacyInstallKey)
        }
    }

    /// Whether Stow can write in `folder` right now — the sandbox's answer, not the permission
    /// bits, so it tries.
    func canWrite(in folder: URL) -> Bool { Self.canWrite(folder) }

    /// Makes `folder` writable, asking once if needed. Returns the folder to use: `folder` itself,
    /// or — if people chose a different folder in the panel — that one, for this time only.
    func writableFolder(_ folder: URL, for purpose: Purpose) async -> URL? {
        if canWrite(in: folder) { return folder }
        return await ask(for: folder, purpose: purpose)
    }

    /// Makes `file` readable, asking for its folder if needed.
    func readable(_ file: URL, for purpose: Purpose) async -> Bool {
        if FileManager.default.isReadableFile(atPath: file.path) { return true }
        let folder = file.deletingLastPathComponent()
        guard let granted = await ask(for: folder, purpose: purpose) else { return false }
        return granted == folder && FileManager.default.isReadableFile(atPath: file.path)
    }

    /// A first-volume grant does not authorize its siblings. The system panel grants the folder.
    func readableParts(in folder: URL) async -> Bool {
        let reason = String(localized: "Choose the folder containing all archive parts so Stow can read the complete archive.")
        guard let granted = await ask(for: folder, purpose: .explained(reason)) else { return false }
        return granted.standardizedFileURL == folder.standardizedFileURL
    }

    /// Whether a remembered grant covers `folder`.
    func covers(_ folder: URL) -> Bool {
        grants.contains { PathContainment.isInside(folder.standardizedFileURL.path, root: $0.standardizedFileURL.path) }
    }

    func revoke(_ folder: URL) {
        let path = folder.standardizedFileURL.path
        guard let index = grants.firstIndex(where: { $0.standardizedFileURL.path == path }) else { return }
        bookmarks.stop(grants[index])
        grants.remove(at: index)
        save()
    }

    /// Called only after source read-back succeeds. Build bookmarks before changing active grants,
    /// so a serialization failure leaves existing access intact and can be reported to the user.
    func rememberSourceFolder(_ folder: URL) throws {
        // An ancestor's sandbox grant does not supersede a protected descendant's explicit grant.
        // Replace only the same path, using the fresh picker URL when reauthorizing stale access.
        let retained = grants.filter { $0.standardizedFileURL.path != folder.standardizedFileURL.path } + [folder]
        let data = try retained.map(bookmarks.create)
        guard bookmarks.start(folder) else {
            throw CocoaError(.fileReadNoPermission)
        }
        for old in grants where old.standardizedFileURL.path == folder.standardizedFileURL.path { bookmarks.stop(old) }
        grants = retained
        defaults.set(data, forKey: Self.key)
    }

    private func ask(for folder: URL, purpose: Purpose) async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = folder
        panel.prompt = String(localized: "Allow")
        panel.title = String(localized: "Allow Access to “\(FileManager.default.displayName(atPath: folder.path))”")
        panel.message = purpose.message(for: folder)
        NSApp.activate()
        let response = if let window = NSApp.keyWindow {
            await panel.beginSheetModal(for: window)
        } else {
            panel.runModal()
        }
        guard response == .OK, let chosen = panel.url else { return nil }
        guard PathContainment.isInside(folder.standardizedFileURL.path, root: chosen.standardizedFileURL.path) else {
            return chosen // a different place: use it once, remember nothing
        }
        remember(chosen)
        return folder
    }

    private func remember(_ folder: URL) {
        guard !grants.contains(folder), bookmarks.start(folder) else { return }
        grants.append(folder)
        save()
    }

    private func save() {
        let data = grants.compactMap { try? bookmarks.create($0) }
        defaults.set(data, forKey: Self.key)
    }

    /// The sandbox's answer, not the file system's permission bits: try it.
    static func canWrite(_ folder: URL) -> Bool {
        let probe = folder.appending(path: ".stow-access-\(UUID().uuidString)")
        guard mkdir(probe.path, 0o700) == 0 else { return false }
        rmdir(probe.path)
        return true
    }
}

// MARK: - Installing

/// The install flows' view of the same grants: a folder to write into for the length of one step.
extension FolderAccess {
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

    /// Write access to `folder`: already writable (granted earlier), or asked for now. Declining
    /// throws `.cancelled`; a folder this account can't change (not an administrator) says so.
    static func request(_ folder: URL, purpose: String) async throws(EngineError) -> Grant {
        if canWrite(folder) { return Grant(url: folder, scoped: false) }
        guard let url = await shared.ask(for: folder, purpose: .explained(purpose)) else {
            throw EngineError(.cancelled)
        }
        let scoped = url != folder && url.startAccessingSecurityScopedResource()
        guard canWrite(url) else {
            if scoped { url.stopAccessingSecurityScopedResource() }
            shared.revoke(folder)
            let name = FileManager.default.displayName(atPath: url.path)
            throw EngineError(.failed, String(localized: "This account can’t add things to “\(name)”. Ask an administrator, or install somewhere else."))
        }
        return Grant(url: url, scoped: scoped)
    }

    /// Whether a grant for `folder` is remembered.
    static func isRemembered(_ folder: URL) -> Bool { shared.covers(folder) }

    static func forget(_ folder: URL) { shared.revoke(folder) }
}
