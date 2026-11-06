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
    private var foregroundTask: Task<Void, Never>?
    private var foregroundRequest = UUID()

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
                        self?.pendingWindows = self?.pendingWindows.filter {
                            identifier != $0 && !identifier.hasPrefix($0 + "-")
                        } ?? []
                    }
                    self?.schedule()
                }
            })
        }
        schedule()
    }

    func presenting(_ identifier: String) {
        guard app != nil else { return }
        if !NSApp.windows.contains(where: {
            let actual = $0.identifier?.rawValue ?? ""
            return ($0.isVisible || $0.isMiniaturized) && (actual == identifier || actual.hasPrefix(identifier + "-"))
        }) {
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

    /// Explicit user requests must order the requested window after SwiftUI creates it and
    /// after any status/Dock menu finishes tracking. Never pick an unrelated visible window.
    func presentWindow(_ identifier: String, open: () -> Void) {
        Self.activateForWindow()
        presenting(identifier)
        open()
        guard NSClassFromString("XCTestCase") == nil,
              UserDefaults.standard.string(forKey: "StowScene") == nil else { return }
        foregroundTask?.cancel()
        let request = UUID()
        foregroundRequest = request
        foregroundTask = Task { @MainActor in
            let deadline = ContinuousClock.now + .seconds(2)
            repeat {
                await Task.yield()
                guard !Task.isCancelled else { return }
                if let window = Self.window(for: identifier, in: NSApp.windows) {
                    if window.isMiniaturized { window.deminiaturize(nil) }
                    Self.foregroundSurface(for: window, modal: NSApp.modalWindow).makeKeyAndOrderFront(nil)
                    NSApp.activate()
                    if !NSApp.isActive {
                        // Use the same Launch Services activation path as an explicit Dock open;
                        // this reuses the running process and does not open a second document.
                        let configuration = NSWorkspace.OpenConfiguration()
                        configuration.activates = true
                        configuration.createsNewApplicationInstance = false
                        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { [weak self] _, _ in
                            Task { @MainActor in
                                guard self?.foregroundRequest == request,
                                      let destination = Self.window(for: identifier, in: NSApp.windows) else { return }
                                // The reopen event can choose the main window; restore the actual
                                // requested destination (notably Settings) after activation completes.
                                Self.foregroundSurface(for: destination, modal: NSApp.modalWindow).makeKeyAndOrderFront(nil)
                            }
                        }
                    }
                    return
                }
                try? await Task.sleep(for: .milliseconds(20))
            } while ContinuousClock.now < deadline
        }
    }

    static func window(for identifier: String, in windows: [NSWindow]) -> NSWindow? {
        windows.first {
            let actual = $0.identifier?.rawValue ?? ""
            return (actual == identifier || actual.hasPrefix(identifier + "-"))
                && ($0.isVisible || $0.isMiniaturized)
        }
    }

    /// Presentation may finish inside an alert's nested run loop. Never raise its parent above
    /// an active quit/discard confirmation or a picker that arrived after the original request.
    static func foregroundSurface(for window: NSWindow, modal: NSWindow?) -> NSWindow {
        var surface = modal ?? window
        while let sheet = surface.attachedSheet { surface = sheet }
        return surface
    }
}
