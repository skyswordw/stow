import AppKit
import SwiftUI

/// Where Glance opens: centred on the pointer with the pointer in its toolbar, so it seems to grow
/// out of what was clicked — then pulled back inside the screen's visible area (menu bar and Dock
/// excluded) so no edge or corner is ever off screen.
nonisolated enum GlancePlacement {
    static let defaultSize = CGSize(width: 440, height: 500)
    static let minimumSize = CGSize(width: 400, height: 320)
    /// Kept clear between Glance and the edge of the visible area.
    static let margin: CGFloat = 8
    /// How far above the pointer the window's top edge sits: the pointer lands in the toolbar.
    static let pointerInset: CGFloat = 24

    /// The window frame in screen coordinates (AppKit: origin bottom-left, y up).
    static func frame(size: CGSize, pointer: CGPoint, visible: CGRect) -> CGRect {
        let room = visible.insetBy(dx: margin, dy: margin)
        let width = min(size.width, room.width)
        let height = min(size.height, room.height)
        let x = clamp(pointer.x - width / 2, room.minX, room.maxX - width)
        let y = clamp(pointer.y + pointerInset - height, room.minY, room.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// The pointer as a point in the window's own top-left space, kept inside it — where the
    /// opening scale is anchored.
    static func anchor(pointer: CGPoint, in frame: CGRect) -> UnitPoint {
        guard frame.width > 0, frame.height > 0 else { return .center }
        return UnitPoint(x: clamp((pointer.x - frame.minX) / frame.width, 0, 1),
                         y: clamp((frame.maxY - pointer.y) / frame.height, 0, 1))
    }

    /// Edges and corners of the visible area, for `-StowGlanceEdge` and the placement tests.
    enum Edge: String, CaseIterable, Sendable {
        case center, top, bottom, left, right, topLeft, topRight, bottomLeft, bottomRight

        /// A pointer resting on this edge of `visible`.
        func pointer(in visible: CGRect) -> CGPoint {
            let left = visible.minX + 1, right = visible.maxX - 1
            let bottom = visible.minY + 1, top = visible.maxY - 1
            return switch self {
            case .center: CGPoint(x: visible.midX, y: visible.midY)
            case .top: CGPoint(x: visible.midX, y: top)
            case .bottom: CGPoint(x: visible.midX, y: bottom)
            case .left: CGPoint(x: left, y: visible.midY)
            case .right: CGPoint(x: right, y: visible.midY)
            case .topLeft: CGPoint(x: left, y: top)
            case .topRight: CGPoint(x: right, y: top)
            case .bottomLeft: CGPoint(x: left, y: bottom)
            case .bottomRight: CGPoint(x: right, y: bottom)
            }
        }
    }

    private static func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        min(max(value, low), max(low, high))
    }
}

/// Glass, or a solid window background when Reduce Transparency is on.
nonisolated enum GlanceMaterial: Equatable, Sendable {
    case glass, solid

    static func resolve(reduceTransparency: Bool, override: Bool = UserDefaults.standard.bool(forKey: "StowReduceTransparency")) -> Self {
        reduceTransparency || override ? .solid : .glass
    }
}

/// Glance: the compact window for a quick browse and extract. It shows the same `BrowserModel`
/// as the full window — switching between them moves the window, not the state, so folder,
/// selection and history come along. Only one of the two shows the browser at a time.
@Observable
final class GlanceController: NSObject, NSWindowDelegate {
    weak var app: AppState?
    private(set) var isShown = false
    /// Keep Glance above other apps' windows.
    var isPinned = SettingsKeys.flag(SettingsKeys.glancePinned) {
        didSet {
            UserDefaults.standard.set(isPinned, forKey: SettingsKeys.glancePinned)
            window?.level = isPinned ? .floating : .normal
        }
    }
    /// The archive being opened into Glance (from Finder or Quick Look) until it's listed.
    var pendingName: String?
    /// Bumped on every animated appearance; the view springs its content in from `anchor`.
    private(set) var appearance = 0
    private(set) var anchor = UnitPoint.center

    /// Closes the full window. A seam for tests; Glance and the full window never both show the browser.
    @ObservationIgnored var closeMainWindow: () -> Void = { GlanceController.mainWindows.forEach { $0.close() } }
    /// Brings the full window back (AppState's `showMainWindow` unless a test swaps it).
    @ObservationIgnored var openMainWindow: (() -> Void)?
    /// Tests keep Glance off screen; the state still changes the same way.
    @ObservationIgnored var presentsWindow = true

    @ObservationIgnored private(set) var window: NSWindow?

    /// The browser Glance shows — always the app's own, never a copy.
    var model: BrowserModel? { app?.browser }

    /// Whether the full window has been on screen yet. SwiftUI puts it up once at launch, after
    /// a Finder open may already have gone to Glance.
    @ObservationIgnored private var sawMainWindow = false

    override init() {
        super.init()
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didChangeOcclusionStateNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let window = (note.object as? NSWindow).map(WindowBox.init)
                MainActor.assumeIsolated { if let window = window?.window { self?.mainWindowAppeared(window) } }
            }
        }
    }

    /// The full window came up while Glance was showing the browser. At launch that's SwiftUI's
    /// own presentation, so it goes; later it's someone choosing the full window, so Glance goes.
    private func mainWindowAppeared(_ window: NSWindow) {
        guard window.isVisible, Self.mainWindows.contains(window) else { return }
        defer { sawMainWindow = true }
        if mainWindowAnimation != .default {
            // It's up; whatever opens it next (the Dock, the Window menu) gets the usual opening.
            mainWindowAnimation = .default
            window.animationBehavior = .default
        }
        guard isShown, presentsWindow else { return }
        guard !sawMainWindow else { return close() }
        // SwiftUI is still presenting it and ignores a close until that's done: hide it now, close it after.
        window.orderOut(nil)
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            window.close()
        }
    }

    // MARK: - Switching

    /// Full window → Glance, near the pointer. Clicking animates; the keyboard shortcut doesn't.
    func collapse(near pointer: CGPoint = NSEvent.mouseLocation, animated: Bool = !GlanceController.isKeyboardEvent) {
        guard model != nil else { return }
        closeMainWindow()
        show(near: pointer, animated: animated)
    }

    /// Glance → full window, same browser. By keyboard the full window appears without AppKit's
    /// window zoom (DESIGN.md › Motion); a click keeps the system's usual opening.
    func expand(byKeyboard: Bool = Motion.byKeyboard) {
        guard isShown else { return }
        close()
        mainWindowAnimation = byKeyboard ? .none : .default
        // A full window SwiftUI kept around is ordered in again; a new one gets it in `prepareMainWindow`.
        for window in Self.mainWindows { window.animationBehavior = mainWindowAnimation }
        (openMainWindow ?? app?.showMainWindow)?()
    }

    /// How the next full window comes up; `expand` sets it, and it's back to the default once one has.
    @ObservationIgnored private var mainWindowAnimation = NSWindow.AnimationBehavior.default

    /// The browser hands over its window as soon as it exists, before SwiftUI puts it on screen.
    func prepareMainWindow(_ window: NSWindow) {
        guard Self.mainWindows.contains(window) else { return }
        window.animationBehavior = mainWindowAnimation
    }

    /// Opens an archive from Finder or Quick Look straight into Glance: the window appears at the
    /// pointer right away and says what it's opening; the archive fills it once listed.
    func open(_ url: URL) {
        guard let app else { return }
        pendingName = url.lastPathComponent
        closeMainWindow()
        show(near: NSEvent.mouseLocation, animated: true)
        app.open(url)
    }

    // MARK: - Window

    func show(near pointer: CGPoint, size: CGSize? = nil, animated: Bool) {
        let visible = Self.screen(containing: pointer).visibleFrame
        let frame = GlancePlacement.frame(size: size ?? window?.frame.size ?? GlancePlacement.defaultSize,
                                          pointer: pointer, visible: visible)
        anchor = GlancePlacement.anchor(pointer: pointer, in: frame)
        isShown = true
        guard presentsWindow else { return }
        let window = window ?? makeWindow()
        self.window = window
        window.level = isPinned ? .floating : .normal
        window.setFrame(frame, display: false)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if animated {
            appearance += 1
            window.alphaValue = 0
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                // The glass arrives with the content's spring (DESIGN.md › Motion: response 0.32, damping 1).
                context.duration = reduceMotion ? 0.15 : 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 1
            }
        } else {
            window.alphaValue = 1
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
        }
    }

    /// Closes Glance; the archive stays open, like closing the full window.
    func close() {
        guard isShown else { return }
        isShown = false
        pendingName = nil
        if model?.quickLook.isVisible == true { model?.quickLook.close() }
        window?.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // The close button or ⌘W.
        isShown = false
        pendingName = nil
    }

    private func makeWindow() -> NSWindow {
        let window = GlanceWindow(contentRect: CGRect(origin: .zero, size: GlancePlacement.defaultSize),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: true)
        window.identifier = NSUserInterfaceItemIdentifier(Self.windowIdentifier)
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unifiedCompact
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentMinSize = GlancePlacement.minimumSize
        window.collectionBehavior.insert(.fullScreenAuxiliary)
        window.tabbingMode = .disallowed
        // Glance has its own entrance (springing out of the pointer) and none by keyboard; AppKit's
        // window zoom would play on top of both. Closing is instant.
        window.animationBehavior = .none
        window.delegate = self
        let host = NSHostingController(rootView: GlanceRoot(glance: self).environment(app ?? AppState()))
        // SwiftUI's toolbar and title become the window's own.
        host.sceneBridgingOptions = [.toolbars, .title]
        host.sizingOptions = []
        window.contentViewController = host
        window.setContentSize(GlancePlacement.defaultSize)
        return window
    }

    static let windowIdentifier = "glance"

    /// The full window (SwiftUI's `Window(id: "main")`), however many times it was reopened.
    static var mainWindows: [NSWindow] {
        NSApp.windows.filter { $0.identifier?.rawValue == "main" || $0.identifier?.rawValue.hasPrefix("main-") == true }
    }

    static var isKeyboardEvent: Bool { NSApp.currentEvent?.type == .keyDown }

    private static func screen(containing point: CGPoint) -> NSScreen {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }
}

private final class GlanceWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private struct WindowBox: @unchecked Sendable {
    let window: NSWindow
}
