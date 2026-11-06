import AppKit
import Testing
@testable import Stow

@Suite("Tray dismissal", .serialized)
struct TrayDismissalTests {
    @Test func outsideClickRequiresAnEntireClickNotADrag() {
        var click = TrayOutsideClick()
        let released1 = click.release(button: 0, outside: true)
        #expect(!released1, "The drop that revealed Tray has no matching press")
        click.press(button: 0, outside: true)
        click.drag()
        let released2 = click.release(button: 0, outside: true)
        #expect(!released2, "Dragging in Finder must not hide Tray")
        click.press(button: 0, outside: false)
        let released3 = click.release(button: 0, outside: true)
        #expect(!released3, "A drag starting in Tray must not dismiss it")
        click.press(button: 0, outside: true)
        let released4 = click.release(button: 0, outside: false)
        #expect(!released4, "Releasing over Tray is not an outside click")
        click.press(button: 1, outside: true)
        let released5 = click.release(button: 1, outside: true)
        #expect(released5)
        let released6 = click.release(button: 1, outside: true)
        #expect(!released6, "A release cannot be reused")
        click.press(button: 0, outside: true)
        click.cancel()
        let released7 = click.release(button: 0, outside: true)
        #expect(!released7, "Menu/open transitions discard stale presses")
    }

    @Test @MainActor func eventAdapterDelaysDismissalAndProtectsRelatedWindows() throws {
        let monitor = TrayDismissalMonitor()
        let related = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 20, height: 20),
                               styleMask: .borderless, backing: .buffered, defer: false)
        var allowed = true
        var dismissals = 0
        var releases = 0
        monitor.canDismiss = { allowed }
        monitor.dismiss = { dismissals += 1 }
        monitor.mouseReleased = { releases += 1 }
        monitor.isRelatedWindow = { $0 === related }
        func event(_ type: NSEvent.EventType, window: NSWindow? = nil) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0,
                                            windowNumber: window?.windowNumber ?? 0, context: nil,
                                            eventNumber: 0, clickCount: 1, pressure: 0))
        }
        monitor.handle(try event(.leftMouseDown), local: false)
        #expect(dismissals == 0)
        monitor.handle(try event(.leftMouseDragged), local: false)
        monitor.handle(try event(.leftMouseUp), local: false)
        #expect(dismissals == 0)
        monitor.handle(try event(.leftMouseDown), local: false)
        allowed = false // A picker or pin opened while this press was in flight.
        monitor.handle(try event(.leftMouseUp), local: false)
        #expect(dismissals == 0)
        allowed = true
        monitor.handle(try event(.leftMouseDown, window: related), local: true)
        monitor.handle(try event(.leftMouseUp, window: related), local: true)
        #expect(dismissals == 0)
        monitor.handle(try event(.leftMouseDown), local: false)
        monitor.handle(try event(.leftMouseUp), local: false)
        #expect(dismissals == 1)
        #expect(releases == 4, "Local releases must also finish inbound drags")
    }

    @Test @MainActor func dismissalPreservesDraftFilesAndPinPreference() throws {
        let name = "TrayDismissalTests.\(UUID())"
        let store = try #require(UserDefaults(suiteName: name))
        defer { store.removePersistentDomain(forName: name) }
        store.set(0, forKey: "tray.idleSeconds") // Old Never is not an implicit pin.
        store.set(true, forKey: SettingsKeys.trayEnabled)
        let tray = TrayController(settings: store)
        defer { tray.hide() }
        #expect(!tray.isPinned)
        let file = URL(filePath: "/tmp/Tray-dismissal-fixture.txt")
        tray.add([file])
        tray.beginCollecting()
        tray.collectingName = "Unsubmitted name"
        let destination = tray.collectDestination
        tray.show()
        tray.dismissForOutsideInteraction()
        #expect(!tray.isShown)
        #expect(tray.items.map(\.url) == [file])
        #expect(tray.collectingName == "Unsubmitted name")
        #expect(tray.collectDestination == destination)
        tray.show()
        tray.isPinned = true
        tray.dismissForOutsideInteraction()
        #expect(tray.isShown)
        tray.hide()
        #expect(!tray.isShown, "Explicit close works even when pinned")
        let reopened = TrayController(settings: store)
        #expect(reopened.isPinned && !reopened.isShown, "Remembering pin must not open on startup")
        tray.show()
        tray.isPinned = false
        #expect(tray.isShown, "Unpin must not immediately hide")
        tray.dismissForOutsideInteraction()
        #expect(!tray.isShown)
    }

    @Test @MainActor func nestedInteractionsAndDropTargetProtectTray() throws {
        let name = "TrayDismissalTests.\(UUID())"
        let store = try #require(UserDefaults(suiteName: name))
        defer { store.removePersistentDomain(forName: name) }
        store.set(true, forKey: SettingsKeys.trayEnabled)
        let tray = TrayController(settings: store)
        defer { tray.hide() }
        tray.show()
        let picker = tray.beginRelatedInteraction()
        let sharing = tray.beginRelatedInteraction()
        tray.dismissForOutsideInteraction()
        #expect(tray.isShown)
        tray.endRelatedInteraction(picker)
        tray.dismissForOutsideInteraction()
        #expect(tray.isShown, "Another owned surface is still active")
        tray.endRelatedInteraction(sharing)
        tray.isDropTargeted = true
        tray.dismissForOutsideInteraction()
        #expect(tray.isShown)
        tray.isDropTargeted = false
        #expect(tray.isShown, "Completing an interaction must not itself hide Tray")
        tray.dismissForOutsideInteraction()
        #expect(!tray.isShown)
    }

    @Test @MainActor func staleUnusedDragCannotHideAcceptedDropOrUnpinnedTray() async throws {
        let name = "TrayDismissalTests.\(UUID())"
        let store = try #require(UserDefaults(suiteName: name))
        defer { store.removePersistentDomain(forName: name) }
        store.set(true, forKey: SettingsKeys.trayEnabled)
        // This exercises stale task cancellation; pointer event delivery has separate adapter tests.
        let tray = TrayController(settings: store, monitorsSystemEvents: false)
        defer { tray.hide() }
        let file = URL(filePath: "/tmp/Tray-drag-fixture.txt")
        tray.add([file])
        tray.beginFileDrag()
        tray.show(fromDrag: true)
        tray.dismissForOutsideInteraction()
        #expect(tray.isShown, "An inbound drag protects the panel")
        tray.endFileDrag(overTray: false)
        tray.add([file]) // Duplicate acceptance must also cancel the unused-drag task.
        try await Task.sleep(for: .seconds(1))
        #expect(tray.isShown && tray.items.count == 1)
        tray.hide()
        tray.beginFileDrag()
        tray.show(fromDrag: true)
        tray.endFileDrag(overTray: false)
        tray.isPinned = true
        tray.isPinned = false
        try await Task.sleep(for: .seconds(1))
        #expect(tray.isShown, "Unpin cannot revive an old dismissal")
        tray.hide()
        tray.beginFileDrag()
        tray.show(fromDrag: true)
        tray.endFileDrag(overTray: false)
        tray.hide()
        tray.show()
        try await Task.sleep(for: .seconds(1))
        #expect(tray.isShown, "Reopening manually invalidates the previous drag's dismissal")
    }

}
