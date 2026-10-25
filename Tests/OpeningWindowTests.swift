import Testing
@testable import Stow

@MainActor
@Suite("Opening window ownership")
struct OpeningWindowTests {
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
