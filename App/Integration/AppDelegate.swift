import AppKit

/// Receives what macOS hands Stow from outside: documents opened from Finder (double-click,
/// Open With, Quick Look's "Open in Stow") and `stow://` hand-offs.
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var app: AppState? {
        didSet { flush() }
    }

    /// Opened before the window (and its AppState) exists — e.g. Stow launched by a double-click.
    private var pending: [URL] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        pending += urls
        flush()
    }

    private func flush() {
        guard let app, !pending.isEmpty else { return }
        let urls = pending
        pending = []
        app.receive(urls)
    }
}
