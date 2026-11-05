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
            } else { app?.showMainWindow() }
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
            draft.close()
            app.archiveDraft = nil
        }
        guard app?.browser?.levels.contains(where: { $0.edits.isEdited }) == true else { return .terminateNow }
        guard !checkingTermination else { return .terminateLater }
        checkingTermination = true
        app?.showMainWindow()
        Task {
            let allowed = await app?.browser?.confirmDiscardingEdits() ?? true
            checkingTermination = false
            sender.reply(toApplicationShouldTerminate: allowed)
        }
        return .terminateLater
    }

    /// Clicking Stow in Finder, Launchpad or the Dock with no window open brings the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        guard !hasVisibleWindows, let app else { return true }
        app.showMainWindow()
        // We routed the reopen ourselves. Default handling can also present another scene,
        // briefly showing both Welcome and Browser.
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let sender = Self.sender() { Self.log.info("Open from \(sender, privacy: .public)") }
        receivedExternalRequest = true
        enqueue { $0.receive(urls) }
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
