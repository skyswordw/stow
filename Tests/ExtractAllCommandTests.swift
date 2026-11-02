import AppKit
import Testing
@testable import Stow

@MainActor
@Suite("File Extract All command", .serialized)
struct ExtractAllCommandTests {
    @Test func menuPairsTheTwoScopesWithDistinctShortcuts() throws {
        func items(in menu: NSMenu) -> [NSMenuItem] {
            menu.items.flatMap { [$0] + ($0.submenu.map { items(in: $0) } ?? []) }
        }
        let menu = try #require(NSApp.mainMenu)
        menu.update()
        let commands = items(in: menu).filter { $0.keyEquivalent.lowercased() == "e" }
        let all = commands.filter { $0.keyEquivalentModifierMask == [.command, .shift] }
        #expect(all.count == 1)
        let item = try #require(all.first)
        #expect(item.title == String(localized: "Extract All"))
        let parent = try #require(item.menu)
        let index = parent.index(of: item)
        try #require(index > 0)
        let selection = try #require(parent.item(at: index - 1))
        #expect(selection.title == String(localized: "Extract"))
        #expect(selection.keyEquivalent.lowercased() == "e")
        #expect(selection.keyEquivalentModifierMask == .command)
    }

    @Test(arguments: [false, true])
    func extractsTheWholeArchiveWithoutChangingSelection(hasSelection: Bool) {
        let fixture = Fixture()
        defer { fixture.close() }
        let selection: Set<String> = hasSelection ? ["alpha.txt"] : []
        fixture.model.select(selection)
        fixture.command.perform(in: fixture.window)
        // The source-free model records the actual dispatch scope synchronously in its activity.
        // Engine extraction and helper filtering are covered by the existing extraction suites.
        #expect(fixture.model.activity?.step == .extract)
        #expect(fixture.model.activity?.itemCount == 2)
        #expect(fixture.model.selection == selection)
    }

    @Test func availabilityMatchesTheButtonAndIsRecheckedAtDispatch() {
        let fixture = Fixture(isListing: true)
        defer { fixture.close() }
        #expect(!fixture.command.isEnabled)
        fixture.command.perform(in: fixture.window)
        #expect(fixture.model.activity == nil)
        fixture.model.applyListing(fixture.model.archive, complete: true)
        #expect(fixture.command.isEnabled)

        fixture.model.previewActivity(.init(step: .pack, itemCount: 7, phase: .running(0.5)))
        #expect(!fixture.command.isEnabled)
        fixture.command.perform(in: fixture.window)
        #expect(fixture.model.activity?.step == .pack)
        #expect(fixture.model.activity?.itemCount == 7)

        fixture.model.previewActivity(.init(step: .pack, itemCount: 7, phase: .done))
        #expect(fixture.command.isEnabled)
        #expect(fixture.model.extractAllUnavailableReason == nil)
        fixture.command.perform(in: fixture.window)
        #expect(fixture.model.activity?.step == .extract)
        #expect(fixture.model.activity?.itemCount == 2)
    }

    @Test func unrelatedWindowAndMissingWindowCannotExtractTheBackgroundArchive() {
        let fixture = Fixture()
        defer { fixture.close() }
        let settings = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        defer { settings.orderOut(nil) }
        var focusedWindow: NSWindow? = fixture.window
        let command = ExtractAllCommand(currentWindow: { focusedWindow })
        #expect(command.isEnabled)
        focusedWindow = settings
        command.refresh()
        #expect(!command.isEnabled && command.target == nil)
        command.perform(in: settings)
        focusedWindow = nil
        command.refresh()
        #expect(!command.isEnabled)
        command.perform(in: nil)
        #expect(fixture.model.activity == nil)

        // The retained Browser delegate must not route to a model that has moved to Glance.
        fixture.model.editingWindow = settings
        fixture.command.perform(in: fixture.window)
        #expect(fixture.model.activity == nil)
    }

    @Test func archiveTextEditingDoesNotDisableExtractAll() {
        let fixture = Fixture()
        defer { fixture.close() }
        let editor = NSTextView(frame: fixture.window.contentView!.bounds)
        editor.isEditable = true
        fixture.window.contentView = editor
        fixture.window.makeFirstResponder(editor)
        fixture.command.refresh()
        #expect(fixture.command.isEnabled)
        fixture.command.perform(in: fixture.window)
        #expect(fixture.model.activity?.itemCount == 2)
    }

    @Test func sheetBlocksBothItsOwnWindowAndTheArchiveUntilDismissed() {
        let fixture = Fixture()
        defer { fixture.close() }
        let sheet = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        fixture.window.beginSheet(sheet)
        fixture.command.refresh()
        #expect(!fixture.command.isEnabled)
        fixture.command.perform(in: fixture.window)
        fixture.command.perform(in: sheet)
        #expect(fixture.model.activity == nil)
        fixture.window.endSheet(sheet)
        sheet.orderOut(nil)
        fixture.window.makeKeyAndOrderFront(nil)
        fixture.command.refresh()
        #expect(fixture.command.isEnabled)
    }

    @Test func glanceRoutesToItsArchiveEvenWithASelection() async throws {
        let app = AppState()
        app.openArchive(named: "Glance.zip")
        let model = try #require(app.browser)
        app.glance.closeMainWindow = {}
        app.glance.collapse(near: .zero, animated: false)
        defer { model.cancelActivity(); app.glance.close() }
        let window = try #require(app.glance.window)
        let deadline = ContinuousClock.now + .seconds(5)
        while ExtractAllCommand.model(in: window) == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(ExtractAllCommand.model(in: window) === model)
        let selected = try #require(model.archive.files.first)
        model.select([selected.id])
        ExtractAllCommand().perform(in: window)
        #expect(model.activity?.itemCount == model.archive.files.count)
        #expect(model.selection == [selected.id])
    }

    private final class Fixture {
        let model: BrowserModel
        let window: NSWindow
        let delegate = EditingWindowDelegate()
        let command: ExtractAllCommand

        init(isListing: Bool = false) {
            model = BrowserModel(archive: Archive(name: "Scope.zip", format: .zip, files: [
                ArchiveEntry(path: "alpha.txt", isFolder: false, size: 1, packedSize: 1, modified: .now),
                ArchiveEntry(path: "beta.txt", isFolder: false, size: 1, packedSize: 1, modified: .now)
            ]), isListing: isListing)
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = NSView()
            // The runner need not be the foreground app: supply its key window deterministically.
            command = ExtractAllCommand(currentWindow: { [weak window] in window })
            delegate.attach(window, model: model)
            window.makeKeyAndOrderFront(nil)
            command.refresh()
        }

        func close() {
            model.cancelActivity()
            window.delegate = nil
            window.orderOut(nil)
            command.refresh()
        }
    }
}
