import AppKit
import OSLog

/// Receives what macOS hands Stow from outside: documents opened from Finder (double-click,
/// Open With, Quick Look's "Open in Stow"), `stow://` hand-offs and Services requests.
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var app: AppState? {
        didSet {
            guard oldValue !== app else { return }
            app?.tray.applySettings()
            flush()
        }
    }

    /// Arrived before the window (and its AppState) existed — e.g. Stow launched by a double-click
    /// or a Finder action.
    private var pending: [(AppState) -> Void] = []
    private var receivedExternalRequest = false
    private lazy var services = ServicesProvider { [weak self] job in self?.enqueue(job) }
    private let dockMenu = DockMenuController()

    private static let log = Logger(subsystem: "app.stow.Stow", category: "open")

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Before launching finishes, or a Services request that launched Stow times out.
        NSApp.servicesProvider = services
        NSUpdateDynamicServices()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        IntegrationSettings.shared.publishFinderSettings()
        // Starts Sparkle only in Developer ID release builds (UpdatePolicy); a relaunch into an
        // update waits until nothing is running.
        AppUpdater.shared.start { [weak self] in self?.app?.isBusy ?? false }
        let isDefault = (notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? NSNumber)?.boolValue ?? true
        Task { @MainActor [weak self] in
            guard let self, let app else { return }
            ApplicationLifecycle.shared.install(app: app, backgroundLaunch: !isDefault || receivedExternalRequest)
            DemoScene.apply(to: app)
            if app.usesBrowserWindow || app.glance.isShown {
                if !app.glance.isShown { app.showMainWindow() }
            } else if isDefault && !receivedExternalRequest {
                app.showMainWindow()
            }
            guard !OnboardingRouter.shared.didCheckAutomaticPresentation else { return }
            OnboardingRouter.shared.didCheckAutomaticPresentation = true
            if isDefault && !receivedExternalRequest && Onboarding.shouldShowAutomatically() {
                OnboardingRouter.shared.open()
            }
        }
    }

    /// The coordinator reevaluates after SwiftUI handovers and any pending work have settled.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private var checkingTermination = false
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !checkingTermination else { return .terminateLater }
        if app?.isBusy == true {
            if app?.archiveDraft?.isSaving == true || app?.archiveDraft?.isImporting == true {
                app?.showCreationWindow()
            } else {
                let busy = app?.archiveSessions.last(where: { $0.isBusy })
                busy?.presentArchive()
            }
            let alert = NSAlert()
            alert.messageText = String(localized: "An operation is still running")
            alert.informativeText = String(localized: "Wait for it to finish, or cancel it in Stow before quitting.")
            alert.addButton(withTitle: String(localized: "OK"))
            alert.runModal()
            return .terminateCancel
        }
        if let app, let draft = app.archiveDraft, draft.isEdited {
            app.showCreationWindow()
            guard draft.allowDiscardOrSave(quitting: true) else { return .terminateCancel }
            app.discardArchiveDraft()
        }
        let dirty = app?.archiveSessions.filter { $0.browser?.levels.contains(where: { $0.edits.isEdited }) == true } ?? []
        guard !dirty.isEmpty else { return .terminateNow }
        guard !checkingTermination else { return .terminateLater }
        checkingTermination = true
        Task {
            var allowed = true
            for session in dirty {
                session.presentArchive()
                if !(await session.browser?.confirmDiscardingEdits() ?? true) {
                    allowed = false
                    break
                }
            }
            checkingTermination = false
            sender.reply(toApplicationShouldTerminate: allowed)
        }
        return .terminateLater
    }

    /// Clicking Stow in Finder, Launchpad or the Dock with no window open brings the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        guard !hasVisibleWindows, let app else { return true }
        app.presentMostRecentArchive()
        // We routed the reopen ourselves. Default handling can also present another scene,
        // briefly showing both Welcome and Browser.
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let sender = Self.sender() { Self.log.info("Open from \(sender, privacy: .public)") }
        receivedExternalRequest = true
        enqueue { $0.receive(urls) }
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        guard let app else { return nil }
        return dockMenu.makeMenu(app: app, windows: sender.windows,
                                 current: sender.keyWindow ?? sender.mainWindow)
    }

    private func enqueue(_ job: @escaping (AppState) -> Void) {
        receivedExternalRequest = true
        pending.append(job)
        flush()
    }

    private func flush() {
        guard let app, !pending.isEmpty else { return }
        let jobs = pending
        pending = []
        jobs.forEach { $0(app) }
    }

    /// Who sent the Apple Event that opened these URLs, when macOS says.
    private static func sender() -> String? {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              let pid = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value, pid > 0
        else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "pid \(pid)"
    }
}

/// Reuse Stow's scoped recent-archive records rather than publishing a second, unscoped history.
final class DockMenuController: NSObject {
    private weak var app: AppState?

    func makeMenu(app: AppState, windows: [NSWindow], current: NSWindow?) -> NSMenu {
        self.app = app
        let menu = NSMenu()
        menu.autoenablesItems = false
        app.recents.refresh()
        for entry in app.recents.visible {
            let item = NSMenuItem(title: OpenRecentMenu.title(for: entry, among: app.recents.visible),
                                 action: #selector(openRecent(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = entry.id
            item.toolTip = entry.folderDisplay
            item.isEnabled = app.passwords.question == nil
            menu.addItem(item)
        }
        let visibleWindows = windows.filter(Self.includes)
        if !menu.items.isEmpty && !visibleWindows.isEmpty { menu.addItem(.separator()) }
        for window in visibleWindows {
            let item = NSMenuItem(title: window.title, action: #selector(showWindow(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = window
            item.state = window === current ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    static func includes(_ window: NSWindow) -> Bool {
        guard window.isVisible || window.isMiniaturized else { return false }
        let id = window.identifier?.rawValue ?? ""
        return ["main", "archive", "welcome", "creation", "glance", "com_apple_SwiftUI_Settings_window"].contains {
            id == $0 || id.hasPrefix($0 + "-")
        }
    }

    @objc func showWindow(_ sender: NSMenuItem) {
        guard let window = sender.representedObject as? NSWindow,
              let id = window.identifier?.rawValue else { return }
        DispatchQueue.main.async { [weak window] in
            guard let window else { return }
            ApplicationLifecycle.shared.presentWindow(id) {
                if window.isMiniaturized { window.deminiaturize(nil) }
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    @objc func openRecent(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        DispatchQueue.main.async { [weak self] in
            guard let app = self?.app, let entry = app.recents.entries.first(where: { $0.id == id }) else { return }
            app.passwords.performCommand { app.openRecent(entry) }
        }
    }
}
