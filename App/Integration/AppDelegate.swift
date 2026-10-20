import AppKit
import OSLog

/// Receives what macOS hands Stow from outside: documents opened from Finder (double-click,
/// Open With, Quick Look's "Open in Stow") and `stow://` hand-offs.
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var app: AppState? {
        didSet { flush() }
    }

    /// Opened before the window (and its AppState) exists — e.g. Stow launched by a double-click.
    private var pending: [URL] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        if let sender = Self.sender() { Self.log.info("Open from \(sender, privacy: .public)") }
        pending += urls
        flush()
    }

    private static let log = Logger(subsystem: "app.stow.Stow", category: "open")

    /// Who sent the Apple Event that opened these URLs, when macOS says.
    private static func sender() -> String? {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              let pid = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value, pid > 0
        else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "pid \(pid)"
    }

    private func flush() {
        guard let app, !pending.isEmpty else { return }
        let urls = pending
        pending = []
        app.receive(urls)
    }
}
