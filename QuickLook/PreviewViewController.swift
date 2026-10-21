import AppKit
import OSLog
import QuickLookUI
import SwiftUI

/// Stow's Quick Look extension: Space on an archive in Finder lists it (never extracts) and shows
/// the tree with a one-line Checkup. Quick Look extensions may not launch processes, so it carries
/// its own copy of the sandboxed engine (Contents/XPCServices) and sends it the file as a handle.
final class PreviewViewController: NSViewController, QLPreviewingController {
    nonisolated private static let log = Logger(subsystem: "app.stow.Stow.QuickLook", category: "preview")

    override func loadView() {
        view = NSView()
        preferredContentSize = CGSize(width: 640, height: 480)
    }

    func preparePreviewOfFile(at url: URL) async throws {
        let start = ContinuousClock.now
        let content = await ArchivePreviewLoader.load(url) { try await ArchiveEngine.shared.list($0) }
        switch content {
        case .listed(let model):
            Self.log.info("Listed \(url.lastPathComponent, privacy: .public): \(model.fileCount) files in \(ContinuousClock.now - start, privacy: .public)")
        case .fallback(let fallback):
            Self.log.info("Fallback for \(url.lastPathComponent, privacy: .public): \(fallback.title, privacy: .public) — \(fallback.message, privacy: .public)")
        }
        let host = NSHostingView(rootView: ArchivePreview(content: content, openInStow: Self.containingApp.map { app in
            { Self.open(url, with: app) }
        }))
        host.translatesAutoresizingMaskIntoConstraints = false
        view.subviews.forEach { $0.removeFromSuperview() }
        view.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.topAnchor.constraint(equalTo: view.topAnchor),
            host.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    /// Stow.app, two levels above this extension (Contents/PlugIns/StowQuickLook.appex).
    private static var containingApp: URL? {
        let app = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return app.pathExtension == "app" ? app : nil
    }

    /// Quick Look already let this extension read the file, so Launch Services can pass it on.
    private static func open(_ url: URL, with app: URL) {
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error { log.error("Open in Stow failed: \(error.localizedDescription, privacy: .public)") }
        }
    }
}
