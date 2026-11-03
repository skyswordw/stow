import AppKit
import Testing
@testable import Stow

/// `SearchFieldFocus` in plain AppKit: a stand-in for the toolbar item (Search's field and the
/// anchor) and another field in the window's content that the keyboard can move to.
@MainActor
@Suite("Search field focus requests", .serialized)
struct SearchFieldFocusTests {
    /// The toolbar can build the field before it puts it in the window: the request waits for it.
    @Test func aRequestWaitsForTheFieldToReachTheWindow() async {
        let harness = Harness(attached: false)
        harness.focus.request()
        await harness.drainMainQueue()
        #expect(!harness.holdsKeyboard(harness.search))
        harness.attach()
        await harness.drainMainQueue()
        #expect(harness.holdsKeyboard(harness.search))
    }

    /// Search lets go after the field reaches the window but before the waiting request runs.
    @Test func lettingGoAfterTheFieldArrivesKeepsTheKeyboardWhereItWent() async {
        let harness = Harness(attached: false)
        harness.focus.request()
        await harness.drainMainQueue()
        harness.attach()
        harness.focus.cancel()
        harness.window.makeFirstResponder(harness.other)
        #expect(harness.holdsKeyboard(harness.other))
        await harness.drainMainQueue()
        #expect(harness.holdsKeyboard(harness.other))
    }

    /// Search lets go while a request is still queued for the next turn (Esc releases the same way).
    @Test(arguments: [false, true])
    func lettingGoCancelsAQueuedRequest(byEscape: Bool) async {
        let harness = Harness(attached: true)
        harness.focus.request()
        if byEscape { harness.focus.release() } else { harness.focus.cancel() }
        harness.window.makeFirstResponder(harness.other)
        await harness.drainMainQueue()
        #expect(harness.holdsKeyboard(harness.other))
    }

    /// A request after letting go still works: cancelling only drops what came before it.
    @Test func aNewRequestAfterLettingGoTakesTheKeyboard() async {
        let harness = Harness(attached: false)
        harness.focus.request()
        await harness.drainMainQueue()
        harness.focus.cancel()
        harness.window.makeFirstResponder(harness.other)
        harness.focus.request()
        harness.attach()
        await harness.drainMainQueue()
        #expect(harness.holdsKeyboard(harness.search))
    }

    private final class Harness {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let focus = SearchFieldFocus()
        /// Stands in for the toolbar item's hosting view.
        let item = NSView(frame: NSRect(x: 0, y: 100, width: 240, height: 30))
        let search = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        let other = NSTextField(frame: NSRect(x: 0, y: 20, width: 200, height: 24))

        init(attached: Bool) {
            item.addSubview(search)
            item.addSubview(focus.makeAnchor())
            window.contentView?.addSubview(other)
            if attached { attach() }
        }

        func attach() { window.contentView?.addSubview(item) }

        func holdsKeyboard(_ field: NSTextField) -> Bool {
            (window.firstResponder as? NSText)?.delegate === field
        }

        /// Runs everything already queued on the main queue, and what that queues in turn.
        func drainMainQueue() async {
            for _ in 0..<3 {
                await withCheckedContinuation { done in DispatchQueue.main.async { done.resume() } }
            }
        }
    }
}
