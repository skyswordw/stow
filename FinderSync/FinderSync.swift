import AppKit
import FinderSync
import OSLog

/// Stow's items in Finder's context menu. The extension never opens the files: it posts the
/// selection under a one-time token into the App Group mailbox (pasteboard fallback for ad-hoc
/// builds) and opens `stow://handoff/<token>` (see Handoff.swift).
/// Finder calls in on the main thread, but FIFinderSync's methods aren't annotated.
nonisolated final class FinderSync: FIFinderSync {
    private static let log = Logger(subsystem: "app.stow.Stow.FinderSync", category: "menu")
    private let defaults = UserDefaults.standard

    override init() {
        super.init()
        // Everything; which volumes get the menu is decided per selection (FinderMenu).
        FIFinderSyncController.default().directoryURLs = [URL(filePath: "/")]
    }

    /// The app's latest settings (App Group file, else pasteboard), or the last ones this
    /// extension saw after a restart until Stow runs again.
    private var settings: FinderMenuSettings {
        if let published = FinderMenuSettings.published() {
            if let data = try? JSONEncoder().encode(published) { defaults.set(data, forKey: "FinderMenuSettings") }
            return published
        }
        return defaults.data(forKey: "FinderMenuSettings")
            .flatMap { try? JSONDecoder().decode(FinderMenuSettings.self, from: $0) } ?? FinderMenuSettings()
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems,
              let selection = FIFinderSyncController.default().selectedItemURLs() else { return nil }
        let actions = FinderMenu.actions(for: selection.map(\.path), settings: settings)
        guard !actions.isEmpty else { return nil }
        let selectors = actions.map(Self.selector(for:))
        nonisolated(unsafe) var menu: NSMenu?
        MainActor.assumeIsolated {
            let built = NSMenu(title: "Stow")
            for (action, selector) in zip(actions, selectors) {
                let item = NSMenuItem(title: FinderMenu.title(for: action), action: selector, keyEquivalent: "")
                item.image = NSImage(systemSymbolName: FinderMenu.symbol(for: action), accessibilityDescription: nil)
                built.addItem(item)
            }
            menu = built
        }
        return menu
    }

    private static func selector(for action: HandoffAction) -> Selector {
        switch action {
        case .extractHere: #selector(extractHere(_:))
        case .extractTo: #selector(extractTo(_:))
        case .open: #selector(openInStow(_:))
        case .compress: #selector(compress(_:))
        case .quickCompress: #selector(quickCompress(_:))
        }
    }

    @objc func extractHere(_ sender: AnyObject?) { send(.extractHere) }
    @objc func extractTo(_ sender: AnyObject?) { send(.extractTo) }
    @objc func openInStow(_ sender: AnyObject?) { send(.open) }
    @objc func compress(_ sender: AnyObject?) { send(.compress) }
    @objc func quickCompress(_ sender: AnyObject?) { send(.quickCompress) }

    private func send(_ action: HandoffAction) {
        guard let selection = FIFinderSyncController.default().selectedItemURLs(), !selection.isEmpty else { return }
        do {
            let url = try Handoff().send(HandoffRequest(action: action, paths: selection.map(\.path)))
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.open([url], withApplicationAt: Self.containingApp, configuration: configuration) { _, error in
                if let error { Self.log.error("Couldn’t reach Stow: \(error.localizedDescription, privacy: .public)") }
            }
        } catch {
            Self.log.error("Couldn’t post the request: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Stow.app, three levels above Contents/PlugIns/StowFinderSync.appex.
    private static var containingApp: URL {
        Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
}
