import AppKit
import Testing
@testable import Stow

@MainActor
@Suite("Opening window ownership")
struct OpeningWindowTests {
    @Test func nativeBrowserCloseClearsArchiveWithoutPresentingWelcome() {
        let app = AppState()
        app.openArchive(named: "Closed.zip")
        var presentations = 0
        app.showMainWindow = { presentations += 1 }
        app.mainWindowDidClose(.browser)
        #expect(app.browser == nil)
        #expect(app.mainWindowDismissed)
        #expect(!app.isOpening && presentations == 0)
        app.prepareToShowMainWindow()
        #expect(!app.mainWindowDismissed && app.browser == nil)
    }

    @Test func welcomeHandoverDoesNotCloseTheNewArchive() throws {
        let app = AppState()
        app.openArchive(named: "Opened.zip")
        let browser = try #require(app.browser)
        app.mainWindowDidClose(.welcome)
        #expect(app.browser === browser)
        #expect(!app.mainWindowDismissed)
    }

    @Test func closingLoadingBrowserCancelsPendingOpenAndIgnoresLateFailure() async throws {
        let app = AppState()
        app.open(URL(filePath: "/tmp/Absent-\(UUID().uuidString).zip"))
        #expect(app.isOpening)
        app.mainWindowDidClose(.browser)
        #expect(!app.isOpening && app.mainWindowDismissed)
        // Let the cancelled task run its cleanup; it must not restore content or a failure sheet.
        try await Task.sleep(for: .milliseconds(100))
        #expect(app.browser == nil && app.openFailure == nil)
    }

    @Test func collapseTransfersOwnershipBeforeClosingTheBrowserWindow() throws {
        let app = AppState()
        app.openArchive(named: "Transfer.zip")
        let browser = try #require(app.browser)
        app.glance.presentsWindow = false
        app.glance.closeMainWindow = { app.mainWindowDidClose(.browser) }
        defer { app.glance.closeMainWindow = {} }
        app.glance.collapse(near: .zero, animated: false)
        #expect(app.browser === browser && app.glance.isShown)
        #expect(!app.mainWindowDismissed)
    }

    @Test func handledReopenDoesNotAlsoAskAppKitToRestoreClosedWindows() {
        let app = AppState(), delegate = AppDelegate()
        delegate.app = app
        var presentations = 0
        app.showMainWindow = { presentations += 1 }
        #expect(!delegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: false))
        #expect(presentations == 1)
        #expect(delegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: true))
        #expect(presentations == 1)
    }

    @Test func closingAnObsoleteBrowserCannotCancelTheReplacementLoad() {
        // AppState.open cancels the provisional listing for A, clears browser, then starts B.
        // The nil browser hands over to Welcome; closing A's old window must not cancel B.
        #expect(!WindowSwitch.ownsOpening(.browser, hasArchive: false, glanceIsShown: false))
        #expect(WindowSwitch.ownsOpening(.welcome, hasArchive: false, glanceIsShown: false))
    }

    @Test func normalCloseStillCancelsTheLoadOwnedByThatWindow() {
        #expect(WindowSwitch.ownsOpening(.browser, hasArchive: true, glanceIsShown: false))
        #expect(!WindowSwitch.ownsOpening(.welcome, hasArchive: true, glanceIsShown: false))
    }

    @Test func compactPresentationOwnsTheLoadWhenFullWindowsAreClosed() {
        for hasArchive in [false, true] {
            #expect(!WindowSwitch.ownsOpening(.browser, hasArchive: hasArchive, glanceIsShown: true))
            #expect(!WindowSwitch.ownsOpening(.welcome, hasArchive: hasArchive, glanceIsShown: true))
        }
    }
    @Test func anOldOperationCannotCloseAReplacementArchiveOrCancelItsLoad() async throws {
        let app = AppState()
        app.openArchive(named: "Old.zip")
        let old = try #require(app.browser)
        app.open(URL(filePath: "/tmp/Replacement-\(UUID()).zip"))
        old.onCloseWindow?()
        #expect(app.isOpening, "The old operation must not cancel the new load")
        app.cancelOpening()
        app.openArchive(named: "New.zip")
        let replacement = try #require(app.browser)
        old.onArchiveGone?()
        try await Task.sleep(for: .milliseconds(50))
        #expect(app.browser === replacement)
    }

    @Test func aQueuedArchiveCloseDoesNotDiscardAReplacementSession() async throws {
        let app = AppState()
        app.openArchive(named: "Old.zip")
        app.closeArchive()
        app.openArchive(named: "Replacement.zip")
        let replacement = try #require(app.browser)
        try await Task.sleep(for: .milliseconds(50))
        #expect(app.browser === replacement)
    }

    @Test func automaticArchiveCloseDoesNotCloseTheCreationWorkspace() {
        let app = AppState()
        app.openArchive(named: "Working.zip")
        let archive = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                               styleMask: [.titled, .closable], backing: .buffered, defer: false)
        let creation = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                                styleMask: [.titled, .closable], backing: .buffered, defer: false)
        app.browser?.editingWindow = archive
        archive.identifier = NSUserInterfaceItemIdentifier("main-ownership-test")
        creation.identifier = NSUserInterfaceItemIdentifier("creation-ownership-test")
        archive.isReleasedWhenClosed = false
        creation.isReleasedWhenClosed = false
        archive.orderFrontRegardless()
        creation.makeKeyAndOrderFront(nil)
        defer { archive.orderOut(nil); creation.orderOut(nil) }
        app.closeWindow()
        #expect(!archive.isVisible && creation.isVisible)
    }

}
