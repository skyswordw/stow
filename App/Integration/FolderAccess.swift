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

    enum Purpose {
        case extract(String)
        case compress
        case open(String)
        /// Installs and other one-off writes say what they're for in their own words.
        case explained(String)

        func message(for folder: URL) -> String {
            switch self {
            case .extract(let name): "Stow can only write in folders you allow. Choose Allow to let Stow extract “\(name)” here — and next time, extract anything in this folder without asking."
            case .compress: "Stow can only write in folders you allow. Choose Allow to let Stow save the archive here — and next time, compress anything in this folder without asking."
            case .open(let name): "Choose Allow to let Stow open “\(name)” and other archives in this folder."
            case .explained(let reason): "\(reason) Stow asks once for “\(FileManager.default.displayName(atPath: folder.path))” and remembers it."
            }
        }
    }

    /// Granted folders whose scope is active (they stay active while Stow runs).
    private(set) var grants: [URL] = []
    private let defaults: UserDefaults
    private static let key = "FolderGrants"
    /// Where the install flow kept its grants before there was one list.
    private static let legacyInstallKey = "install.folderBookmarks"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var stored = defaults.array(forKey: Self.key) as? [Data] ?? []
        let legacy = (defaults.dictionary(forKey: Self.legacyInstallKey) as? [String: Data]).map { Array($0.values) } ?? []
        stored += legacy
        var dropped = !legacy.isEmpty
        for data in stored {
            var isStale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI],
                                     bookmarkDataIsStale: &isStale),
                  !grants.contains(url), url.startAccessingSecurityScopedResource() else {
                dropped = true
                continue
            }
            if isStale { dropped = true }
            grants.append(url)
        }
        if dropped {
            grants = Self.minimal(grants)
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

    /// Whether a remembered grant covers `folder`.
    func covers(_ folder: URL) -> Bool {
        grants.contains { PathContainment.isInside(folder.standardizedFileURL.path, root: $0.standardizedFileURL.path) }
    }

    func revoke(_ folder: URL) {
        let path = folder.standardizedFileURL.path
        guard let index = grants.firstIndex(where: { $0.standardizedFileURL.path == path }) else { return }
        grants[index].stopAccessingSecurityScopedResource()
        grants.remove(at: index)
        save()
    }

    private func ask(for folder: URL, purpose: Purpose) async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = folder
        panel.prompt = "Allow"
        panel.title = "Allow Access to “\(FileManager.default.displayName(atPath: folder.path))”"
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
        guard !grants.contains(folder), folder.startAccessingSecurityScopedResource() else { return }
        grants.append(folder)
        // A grant inside another is redundant.
        grants = Self.minimal(grants)
        save()
    }

    private func save() {
        let data = grants.compactMap { try? $0.bookmarkData(options: .withSecurityScope) }
        defaults.set(data, forKey: Self.key)
    }

    /// Drops folders already covered by another grant.
    static func minimal(_ folders: [URL]) -> [URL] {
        folders.filter { folder in
            !folders.contains { other in
                other != folder && PathContainment.isInside(folder.path, root: other.path)
            }
        }
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
            throw EngineError(.failed, "This account can’t add things to “\(name)”. Ask an administrator, or install somewhere else.")
        }
        return Grant(url: url, scoped: scoped)
    }

    /// Whether a grant for `folder` is remembered.
    static func isRemembered(_ folder: URL) -> Bool { shared.covers(folder) }

    static func forget(_ folder: URL) { shared.revoke(folder) }
}
