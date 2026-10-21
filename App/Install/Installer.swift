import AppKit
import CoreText

/// The install Next Steps: an app into Applications (or a disk image's "drag here" folder), fonts
/// into the person's font library, and installer packages handed to Installer.
///
/// Everything goes through `Extraction.stage` first, so the engine has extracted and both sides have
/// audited before anything is judged or moved; nothing appears half-copied.
enum Installer {
    /// What the person is asked before going on. `.alternate` is the second button (Skip, Keep Both).
    enum Question {
        case signature(app: String, verdict: CodeSignature.Verdict)
        case replaceApp(app: String, installed: String?, incoming: String?)
        case replaceFonts([String])
    }

    enum Answer { case proceed, alternate, cancel }

    typealias Ask = (Question) async -> Answer

    struct AppOutcome {
        let app: URL
        let verdict: CodeSignature.Verdict
        let replaced: Bool
        /// Nil when removal wasn't asked for.
        let quarantineRemoved: Bool?
    }

    struct FontOutcome {
        var installed: [URL] = []
        var replaced = 0
        var skipped: [String] = []
        /// Not fonts macOS can use (e.g. web fonts).
        var unusable: [String] = []
    }

    // MARK: - Apps

    static func installApp(_ entry: ArchiveEntry, from archive: Archive, into folder: URL, removeQuarantine: Bool,
                           ask: Ask, onProgress: @escaping @Sendable (Double) -> Void) async throws(EngineError) -> AppOutcome {
        let staged = try await Extraction.stage(archive, selection: [entry], near: folder, onProgress: onProgress)
        defer { staged.discard() }
        let bundle = staged.url(for: entry)
        guard Extraction.exists(bundle) else { throw EngineError(.failed, String(localized: "“\(entry.name)” wasn’t extracted.")) }

        let verdict = await assess(bundle)
        if verdict.needsConfirmation {
            guard await ask(.signature(app: entry.name, verdict: verdict)) == .proceed else { throw EngineError(.cancelled) }
        }

        let target = folder.appending(path: entry.name)
        let replacing = Extraction.exists(target)
        if replacing {
            if isRunning(target) {
                throw EngineError(.failed, String(localized: "“\(displayName(entry.name))” is open. Quit it, then install again."))
            }
            let answer = await ask(.replaceApp(app: entry.name, installed: version(of: target), incoming: version(of: bundle)))
            if answer == .cancel { throw EngineError(.cancelled) }
            if answer == .alternate {
                // Keep Both: the new copy gets a number, the installed one stays as it is.
                let placement = try await Placement.place([(bundle, entry.name)], in: folder)
                if !removeQuarantine, let source = archive.source?.url { Quarantine.inherit(from: source, to: placement.placed[0]) }
                return AppOutcome(app: placement.placed[0], verdict: verdict, replaced: false,
                                  quarantineRemoved: removeQuarantine ? Quarantine.remove(under: placement.placed[0]) : nil)
            }
        }
        let placement = try await Placement.place([(bundle, entry.name)], in: folder) { _ in .replace }
        guard let app = placement.placed.first else { throw EngineError(.failed, String(localized: "Nothing was installed.")) }
        // After the move: renaming into place drops a flag set in staging.
        if !removeQuarantine, let source = archive.source?.url { Quarantine.inherit(from: source, to: app) }
        return AppOutcome(app: app, verdict: verdict, replaced: replacing,
                          quarantineRemoved: removeQuarantine ? Quarantine.remove(under: app) : nil)
    }

    @concurrent
    private static func assess(_ bundle: URL) async -> CodeSignature.Verdict {
        CodeSignature.assess(bundle)
    }

    private static func isRunning(_ app: URL) -> Bool {
        let path = app.standardizedFileURL.resolvingSymlinksInPath().path
        return NSWorkspace.shared.runningApplications.contains {
            $0.bundleURL?.standardizedFileURL.resolvingSymlinksInPath().path == path
        }
    }

    static func version(of app: URL) -> String? {
        let info = NSDictionary(contentsOf: app.appending(path: "Contents/Info.plist"))
        return info?["CFBundleShortVersionString"] as? String
    }

    static func displayName(_ bundleName: String) -> String {
        bundleName.hasSuffix(".app") ? String(bundleName.dropLast(4)) : bundleName
    }

    // MARK: - Fonts

    static func installFonts(_ entries: [ArchiveEntry], from archive: Archive, into folder: URL,
                             ask: Ask, onProgress: @escaping @Sendable (Double) -> Void) async throws(EngineError) -> FontOutcome {
        let staged = try await Extraction.stage(archive, selection: entries, near: folder, onProgress: onProgress)
        defer { staged.discard() }
        var outcome = FontOutcome()
        var fonts: [(URL, String)] = []
        for (url, name) in staged.items(allFolder: .automatic, folderName: "") {
            if isUsableFont(url) { fonts.append((url, name)) } else { outcome.unusable.append(name) }
        }
        guard !fonts.isEmpty else {
            throw EngineError(.failed, outcome.unusable.count == 1
                ? String(localized: "“\(outcome.unusable[0])” isn’t a font macOS can install.")
                : String(localized: "None of these are fonts macOS can install."))
        }

        let taken = fonts.map(\.1).filter { Extraction.exists(folder.appending(path: $0)) }
        var resolution = Placement.Resolution.replace
        if !taken.isEmpty {
            switch await ask(.replaceFonts(taken)) {
            case .proceed: resolution = .replace
            case .alternate: resolution = .skip
            case .cancel: throw EngineError(.cancelled)
            }
        }
        let placement = try await Placement.place(fonts, in: folder) { _ in resolution }
        outcome.installed = placement.placed
        outcome.replaced = placement.replaced
        outcome.skipped = resolution == .skip ? taken : []
        return outcome
    }

    /// OpenType, TrueType and collections Core Text can read; web fonts (WOFF2) are not installable.
    static func isUsableFont(_ url: URL) -> Bool {
        guard ["otf", "ttf", "ttc", "otc", "dfont"].contains(url.pathExtension.lowercased()) else { return false }
        return ((CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor]) ?? []).count > 0
    }

    // MARK: - Packages

    /// Extracts the package into a hidden folder beside the archive (Installer refuses packages a
    /// sandboxed app wrote into its own container) and opens it in Installer, which shows its
    /// signature and asks for an administrator password itself. The copy is removed when Installer quits.
    static func openInstaller(_ entry: ArchiveEntry, from archive: Archive, near location: URL,
                              onProgress: @escaping @Sendable (Double) -> Void) async throws(EngineError) -> URL {
        let folder = try PackageHandoff.makeFolder(in: location)
        do {
            let result = try await Extraction.run(archive, selection: [entry], to: folder, onProgress: onProgress)
            guard let package = result.placed.first else { throw EngineError(.failed, String(localized: "“\(entry.name)” wasn’t extracted.")) }
            try await PackageHandoff.open(package)
            return package
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw EngineError(error)
        }
    }
}

/// Removing `com.apple.quarantine` skips Gatekeeper's first-open check. Off unless asked for.
enum Quarantine {
    static let attribute = "com.apple.quarantine"

    static func isQuarantined(_ url: URL) -> Bool {
        getxattr(url.path, attribute, nil, 0, 0, XATTR_NOFOLLOW) >= 0
    }

    /// Like Archive Utility: an app from a downloaded archive stays "downloaded", so Gatekeeper
    /// checks it the first time it opens. Goes through Launch Services' quarantine properties —
    /// the sandbox refuses a raw `setxattr` of the flag. Returns whether the app is quarantined.
    @discardableResult
    static func inherit(from archive: URL, to root: URL) -> Bool {
        guard let properties = try? archive.resourceValues(forKeys: [.quarantinePropertiesKey]).quarantineProperties,
              !properties.isEmpty else { return isQuarantined(root) }
        if !isQuarantined(root) {
            var values = URLResourceValues()
            values.quarantineProperties = properties
            var target = root
            try? target.setResourceValues(values)
        }
        return isQuarantined(root)
    }

    /// Archive Utility's rule for downloads: everything that came out of a quarantined archive is
    /// quarantined too — files and bundles, not the folders around them. Only `added` items, never
    /// files that were already in a merged folder.
    static func propagate(from archive: URL, to added: [URL]) {
        guard isQuarantined(archive) else { return }
        for item in added {
            guard Placement.isPlainFolder(item) else {
                inherit(from: archive, to: item)
                continue
            }
            guard let walker = FileManager.default.enumerator(at: item, includingPropertiesForKeys: [.isPackageKey, .isRegularFileKey]) else { continue }
            for case let url as URL in walker {
                let values = try? url.resourceValues(forKeys: [.isPackageKey, .isRegularFileKey])
                if values?.isPackage == true {
                    inherit(from: archive, to: url)
                    walker.skipDescendants()
                } else if values?.isRegularFile == true {
                    inherit(from: archive, to: url)
                }
            }
        }
    }

    /// Removes the flag from `root` and everything inside it. False if macOS refused for any item —
    /// a sandboxed app may not be allowed to; the app then simply gets Gatekeeper's normal check.
    static func remove(under root: URL) -> Bool {
        var paths = [root.path]
        if let walker = FileManager.default.enumerator(atPath: root.path) {
            paths += walker.compactMap { $0 as? String }.map { root.path + "/" + $0 }
        }
        var removedAll = true
        for path in paths where getxattr(path, attribute, nil, 0, 0, XATTR_NOFOLLOW) >= 0 {
            if removexattr(path, attribute, XATTR_NOFOLLOW) != 0 { removedAll = false }
        }
        return removedAll
    }
}

/// Packages waiting in Installer, each in a hidden folder beside its archive.
enum PackageHandoff {
    /// Each copy with the (security-scoped) folder it sits in, held open until the copy is removed.
    private static var waiting: [(folder: URL, scope: URL, scoped: Bool)] = []
    private static var observer: NSObjectProtocol?

    static func makeFolder(in location: URL) throws(EngineError) -> URL {
        let folder = location.appending(path: ".stow-installer-\(UUID().uuidString)", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        } catch {
            throw EngineError(.failed, String(localized: "Couldn’t prepare the installer: \(error.localizedDescription)"))
        }
        waiting.append((folder, location, location.startAccessingSecurityScopedResource()))
        return folder
    }

    static func open(_ package: URL) async throws(EngineError) {
        guard let installer = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.installer") else {
            throw EngineError(.failed, String(localized: "Installer isn’t available on this Mac."))
        }
        watchInstaller()
        do {
            _ = try await NSWorkspace.shared.open([package], withApplicationAt: installer,
                                                  configuration: NSWorkspace.OpenConfiguration())
        } catch {
            throw EngineError(.failed, String(localized: "Installer couldn’t open “\(package.lastPathComponent)”: \(error.localizedDescription)"))
        }
    }

    /// Removes the copies once Installer quits, and when Stow quits.
    static func removeAll() {
        for (folder, scope, scoped) in waiting {
            try? FileManager.default.removeItem(at: folder)
            if scoped { scope.stopAccessingSecurityScopedResource() }
        }
        waiting.removeAll()
    }

    private static func watchInstaller() {
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == "com.apple.installer" else { return }
            MainActor.assumeIsolated { removeAll() }
        }
    }
}

/// Items extracted only to be opened in their default app. Kept until Stow next launches, since
/// the app that opened them may still be using them.
enum TemporaryOpen {
    private static let parent = FileManager.default.temporaryDirectory.appending(path: "Opened", directoryHint: .isDirectory)

    static func makeFolder() -> URL {
        let folder = parent.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func removeAll() {
        try? FileManager.default.removeItem(at: parent)
    }
}
