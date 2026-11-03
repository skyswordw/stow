import AppKit
import Testing
@testable import Stow

@Suite("Finder menu callback threading")
@MainActor
struct FinderMenuPresentationTests {
    private nonisolated struct MenuBox: @unchecked Sendable { let menu: NSMenu }

    @Test func synchronousMainThreadRequestDoesNotDispatchBackToItself() {
        let menu = FinderMenuPresentation.makeMenu(actions: [.open], selectors: [NSSelectorFromString("openInStow:")])
        #expect(menu.items.map(\.title) == [FinderMenu.title(for: .open)])
    }

    @Test func finderXPCQueueCanSynchronouslyRequestNativeMenu() async {
        let box = await Task.detached { Self.menuFromCallback() }.value
        #expect(box.menu.items.map(\.title) == [FinderMenu.title(for: .extractHere), FinderMenu.title(for: .open)])
        #expect(box.menu.items.last?.action == NSSelectorFromString("openInStow:"))
    }
    private nonisolated static func menuFromCallback() -> MenuBox {
        #expect(!Thread.isMainThread)
        return MenuBox(menu: FinderMenuPresentation.makeMenu(actions: [.extractHere, .open],
            selectors: [NSSelectorFromString("extractHere:"), NSSelectorFromString("openInStow:")]))
    }
}
