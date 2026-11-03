import AppKit
import Testing
@testable import Stow

@Suite("Editing window delegate ownership")
@MainActor
struct WindowDelegateOwnershipTests {
    private final class NativeDelegate: NSObject, NSWindowDelegate {
        var keyNotifications = 0
        func windowDidBecomeKey(_ notification: Notification) { keyNotifications += 1 }
        func windowShouldClose(_ sender: NSWindow) -> Bool { false }
    }

    @Test func rebuiltViewsNeverChainTheirEditingDelegates() {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        let native = NativeDelegate()
        window.delegate = native
        let first = EditingWindowDelegate(), second = EditingWindowDelegate()
        let model = BrowserModel(archive: SampleArchive.make())
        defer { window.delegate = nil }
        // Window delegate installation itself queries optional selectors through responds(to:).
        for _ in 0..<50 {
            first.attach(window, model: model)
            second.attach(window, model: model)
            #expect(first.original === native && second.original === native)
            #expect(!second.windowShouldClose(window))
            #expect(!second.responds(to: NSSelectorFromString("unknownWindowDelegateMethod:")))
        }
        #expect(window.delegate === second)
    }

    @Test func lateKeyNotificationCannotReinstallAnObsoleteDelegate() {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        let native = NativeDelegate()
        window.delegate = native
        let first = EditingWindowDelegate(), second = EditingWindowDelegate()
        let old = BrowserModel(archive: SampleArchive.make(named: "Old.zip"))
        let current = BrowserModel(archive: SampleArchive.make(named: "Current.zip"))
        defer { window.delegate = nil }
        first.attach(window, model: old)
        second.attach(window, model: current)
        let event = Notification(name: NSWindow.didBecomeKeyNotification, object: window)
        first.windowDidBecomeKey(event)
        #expect(window.delegate === second && native.keyNotifications == 0)
        second.windowDidBecomeKey(event)
        #expect(window.delegate === second && native.keyNotifications == 1)
        #expect(second.windowWillReturnUndoManager(window) === current.editingUndoManager)
    }
}
