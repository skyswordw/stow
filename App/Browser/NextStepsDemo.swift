import AppKit

/// Design review: opens the capsule's More menu and captures it with the window
/// (`-StowScene next-steps-more`). A menu isn't one of the app's windows, so the usual capture misses it.
enum NextStepsDemo {
    /// The More button in window coordinates (top-left origin), kept up to date by the capsule.
    static var moreButtonFrame: CGRect?

    private static var mainWindow: NSWindow? {
        NSApp.windows.first { !($0 is NSPanel) && $0.isVisible && $0.sheetParent == nil }
    }

    /// Clicks the More button. The menu then tracks on its own; timers and tasks keep running.
    static func openMoreMenu() {
        guard let window = mainWindow, let frame = moreButtonFrame, let content = window.contentView else { return }
        let point = CGPoint(x: frame.midX, y: content.bounds.height - frame.midY)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                NSApp.postEvent(event, atStart: false)
            }
        }
    }

    /// The window and everything Stow shows above it — the open menu — as one image.
    static func captureWithMenu(name: String) -> URL? {
        guard let window = mainWindow else { return nil }
        typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY),
              let symbol = dlsym(handle, "CGWindowListCreateImage") else { return nil }
        let create = unsafeBitCast(symbol, to: CreateImage.self)
        let aboveWindow: UInt32 = 1 << 1, includingWindow: UInt32 = 1 << 3, bestResolution: UInt32 = 1 << 3
        guard let image = create(.null, aboveWindow | includingWindow, UInt32(window.windowNumber), bestResolution)?
            .takeRetainedValue(),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return nil }
        let url = FileManager.default.temporaryDirectory.appending(path: "\(name).png")
        return (try? data.write(to: url)) != nil ? url : nil
    }
}
