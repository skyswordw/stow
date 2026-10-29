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

    @Test func closingWelcomeCancelsPendingOpenAndIgnoresLateFailure() async throws {
        let app = AppState()
        app.open(URL(filePath: "/tmp/Absent-\(UUID().uuidString).zip"))
        #expect(app.isOpening)
        app.mainWindowDidClose(.welcome)
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
}
