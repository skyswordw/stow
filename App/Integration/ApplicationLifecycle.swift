import AppKit
import Observation

/// Window presentation, background work and residency are separate lifetime decisions.
nonisolated enum AppLifetime {
    enum Decision: Equatable { case regular, resident, wait, terminate }

    static func decide(hasWindow: Bool, hasWork: Bool, trayEnabled: Bool, mayTerminate: Bool) -> Decision {
        if hasWindow { return .regular }
        if hasWork { return .wait }
        if trayEnabled { return .resident }
        return mayTerminate ? .terminate : .wait
    }
}

/// Reevaluate after window handovers and observed operation changes, without an idle polling timer.
final class ApplicationLifecycle {
    static let shared = ApplicationLifecycle()
    private weak var app: AppState?
    private var observers: [NSObjectProtocol] = []
    private var mayTerminate = false
    private var scheduled = false
    private var generation = 0
    private var pendingWindows: Set<String> = []

    func install(app: AppState, backgroundLaunch: Bool) {
        // Test hosts and screenshot scenes must never terminate the host or alter Dock policy.
        guard NSClassFromString("XCTestCase") == nil,
              UserDefaults.standard.string(forKey: "StowScene") == nil else { return }
        self.app = app
        mayTerminate = backgroundLaunch
        guard observers.isEmpty else { schedule(); return }
        for name in [NSWindow.willCloseNotification, NSWindow.didBecomeKeyNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let identifier = (notification.object as? NSWindow)?.identifier?.rawValue
                MainActor.assumeIsolated {
                    self?.mayTerminate = true
                    if let identifier {
                        self?.pendingWindows.remove(identifier)
                    }
                    self?.schedule()
                }
            })
        }
        schedule()
    }

    func presenting(_ identifier: String) {
        guard app != nil else { return }
        if !NSApp.windows.contains(where: { $0.isVisible && $0.identifier?.rawValue == identifier }) {
            pendingWindows.insert(identifier)
        }
        schedule()
    }

    func schedule() {
        guard app != nil, !scheduled else { return }
        scheduled = true
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            scheduled = false
            evaluate()
        }
    }

    private func evaluate() {
        guard let app else { return }
        generation += 1
        let current = generation
        let decision = withObservationTracking {
            let window = app.glance.isShown || NSApp.windows.contains(where: Self.countsAsWorkWindow)
            let work = app.hasLifetimeWork || NSApp.modalWindow != nil
                || NSApp.windows.contains { $0.isVisible && $0.sheetParent != nil }
                || !pendingWindows.isEmpty
            return AppLifetime.decide(hasWindow: window, hasWork: work,
                                      trayEnabled: app.tray.isEnabled, mayTerminate: mayTerminate)
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.generation == current else { return }
                self.schedule()
            }
        }
        app.releaseFinishedWork()
        switch decision {
        case .regular:
            if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
        case .resident:
            if NSApp.activationPolicy() != .accessory { NSApp.setActivationPolicy(.accessory) }
        case .wait: break
        case .terminate:
            NSApp.terminate(nil)
        }
    }

    static func countsAsWorkWindow(_ window: NSWindow) -> Bool {
        guard window.isVisible || window.isMiniaturized else { return false }
        // Settings can be a utility/key-only window depending on the macOS/SwiftUI host.
        if window.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" { return true }
        return !(window is NSPanel) && (window.canBecomeMain || window.canBecomeKey)
    }

    static func activateForWindow() {
        guard NSClassFromString("XCTestCase") == nil else { return }
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
        NSApp.activate()
    }
}
