import AppKit
import OSLog

/// Receives what macOS hands Stow from outside: documents opened from Finder (double-click,
/// Open With, Quick Look's "Open in Stow"), `stow://` hand-offs and Services requests.
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var app: AppState? {
        didSet { flush() }
    }

    /// Arrived before the window (and its AppState) existed — e.g. Stow launched by a double-click
    /// or a Finder action.
    private var pending: [(AppState) -> Void] = []
    private lazy var services = ServicesProvider { [weak self] job in self?.enqueue(job) }

    private static let log = Logger(subsystem: "app.stow.Stow", category: "open")

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Before launching finishes, or a Services request that launched Stow times out.
        NSApp.servicesProvider = services
        NSUpdateDynamicServices()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let sender = Self.sender() { Self.log.info("Open from \(sender, privacy: .public)") }
        enqueue { $0.receive(urls) }
    }

    private func enqueue(_ job: @escaping (AppState) -> Void) {
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
