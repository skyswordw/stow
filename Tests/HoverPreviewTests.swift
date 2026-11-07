import AppKit
import Testing
@testable import Stow

@MainActor
@Suite("Hover preview interaction cancellation", .serialized)
struct HoverPreviewTests {
    private func entry(_ name: String = "alpha.txt") -> ArchiveEntry {
        ArchiveEntry(path: name, isFolder: false, size: 1, packedSize: 1, modified: .now)
    }

    @Test func closingDuringTheDelayCancelsPresentation() async throws {
        let hover = HoverPreviewModel(mouseButtons: { 0 })
        hover.enter(entry())
        hover.close()
        try await Task.sleep(for: .milliseconds(550))
        #expect(hover.presented == nil)
    }

    @Test func buttonPressedAfterEnteringPreventsDelayedPresentation() async throws {
        var buttons = 0
        let hover = HoverPreviewModel(mouseButtons: { buttons })
        hover.enter(entry())
        // Covers a button change even if native tracking prevented delivery of a local event.
        buttons = 1
        try await Task.sleep(for: .milliseconds(550))
        #expect(hover.presented == nil)
        buttons = 0
        hover.enter(entry())
        #expect(hover.presented == nil)
        hover.close()
    }

    @Test func interruptionEndsWarmScanningAndCancelsPendingWork() async throws {
        let hover = HoverPreviewModel(mouseButtons: { 0 })
        hover.present("alpha.txt")
        hover.enter(entry("beta.txt"))
        #expect(hover.presented == "beta.txt")
        hover.interrupt()
        #expect(hover.presented == nil)
        hover.enter(entry())
        #expect(hover.presented == nil)
        hover.interrupt()
        try await Task.sleep(for: .milliseconds(550))
        #expect(hover.presented == nil)
    }

    @Test func nativePressCancelsPendingPreviewWithoutConsumingTheEvent() async throws {
        let hover = HoverPreviewModel(mouseButtons: { 0 })
        let window = NSWindow()
        var presses = 0
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            MainActor.assumeIsolated { presses += 1 }
            return event
        }
        defer { if let monitor { NSEvent.removeMonitor(monitor) } }
        hover.enter(entry())
        let event = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero,
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        NSApp.sendEvent(event)
        #expect(presses == 1)
        try await Task.sleep(for: .milliseconds(550))
        #expect(hover.presented == nil)
    }

    @Test func losingTheKeyWindowCancelsAPendingPreview() async throws {
        let hover = HoverPreviewModel(mouseButtons: { 0 })
        hover.enter(entry())
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: NSWindow())
        try await Task.sleep(for: .milliseconds(550))
        #expect(hover.presented == nil)
    }

    @Test func enteringWithAButtonDownClosesAnOpenPreview() {
        var buttons = 0
        let hover = HoverPreviewModel(mouseButtons: { buttons })
        hover.present("alpha.txt")
        buttons = 1
        hover.enter(entry("beta.txt"))
        #expect(hover.presented == nil)
        buttons = 0
        hover.enter(entry())
        #expect(hover.presented == nil)
        hover.close()
    }

    @Test func ordinaryHoverExitRetainsWarmNeighborBehavior() {
        let hover = HoverPreviewModel(mouseButtons: { 0 })
        hover.present("alpha.txt")
        hover.close()
        hover.enter(entry("beta.txt"))
        #expect(hover.presented == "beta.txt")
        hover.close()
    }
}
