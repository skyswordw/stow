import AppKit

/// Folders people have allowed Stow to write in, so Extract Here and Quick Compress can put
/// results next to the original while Stow stays sandboxed.
///
/// The first time a Finder action needs a folder Stow has no access to, Stow shows an Open panel
/// already pointing at that folder and says why; choosing Allow grants that folder and everything
/// inside it, remembered as a security-scoped bookmark. Nothing broader is ever asked for, and
/// grants can be removed in Settings › Integration. (See README › Sandbox and Finder actions.)
@Observable
final class FolderAccess {
    static let shared = FolderAccess()

    enum Purpose {
        case extract(String)
        case compress
        case open(String)

        var message: String {
            switch self {
            case .extract(let name): "Stow can only write in folders you allow. Choose Allow to let Stow extract “\(name)” here — and next time, extract anything in this folder without asking."
            case .compress: "Stow can only write in folders you allow. Choose Allow to let Stow save the archive here — and next time, compress anything in this folder without asking."
            case .open(let name): "Choose Allow to let Stow open “\(name)” and other archives in this folder."
            }
        }
    }

    /// Granted folders whose scope is active (they stay active while Stow runs).
    private(set) var grants: [URL] = []
    private let defaults: UserDefaults
    private static let key = "FolderGrants"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var stale: [Data] = []
        for data in defaults.array(forKey: Self.key) as? [Data] ?? [] {
            var isStale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &isStale),
                  url.startAccessingSecurityScopedResource() else {
                stale.append(data)
                continue
            }
            grants.append(url)
        }
        if !stale.isEmpty { save() }
    }

    /// Whether Stow can already write in `folder` (granted, picked this session, or its own).
    func canWrite(in folder: URL) -> Bool {
        FileManager.default.isWritableFile(atPath: folder.path)
    }

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

    func revoke(_ folder: URL) {
        guard let index = grants.firstIndex(of: folder) else { return }
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
        panel.message = purpose.message
        NSApp.activate()
        guard panel.runModal() == .OK, let chosen = panel.url else { return nil }
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
}
