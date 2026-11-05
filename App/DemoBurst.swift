import AppKit
import SwiftUI

/// Frame bursts for motion review (#104): `-StowScene <scene> -StowSnapshot YES -StowBurst <transition>`
/// plays one transition while a background thread captures Stow's windows every few milliseconds,
/// then writes a contact sheet: one row per step, frames at fixed offsets after it. A capture on the
/// main thread would stall the very animation it records, so it never runs there.
///
/// Each step happens either as after a click or as after a key press. "Key" posts a key-down Stow
/// ignores and runs the step while that event is current, so `Motion.byKeyboard` sees it at the
/// moment of the change (DESIGN.md › Motion: keyboard actions never animate). The event is then
/// swallowed, and AppKit forgets it before the next redraw: a view that decides its animation in
/// `body` (`.animation(Motion.presence…)`) doesn't see the key press here, though it does for a real
/// one (checked with the event passed on, which delays the change too much to film). Those rows show the click's motion; check them with the keyboard itself.
///
/// `-StowBurstCrop x,y,w,h` crops every frame, in points from the windows' top-left corner;
/// negative x or y count from the right or bottom edge. Transitions:
/// actions (scene next-steps), glance (list), archive-info and notices (details-planned),
/// notice (source-access-unsaved), lock (encrypted), tray (tray), tray-pin (tray), batch (batch),
/// opening (browser-opening).
enum DemoBurst {
    enum Cause: String { case click, key, auto = "on its own" }

    struct Step {
        let at: Int
        let name: String
        let cause: Cause
        let action: @MainActor () -> Void
    }

    /// Views that hold their own state listen for this; `object` names the view's step.
    static let request = Notification.Name("StowDemoBurstRequest")

    static func post(_ name: String) {
        NotificationCenter.default.post(name: request, object: name)
    }

    /// Offsets after each step, in milliseconds, that the sheet shows. -40 is just before it.
    static let offsets = [-40, 16, 33, 50, 83, 116, 150, 200, 300, 500]

    // MARK: - Running

    static func run(_ transition: String, app: AppState, label: String) async -> URL? {
        let steps = steps(for: transition, app: app)
        let length = (steps.map(\.at).max() ?? 0) + 700
        let grabber = FrameGrabber()
        let windows = Task { @MainActor in
            while !Task.isCancelled {
                // The Tray is a panel of its own; leave out the welcome window behind it.
                grabber.windowIDs = NSApp.windows
                    .filter { $0.isVisible && !$0.className.contains("StatusBar") && $0.windowNumber > 0 }
                    .filter { !transition.hasPrefix("tray") || $0 is NSPanel }
                    .map { CGWindowID($0.windowNumber) }
                try? await Task.sleep(for: .milliseconds(8))
            }
        }
        let start = ProcessInfo.processInfo.systemUptime
        // A crop is a close-up: capture it at the screen's full resolution.
        let scale = crop == nil ? 1 : NSScreen.main?.backingScaleFactor ?? 2
        grabber.start(at: start, bestResolution: scale > 1)
        for step in steps {
            let wait = start + Double(step.at) / 1000 - ProcessInfo.processInfo.systemUptime
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            switch step.cause {
            case .key: asIfByKey(step.action)
            case .click, .auto: step.action()
            }
        }
        let rest = start + Double(length) / 1000 - ProcessInfo.processInfo.systemUptime
        if rest > 0 { try? await Task.sleep(for: .seconds(rest)) }
        windows.cancel()
        let frames = grabber.stop()
        let rows = steps.isEmpty ? [Step(at: 0, name: "shown", cause: .auto) {}] : steps
        let pixels = crop.map { CGRect(x: $0.minX * scale, y: $0.minY * scale, width: $0.width * scale, height: $0.height * scale) }
        return sheet(frames, rows: rows, crop: pixels, name: "\(label)-burst-\(transition)")
    }

    private static var crop: CGRect? {
        guard let parts = UserDefaults.standard.string(forKey: "StowBurstCrop")?.split(separator: ",").compactMap({ Double($0) }),
              parts.count == 4 else { return nil }
        return CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
    }

    /// Runs `action` while a key-down is the app's current event.
    private static func asIfByKey(_ action: @escaping @MainActor () -> Void) {
        final class Box { var monitor: Any? }
        let box = Box()
        let f19: UInt16 = 80
        box.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == f19 else { return event }
            if let monitor = box.monitor { NSEvent.removeMonitor(monitor) }
            action()
            return nil
        }
        if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                        timestamp: ProcessInfo.processInfo.systemUptime,
                                        windowNumber: NSApp.keyWindow?.windowNumber ?? 0, context: nil,
                                        characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: f19) {
            NSApp.postEvent(event, atStart: true)
        }
    }

    // MARK: - Transitions

    private static func steps(for transition: String, app: AppState) -> [Step] {
        let browser = app.browser
        switch transition {
        case "actions":
            // Opening and folding as the pointer arrives and leaves (after its 140 / 450 ms waits),
            // then Esc folding it.
            return [
                Step(at: 300, name: "fan out", cause: .click) { post("stack-open") },
                Step(at: 1300, name: "fold", cause: .click) { post("stack-close") },
                Step(at: 2100, name: "fan out", cause: .click) { post("stack-open") },
                Step(at: 3100, name: "fold (Esc)", cause: .key) { post("stack-close") },
            ]
        case "glance":
            let window = NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true && $0.isVisible }
            let point = window.map { CGPoint(x: $0.frame.midX, y: $0.frame.midY) } ?? NSEvent.mouseLocation
            return [
                Step(at: 300, name: "to Glance", cause: .click) { app.glance.collapse(near: point, animated: true) },
                Step(at: 1800, name: "to Browser", cause: .click) { app.glance.expand(byKeyboard: false) },
                Step(at: 3300, name: "to Glance", cause: .key) { app.glance.collapse(near: point, animated: false) },
                Step(at: 4800, name: "to Browser", cause: .key) { app.glance.expand(byKeyboard: true) },
            ]
        case "archive-info":
            return [
                Step(at: 300, name: "More Archive Information", cause: .click) { post("archive-info") },
                Step(at: 1100, name: "close it", cause: .click) { post("archive-info") },
                Step(at: 1900, name: "More Archive Information", cause: .key) { post("archive-info") },
                Step(at: 2700, name: "close it", cause: .key) { post("archive-info") },
            ]
        case "notices":
            return [
                Step(at: 300, name: "open the notice", cause: .click) { post("notices") },
                Step(at: 1100, name: "close it", cause: .click) { post("notices") },
                Step(at: 1900, name: "open the notice", cause: .key) { post("notices") },
                Step(at: 2700, name: "close it", cause: .key) { post("notices") },
            ]
        case "notice":
            let notice = browser?.sourceAccessNotice
            return [
                Step(at: 300, name: "dismiss ×", cause: .click) { browser?.sourceAccessNotice = nil },
                Step(at: 1100, name: "appears", cause: .auto) { browser?.sourceAccessNotice = notice },
                Step(at: 1900, name: "dismiss ×", cause: .key) { browser?.sourceAccessNotice = nil },
            ]
        case "lock":
            return [
                Step(at: 300, name: "checking", cause: .auto) { browser?.showUnlockingForDemo() },
                Step(at: 1100, name: "locked again", cause: .auto) { browser?.endUnlockingForDemo() },
                Step(at: 1900, name: "checking (Return)", cause: .key) { browser?.showUnlockingForDemo() },
                Step(at: 2700, name: "locked (Esc)", cause: .key) { browser?.endUnlockingForDemo() },
            ]
        case "tray":
            return [
                Step(at: 300, name: "hide", cause: .click) { app.tray.hide() },
                Step(at: 1100, name: "show", cause: .click) { app.tray.show() },
                Step(at: 1900, name: "hide (Esc)", cause: .key) { app.tray.hide() },
                Step(at: 2700, name: "show (⌥⌘T)", cause: .key) { app.tray.show() },
            ]
        case "tray-pin":
            // Clicking the pin writes the real setting: put back what was saved once the burst is done.
            let key = SettingsKeys.trayPinned
            let saved = Bundle.main.bundleIdentifier.flatMap { UserDefaults.standard.persistentDomain(forName: $0)?[key] }
            return [
                Step(at: 300, name: "keep open", cause: .click) { post("tray-pin-on") },
                Step(at: 2300, name: "note fades", cause: .auto) {},
                Step(at: 3000, name: "stop keeping open (Space)", cause: .key) { post("tray-pin-off") },
                Step(at: 5000, name: "note fades", cause: .auto) {
                    if let saved { UserDefaults.standard.set(saved, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
                },
            ]
        case "batch":
            let rows: [(String, BatchQueue.Job.Phase)] = [("Field Recordings.7z", .done), ("server-logs.tar.xz", .running(0.62)),
                                                          ("Brand Kit.zip", .waiting)]
            return [
                Step(at: 300, name: "batch ends", cause: .auto) { app.batch.preview([]) },
                Step(at: 1100, name: "batch starts", cause: .click) { app.batch.preview(rows) },
                Step(at: 1900, name: "batch ends", cause: .key) { app.batch.preview([]) },
                Step(at: 2700, name: "batch starts", cause: .key) { app.batch.preview(rows) },
            ]
        default:
            // "opening": nothing to do; the burst starts as the window does.
            return []
        }
    }

    // MARK: - Contact sheet

    private static func sheet(_ frames: [FrameGrabber.Frame], rows: [Step], crop: CGRect?, name: String) -> URL? {
        guard !frames.isEmpty else { return nil }
        let images = frames.map { frame -> CGImage? in
            guard let image = frame.image else { return nil }
            guard let crop else { return image }
            let width = CGFloat(image.width), height = CGFloat(image.height)
            let rect = CGRect(x: crop.minX < 0 ? width + crop.minX : crop.minX,
                              y: crop.minY < 0 ? height + crop.minY : crop.minY,
                              width: crop.width, height: crop.height)
            return image.cropping(to: rect) ?? image
        }
        guard let first = images.compactMap({ $0 }).first else { return nil }
        let isOpening = rows.count == 1 && rows[0].name == "shown"
        let offsets = isOpening ? [0, 100, 200, 300, 380, 420, 460, 500, 560, 650] : offsets
        let cellWidth: CGFloat = min(CGFloat(images.compactMap { $0?.width }.max() ?? 300), crop == nil ? 360 : 440)
        let aspect = CGFloat(first.height) / CGFloat(max(first.width, 1))
        let cellHeight = (cellWidth * aspect).rounded()
        let caption: CGFloat = 28, rowTitle: CGFloat = 34, gap: CGFloat = 8
        let width = gap + CGFloat(offsets.count) * (cellWidth + gap)
        let rowHeight = rowTitle + cellHeight + caption
        let height = gap + CGFloat(rows.count) * (rowHeight + gap)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.translateBy(x: 0, y: height)
        context.cgContext.scaleBy(x: 1, y: -1)
        NSColor(white: 0.5, alpha: 1).setFill()
        CGRect(x: 0, y: 0, width: width, height: height).fill()
        let title: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 22), .foregroundColor: NSColor.white]
        let small: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 18, weight: .medium),
                                                    .foregroundColor: NSColor.white]
        let flipped = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
        NSGraphicsContext.current = flipped
        for (row, step) in rows.enumerated() {
            let top = gap + CGFloat(row) * (rowHeight + gap)
            ("\(step.name) — by \(step.cause.rawValue)" as NSString).draw(at: CGPoint(x: gap, y: top + 4), withAttributes: title)
            for (column, offset) in offsets.enumerated() {
                let target = Double(step.at + offset) / 1000
                guard let index = frames.indices.min(by: { abs(frames[$0].time - target) < abs(frames[$1].time - target) }) else { continue }
                let rect = CGRect(x: gap + CGFloat(column) * (cellWidth + gap), y: top + rowTitle, width: cellWidth, height: cellHeight)
                if let image = images[index] {
                    context.cgContext.saveGState()
                    // Images draw upright in the flipped context by flipping them back locally.
                    context.cgContext.translateBy(x: rect.minX, y: rect.maxY)
                    context.cgContext.scaleBy(x: 1, y: -1)
                    let fit = min(cellWidth / CGFloat(image.width), cellHeight / CGFloat(image.height))
                    context.cgContext.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(image.width) * fit, height: CGFloat(image.height) * fit))
                    context.cgContext.restoreGState()
                } else {
                    ("no window on screen" as NSString).draw(at: CGPoint(x: rect.minX + 8, y: rect.midY), withAttributes: small)
                }
                let actual = Int(((frames[index].time * 1000) - Double(step.at)).rounded())
                let label = isOpening ? "\(actual) ms" : (actual >= 0 ? "+\(actual) ms" : "\(actual) ms")
                (label as NSString).draw(at: CGPoint(x: rect.minX + 2, y: rect.maxY + 3), withAttributes: small)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.representation(using: .png, properties: [:]) else { return nil }
        let url = FileManager.default.temporaryDirectory.appending(path: "\(name).png")
        return (try? data.write(to: url)) != nil ? url : nil
    }
}

/// Captures Stow's windows as fast as the window server gives them, off the main thread.
nonisolated final class FrameGrabber: @unchecked Sendable {
    /// `image` is nil while none of Stow's windows is on screen.
    struct Frame { let time: Double; let image: CGImage? }

    private let lock = NSLock()
    private var _ids: [CGWindowID] = []
    private var frames: [Frame] = []
    private var running = false
    private var thread: Thread?

    var windowIDs: [CGWindowID] {
        get { lock.withLock { _ids } }
        set { lock.withLock { _ids = newValue } }
    }

    func start(at start: Double, bestResolution: Bool) {
        lock.withLock { running = true }
        typealias CreateImage = @convention(c) (CGRect, CFArray, UInt32) -> Unmanaged<CGImage>?
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY),
              let symbol = dlsym(handle, "CGWindowListCreateImageFromArray") else { return }
        let create = unsafeBitCast(symbol, to: CreateImage.self)
        let thread = Thread { [self] in
            while lock.withLock({ running }) {
                let ids = windowIDs
                guard !ids.isEmpty else {
                    let time = ProcessInfo.processInfo.systemUptime - start
                    lock.withLock { frames.append(Frame(time: time, image: nil)) }
                    usleep(8000)
                    continue
                }
                var pointers = ids.map { UnsafeRawPointer(bitPattern: UInt($0)) }
                guard let array = CFArrayCreate(nil, &pointers, pointers.count, nil) else { continue }
                // Frame only (no shadow); one pixel per point unless it's a close-up.
                if let image = create(.null, array, 1 << 0 | (bestResolution ? 1 << 3 : 1 << 4))?.takeRetainedValue() {
                    let time = ProcessInfo.processInfo.systemUptime - start
                    lock.withLock { frames.append(Frame(time: time, image: image)) }
                }
            }
        }
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
    }

    func stop() -> [Frame] {
        lock.withLock {
            running = false
            return frames
        }
    }
}
