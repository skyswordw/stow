import AppKit
import Testing
@testable import Stow

@MainActor
@Suite("File Close command", .serialized)
struct WindowCloseCommandTests {
    @Test func applicationMenuKeepsCommandWSeparateFromCloseArchive() async throws {
        func items(in menu: NSMenu) -> [NSMenuItem] {
            menu.items.flatMap { [$0] + ($0.submenu.map { items(in: $0) } ?? []) }
        }
        let menu = try #require(NSApp.mainMenu)
        menu.update()
        let commands = items(in: menu).filter { $0.keyEquivalent.lowercased() == "w" }
        let close = commands.filter { $0.keyEquivalentModifierMask == .command }
        #expect(close.count == 1)
        #expect(close.first?.title == String(localized: "Close"))
        #expect(commands.contains {
            $0.title == String(localized: "Close Archive") && $0.keyEquivalentModifierMask == [.command, .shift]
        })
    }

    @Test(arguments: ["welcome", "settings"])
    func ordinaryWindowClosesWithoutTouchingArchive(_ identifier: String) throws {
        let app = AppState(), command = WindowCloseCommand(), window = makeWindow(identifier)
        defer { window.orderOut(nil) }
        app.openArchive(named: "Keep.zip")
        let browser = try #require(app.browser)
        window.makeKeyAndOrderFront(nil)
        #expect(WindowCloseCommand.canClose(window))
        command.perform(in: window, app: app)
        #expect(!window.isVisible)
        #expect(app.browser === browser)
    }

    @Test func noWindowAndNonclosableWindowDisableClose() {
        let window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        #expect(!WindowCloseCommand.canClose(nil))
        #expect(!WindowCloseCommand.canClose(window))
    }

    @Test func attachedSheetBlocksClosingBothSheetAndParent() {
        let app = AppState(), command = WindowCloseCommand()
        let parent = makeWindow("parent"), sheet = makeWindow("sheet")
        parent.makeKeyAndOrderFront(nil)
        parent.beginSheet(sheet)
        defer { parent.endSheet(sheet); sheet.orderOut(nil); parent.orderOut(nil) }
        #expect(!WindowCloseCommand.canClose(parent))
        #expect(!WindowCloseCommand.canClose(sheet))
        command.perform(in: parent, app: app)
        command.perform(in: sheet, app: app)
        #expect(parent.isVisible && parent.attachedSheet === sheet)
    }

    @Test func browserCloseAsksToSaveAndCancelKeepsEdits() async throws {
        let app = AppState(), command = WindowCloseCommand(), window = makeWindow("close-test-browser")
        let model = BrowserModel(archive: Archive(listing: ArchiveListing(type: "zip", entries: [
            ListedEntry(path: "keep.txt", isFolder: false, size: 1)
        ]), url: URL(filePath: "/tmp/Close-\(UUID().uuidString).zip")))
        app.browser = model
        let delegate = EditingWindowDelegate()
        delegate.attach(window, model: model)
        defer { window.delegate = nil; window.orderOut(nil) }
        model.editSession.delete(["keep.txt"])
        window.makeKeyAndOrderFront(nil)
        command.perform(in: window, app: app)
        try await wait { window.attachedSheet != nil }
        let sheet = try #require(window.attachedSheet)
        #expect(window.isVisible && model.editSession.isEdited)
        let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: sheet.windowNumber, context: nil, characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        #expect(sheet.performKeyEquivalent(with: escape))
        try await wait { window.attachedSheet == nil }
        #expect(window.isVisible && model.editSession.isEdited)
    }

    @Test func glanceUsesItsClosePathAndKeepsTheArchive() throws {
        let app = AppState(), command = WindowCloseCommand()
        app.openArchive(named: "Glance.zip")
        let browser = try #require(app.browser)
        app.glance.closeMainWindow = {}
        app.glance.collapse(near: .zero, animated: false)
        defer { app.glance.close() }
        let window = try #require(app.glance.window)
        #expect(window.standardWindowButton(.closeButton)?.isHidden == true)
        command.perform(in: window, app: app)
        #expect(!app.glance.isShown && !window.isVisible)
        #expect(app.browser === browser)
    }

    @Test func closingGlanceWhileOpeningCancelsThePendingOpen() async throws {
        let app = AppState(), command = WindowCloseCommand()
        app.glance.closeMainWindow = {}
        app.glance.open(URL(filePath: "/tmp/Absent-Close-\(UUID().uuidString).zip"))
        defer { app.glance.close(); app.cancelOpening() }
        let window = try #require(app.glance.window)
        #expect(app.isOpening && app.glance.pendingName != nil)
        command.perform(in: window, app: app)
        #expect(!app.isOpening && !app.glance.isShown)
        try await Task.sleep(for: .milliseconds(100))
        #expect(app.browser == nil && app.openFailure == nil)
    }

    @Test func trayClosesThroughItsControllerAndKeepsItsItems() throws {
        let app = AppState(), command = WindowCloseCommand()
        app.tray.show()
        defer { app.tray.hide() }
        let panel = try #require(NSApp.windows.compactMap { $0 as? TrayPanel }.first {
            $0.trayUndoManager === app.tray.undoManager
        })
        let items = app.tray.items.map(\.id)
        #expect(WindowCloseCommand.canClose(panel))
        command.perform(in: panel, app: app)
        #expect(!app.tray.isShown)
        #expect(app.tray.items.map(\.id) == items)
    }

    private func makeWindow(_ identifier: String) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 350),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.identifier = NSUserInterfaceItemIdentifier(identifier)
        window.isReleasedWhenClosed = false
        window.contentView = NSView()
        return window
    }

    private func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        try #require(condition(), "Timed out waiting for the close prompt")
    }
}
