import AppKit
import SwiftUI

extension AppState {
    var workspace: AppState { workspaceOwner ?? self }
    var archiveSessions: [AppState] { [workspace] + workspace.additionalSessions }

    /// Reading focus state makes command menus refresh when another archive becomes key.
    var commandSession: AppState {
        let root = workspace
        let _ = root.focusedSessionID
        return root.session(owning: NSApp.keyWindow) ?? root
    }

    func session(owning window: NSWindow?) -> AppState? {
        guard let window else { return nil }
        let owner = window.sheetParent ?? window
        return archiveSessions.first {
            owner === $0.archiveWindow || owner === $0.glance.window
                || owner === $0.browser?.editingWindow
        }
    }

    /// Resolve identity before starting asynchronous loading, so a multi-file open cannot
    /// replace an in-flight session or create competing editors for one source.
    func sessionForOpening(_ url: URL) -> AppState {
        let root = workspace
        let key = RecentArchives.key(for: url)
        if let existing = root.archiveSessions.first(where: {
            let source = $0.browser?.levels.first?.edits.url ?? $0.openingURL
            return source.map { RecentArchives.key(for: $0) == key } ?? false
        }) { return existing }
        if !root.usesBrowserWindow && !root.glance.isShown { return root }
        let session = AppState(workspaceOwner: root)
        session.presentationDefaults = root.presentationDefaults
        session.presentsArchiveWindows = root.presentsArchiveWindows
        session.glance.presentsWindow = root.glance.presentsWindow && root.presentsArchiveWindows
        session.showMainWindow = { [weak session] in
            guard let session, session.presentsArchiveWindows else { return }
            if session.archiveWindowController == nil {
                session.archiveWindowController = ArchiveWindowController(session: session)
            }
            session.archiveWindowController?.present()
        }
        root.additionalSessions.append(session)
        return session
    }

    func presentArchive() {
        workspace.lastArchiveSessionID = sessionID
        if glance.isShown { glance.show(near: NSEvent.mouseLocation, animated: false) }
        else { showMainWindow() }
    }

    func openInBrowser(_ url: URL) {
        let destination = workspace.sessionForOpening(url)
        if destination.isOpening || destination.browser != nil || destination.openFailure != nil {
            destination.presentArchive()
        } else {
            destination.open(url)
            destination.showMainWindow()
        }
    }

    func presentMostRecentArchive() {
        let root = workspace
        let target = root.archiveSessions.first {
            $0.sessionID == root.lastArchiveSessionID && ($0.usesBrowserWindow || $0.glance.isShown)
        }
        (target ?? root).presentArchive()
    }
}

/// Secondary Browser windows reuse the existing workspace and native toolbar. Their close,
/// password and edit state belongs to their session, never to the app-wide Welcome scene.
final class ArchiveWindowController: NSWindowController {
    init(session: AppState) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 700),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.identifier = NSUserInterfaceItemIdentifier("archive-" + session.sessionID.uuidString)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.toolbarStyle = .unified
        window.center()
        if let previous = NSApp.keyWindow { window.cascadeTopLeft(from: NSPoint(x: previous.frame.minX + 24, y: previous.frame.maxY - 24)) }
        let host = NSHostingController(rootView: RootView().environment(session))
        host.sceneBridgingOptions = [.title, .toolbars]
        host.sizingOptions = [.minSize]
        window.contentViewController = host
        window.setContentSize(NSSize(width: 1120, height: 700))
        super.init(window: window)
        session.archiveWindow = window
    }

    required init?(coder: NSCoder) { nil }

    func present() {
        guard let window, let id = window.identifier?.rawValue else { return }
        ApplicationLifecycle.shared.presentWindow(id) { window.makeKeyAndOrderFront(nil) }
    }
}
