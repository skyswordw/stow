import AppKit
import SwiftUI
import Testing
@testable import Stow

@MainActor
@Suite("Glance editing regression", .serialized)
struct GlanceEditingTests {
    private func model() -> BrowserModel {
        BrowserModel(archive: Archive(listing: ArchiveListing(type: "zip", entries: [
            ListedEntry(path: "alpha.txt", isFolder: false, size: 14),
            ListedEntry(path: "beta.txt", isFolder: false, size: 13),
            ListedEntry(path: "Folder/inside.txt", isFolder: false, size: 16)
        ]), url: URL(filePath: "/tmp/Interaction-\(UUID().uuidString).zip")))
    }

    @Test func compactRenameCreatesTheNativeEditorAndPreservesUndo() async throws {
        let app = AppState(), browser = model()
        app.browser = browser
        app.glance.presentsWindow = false
        app.glance.closeMainWindow = {}
        app.glance.collapse(near: .zero, animated: false)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 560),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: GlanceView(model: browser, glance: app.glance).environment(app))
        window.contentView = host
        defer { window.contentView = nil; window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()
        let entry = try #require(browser.archive.entry(at: "alpha.txt"))
        browser.beginRename(entry)
        var field: NSTextField?
        let deadline = ContinuousClock.now + .seconds(5)
        while field?.currentEditor() == nil, ContinuousClock.now < deadline {
            host.layoutSubtreeIfNeeded()
            field = renameField(in: host)
            if field?.currentEditor() == nil { try await Task.sleep(for: .milliseconds(20)) }
        }
        let activeField = try #require(field)
        #expect(activeField.stringValue == "alpha.txt")
        let editor = try #require(activeField.currentEditor())
        #expect(window.firstResponder === editor)
        #expect(editor.selectedRange == NSRange(location: 0, length: 5))
        browser.renameText = "renamed.txt"
        browser.commitRename()
        #expect(browser.renamingPath == nil)
        #expect(browser.editSession.isEdited)
        #expect(browser.editingUndoManager.canUndo)
        browser.editingUndoManager.undo()
        #expect(browser.archive.entry(at: "alpha.txt") != nil)
        #expect(!browser.editSession.isEdited)
    }

    @Test func renameTakesFocusWhenItsCellJoinsAWindowLater() async throws {
        let browser = model()
        let entry = try #require(browser.archive.entry(at: "alpha.txt"))
        browser.beginRename(entry)
        let host = NSHostingView(rootView: EditingName(model: browser, entry: entry))
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 40)
        host.layoutSubtreeIfNeeded()
        let field = try #require(renameField(in: host))
        // A Table can create a cell before it has a window. Let its initial work finish
        // before attaching it, as happens during native compact-window editing.
        try await Task.sleep(for: .milliseconds(50))
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil; window.orderOut(nil) }
        let deadline = ContinuousClock.now + .seconds(5)
        while field.currentEditor() == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let editor = try #require(field.currentEditor())
        #expect(window.firstResponder === editor)
        #expect(editor.selectedRange == NSRange(location: 0, length: 5))
    }

    private func renameField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable,
           field.accessibilityLabel() == String(localized: "Rename") { return field }
        return view.subviews.lazy.compactMap { renameField(in: $0) }.first
    }
}
