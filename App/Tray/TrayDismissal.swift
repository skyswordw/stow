import AppKit

/// A mouse press outside can become a drag. Decide only on release, and require both
/// ends to be outside. A release from the gesture that revealed Tray cannot dismiss it.
nonisolated struct TrayOutsideClick {
    private var button: Int?
    private var dragged = false

    mutating func press(button: Int, outside: Bool) {
        self.button = outside ? button : nil
        dragged = false
    }

    mutating func drag() { dragged = true }

    mutating func release(button: Int, outside: Bool) -> Bool {
        let dismiss = self.button == button && outside && !dragged
        self = Self()
        return dismiss
    }

    mutating func cancel() { self = Self() }
}

/// Observes without consuming clicks. Installed only while Tray is shown, including
/// when it is nonactivating and another application still owns the menu bar.
final class TrayDismissalMonitor {
    var isRelatedWindow: (NSWindow?) -> Bool = { _ in false }
    var canDismiss: () -> Bool = { false }
    var interact: () -> Void = {}
    var dismiss: () -> Void = {}
    var mouseReleased: () -> Void = {}
    /// A new press, with no other mouse button down, proves an earlier drag has ended.
    var outsidePress: () -> Void = {}
    private var click = TrayOutsideClick()
    private var relatedPress = false
    private var local: Any?
    private var global: Any?
    private var activation: (any NSObjectProtocol)?
    private var menuObservers: [any NSObjectProtocol] = []
    private var trackingMenus: Set<ObjectIdentifier> = []

    var isTrackingMenu: Bool { !trackingMenus.isEmpty }

    func start() {
        guard local == nil else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseUp, .leftMouseDragged,
                                          .rightMouseDown, .rightMouseUp, .rightMouseDragged,
                                          .otherMouseDown, .otherMouseUp, .otherMouseDragged]
        local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event, local: true) }
            return event
        }
        global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event, local: false) }
        }
        activation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let pid = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                guard let self, let pid, pid != ProcessInfo.processInfo.processIdentifier,
                      NSEvent.pressedMouseButtons == 0, self.canDismiss(), !self.isTrackingMenu else { return }
                self.dismiss()
            }
        }
        for name in [NSMenu.didBeginTrackingNotification, NSMenu.didEndTrackingNotification] {
            menuObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let identifier = (note.object as? NSMenu).map(ObjectIdentifier.init)
                MainActor.assumeIsolated {
                    guard let self, let identifier else { return }
                    if name == NSMenu.didBeginTrackingNotification {
                        guard self.relatedPress || self.isRelatedWindow(NSApp.keyWindow)
                                || self.isTrackingMenu else { return }
                        self.click.cancel()
                        self.trackingMenus.insert(identifier)
                        self.interact()
                    } else if self.trackingMenus.remove(identifier) != nil {
                        self.click.cancel()
                    }
                }
            })
        }
    }

    func handle(_ event: NSEvent, local: Bool) {
        let related = local && isRelatedWindow(event.window)
        let isPress = [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type)
        if isPress, !related, !isTrackingMenu,
           NSEvent.pressedMouseButtons & ~(1 << event.buttonNumber) == 0 {
            outsidePress()
        }
        let outside = !related && !isTrackingMenu && canDismiss()
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            relatedPress = related
            if related { interact() }
            click.press(button: event.buttonNumber, outside: outside)
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            click.drag()
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            if click.release(button: event.buttonNumber, outside: outside) { dismiss() }
            relatedPress = false
            mouseReleased()
        default: break
        }
    }

    func stop() {
        if let local { NSEvent.removeMonitor(local) }
        if let global { NSEvent.removeMonitor(global) }
        if let activation { NSWorkspace.shared.notificationCenter.removeObserver(activation) }
        for observer in menuObservers { NotificationCenter.default.removeObserver(observer) }
        local = nil
        global = nil
        activation = nil
        menuObservers = []
        trackingMenus = []
        click.cancel()
        relatedPress = false
    }

    isolated deinit { stop() }
}

/// Retains the picker and its delegate through the chosen service, including a share
/// sheet hosted by another process. Ending a share does not dismiss or reopen Tray.
final class TrayShareSession: NSObject, NSSharingServicePickerDelegate, NSSharingServiceDelegate {
    private let picker: NSSharingServicePicker
    private let finished: () -> Void
    private var didFinish = false

    init(items: [URL], finished: @escaping () -> Void) {
        picker = NSSharingServicePicker(items: items)
        self.finished = finished
        super.init()
        picker.delegate = self
    }

    func show(from view: NSView) {
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        if service == nil { finish() }
    }

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker,
                              delegateFor sharingService: NSSharingService) -> (any NSSharingServiceDelegate)? { self }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) { finish() }
    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: any Error) { finish() }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        finished()
    }
}
