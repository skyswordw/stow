import AppKit
import SwiftUI
import Testing
@testable import Stow

@MainActor
@Suite("Browser search focus", .serialized)
struct BrowserFocusTests {
    @Test func columnsSearchKeepsTheEditorWhenTheResultsListAppears() async throws {
        let fixture = Fixture(mode: .columns)
        defer { fixture.close() }
        let editor = try await fixture.focusSearch()
        editor.insertText("al", replacementRange: NSRange(location: NSNotFound, length: 0))
        try await fixture.wait { fixture.model.visibleEntries.count == 1 }
        try await fixture.settle()
        #expect(fixture.window.firstResponder === editor)
        try await fixture.typeIntoSearch("p", expecting: "alp")
    }

    @Test(arguments: [BrowserModel.ViewMode.list, .grid, .columns])
    func matchingResultsKeepTheSearchEditor(mode: BrowserModel.ViewMode) async throws {
        let fixture = Fixture(mode: mode)
        defer { fixture.close() }
        fixture.model.query = "no_matches"
        try await fixture.wait { fixture.model.visibleEntries.isEmpty }
        let editor = try await fixture.focusSearch()
        fixture.model.query = "alpha"
        try await fixture.wait { fixture.model.visibleEntries.count == 1 }
        try await fixture.settle()
        #expect(fixture.window.firstResponder === editor)
        try await fixture.typeIntoSearch(".txt", expecting: "alpha.txt")
    }

    @Test func clearingSearchKeepsTheEditorWhenColumnsReturn() async throws {
        let fixture = Fixture(mode: .columns)
        defer { fixture.close() }
        fixture.model.query = "alpha"
        try await fixture.wait { fixture.model.visibleEntries.count == 1 }
        let editor = try await fixture.focusSearch()
        fixture.model.query = ""
        try await fixture.wait { fixture.model.visibleEntries.count == 2 }
        try await fixture.settle()
        #expect(fixture.window.firstResponder === editor)
        try await fixture.typeIntoSearch("beta", expecting: "beta")
    }

    @Test func theListStillTakesInitialKeyboardFocus() async throws {
        let fixture = Fixture(mode: .list)
        defer { fixture.close() }
        try await fixture.wait { fixture.window.firstResponder is NSTableView }
    }

    private final class Fixture {
        let model: BrowserModel
        let window: NSWindow
        let host: NSViewController

        init(mode: BrowserModel.ViewMode) {
            model = BrowserModel(archive: Archive(name: "Focus.zip", format: .zip, files: [
                ArchiveEntry(path: "alpha.txt", isFolder: false, size: 1, packedSize: 1, modified: .now),
                ArchiveEntry(path: "beta.txt", isFolder: false, size: 1, packedSize: 1, modified: .now),
            ]))
            model.viewMode = mode
            let app = AppState()
            app.browser = model
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 700),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            host = NSHostingController(rootView: BrowserView(model: model).environment(app))
            window.contentViewController = host
            host.view.layoutSubtreeIfNeeded()
        }

        func focusSearch() async throws -> NSTextView {
            try await settle()
            model.focusSearch()
            try await wait { self.window.firstResponder is NSTextView }
            return try #require(window.firstResponder as? NSTextView)
        }

        func settle() async throws {
            host.view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
            host.view.layoutSubtreeIfNeeded()
        }

        func typeIntoSearch(_ text: String, expecting query: String) async throws {
            let input = try #require(window.firstResponder as? NSTextInputClient)
            input.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
            try await wait { self.model.query == query }
        }

        func wait(_ condition: () -> Bool) async throws {
            let deadline = ContinuousClock.now + .seconds(3)
            while !condition(), ContinuousClock.now < deadline {
                try await settle()
            }
            try #require(condition())
        }

        func close() {
            window.contentViewController = nil
            window.orderOut(nil)
        }
    }
}
