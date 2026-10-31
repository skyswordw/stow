import AppKit

/// File > Close targets the key window, independently of the archive behind it. Native windows
/// keep performClose and its unsaved-edit delegate; Glance and Tray use their own hide paths.
@Observable
final class WindowCloseCommand {
    static let shared = WindowCloseCommand()
    private(set) var isEnabled = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                     NSWindow.willBeginSheetNotification, NSWindow.didEndSheetNotification,
                     NSWindow.didUpdateNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        refresh()
    }

    isolated deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    func refresh() {
        let enabled = Self.canClose(NSApp.keyWindow)
        if isEnabled != enabled { isEnabled = enabled }
    }

    static func canClose(_ window: NSWindow?) -> Bool {
        guard let window, window.sheetParent == nil, window.attachedSheet == nil,
              NSApp.modalWindow == nil else { return false }
        return window.styleMask.contains(.closable) || window is TrayPanel
    }

    func perform(in window: NSWindow?, app: AppState) {
        // Recheck at dispatch: a sheet may have appeared since the menu was updated.
        guard Self.canClose(window), let window else { return }
        if window === app.glance.window {
            // Hidden traffic lights can make performClose beep. Match Glance's Close button,
            // retaining the archive session, and stop an opening that no longer has a window.
            if app.glance.pendingName != nil { app.cancelOpening() }
            app.glance.close()
        } else if window is TrayPanel {
            app.tray.hide()
        } else {
            window.performClose(nil)
        }
        refresh()
    }
}
