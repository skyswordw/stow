import AppKit
import Testing
@testable import Stow

@MainActor
@Suite("Editing window undo wiring")
struct EditingWindowTests {
    private func archive() -> Archive {
        Archive(listing: ArchiveListing(type: "zip", entries: [
            ListedEntry(path: "a.txt", isFolder: false, size: 1)
        ]), url: URL(filePath: "/tmp/Stow-Undo-\(UUID().uuidString).zip"))
    }

    @Test func reusedWindowRepresentsNewArchiveAndClearsSampleIdentity() {
        let first = BrowserModel(archive: archive()), second = BrowserModel(archive: archive())
        let delegate = EditingWindowDelegate(), window = NSWindow()
        delegate.attach(window, model: first)
        // Save / Save a Copy / Rename all notify through this callback.
        let saved = URL(filePath: "/tmp/Saved.zip")
        first.editSession.onURLChange?(saved)
        #expect(window.representedURL == saved)
        delegate.attach(window, model: second)
        #expect(window.representedURL == second.archive.source?.url)
        #expect(first.editingWindow == nil)
        first.editSession.onURLChange?(URL(filePath: "/tmp/Late.zip"))
        #expect(window.representedURL == second.archive.source?.url)
        let sample = BrowserModel(archive: Archive(name: "Sample", format: .zip, files: []))
        delegate.attach(window, model: sample)
        #expect(window.representedURL == nil)
    }

    @Test func streamedListingUpdatesRepresentedURLWithoutReattaching() {
        let model = BrowserModel(archive: archive(), isListing: true)
        let delegate = EditingWindowDelegate(), window = NSWindow()
        delegate.attach(window, model: model)
        let replacement = archive()
        model.applyListing(replacement, complete: false)
        #expect(window.representedURL == replacement.source?.url)
        model.applyListing(replacement, complete: true)
        #expect(window.representedURL == replacement.source?.url)
    }

    @Test func nestedNavigationAndWindowSwitchKeepOuterIdentityAndEdits() throws {
        let model = BrowserModel(archive: archive())
        let delegate = EditingWindowDelegate(), full = NSWindow(), glance = NSWindow()
        delegate.attach(full, model: model)
        let root = model.level
        let inner = BrowserModel.Level(archive: archive(), entryPath: "Inner.zip")
        model.editSession.rename("a.txt", to: "outer.txt")
        let undo = try #require(full.undoManager)
        model.navigate(to: "", levels: [root, inner])
        #expect(full.representedURL == root.archive.source?.url)
        // Adopting a new outer URL while nested must update the document identity.
        let copiedOuter = URL(filePath: "/tmp/Outer Copy.zip")
        root.edits.onURLChange?(copiedOuter)
        #expect(full.representedURL == copiedOuter)
        delegate.attach(glance, model: model)
        #expect(glance.representedURL == copiedOuter)
        #expect(glance.undoManager === undo)
        model.goBack()
        #expect(glance.representedURL == copiedOuter)
        model.goForward()
        #expect(glance.representedURL == copiedOuter)
        model.goUp()
        delegate.attach(full, model: model)
        #expect(full.representedURL == copiedOuter)
        #expect(full.isDocumentEdited && full.undoManager === undo)
        #expect(root.edits.pending.entries.contains { $0.path == "outer.txt" })
    }

    @Test func windowSuppliesNamedSingleEditUndoAndRedo() throws {
        let model = BrowserModel(archive: archive())
        let delegate = EditingWindowDelegate(), window = NSWindow()
        delegate.attach(window, model: model)
        let undo = try #require(window.undoManager)
        #expect(delegate.windowWillReturnUndoManager(window) === undo)
        #expect(model.editSession.undoManager === undo)
        let content = NSView()
        window.contentView = content
        #expect(content.undoManager === undo)
        let source = FileManager.default.temporaryDirectory.appending(path: "Undo-\(UUID().uuidString).txt")
        try Data("replacement".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let session = model.editSession
        session.add([source], into: "")
        #expect(undo.canUndo && undo.undoActionName == String(localized: "Add \(1) Items"))
        session.rename("a.txt", to: "b.txt")
        #expect(undo.undoActionName == String(localized: "Rename"))
        session.replace("b.txt", with: source)
        #expect(undo.undoActionName == String(localized: "Replace"))
        session.delete(["b.txt"])
        #expect(undo.undoActionName == String(localized: "Delete “\("b.txt")”"))
        for count in (0..<4).reversed() {
            undo.undo()
            #expect(session.operations.count == count)
            #expect(undo.canRedo)
        }
        for count in 1...4 {
            undo.redo()
            #expect(session.operations.count == count)
        }
    }

    @Test func finalListingConnectsBeforeViewUpdates() throws {
        let model = BrowserModel(archive: archive(), isListing: true)
        let delegate = EditingWindowDelegate(), window = NSWindow()
        delegate.attach(window, model: model)
        let undo = try #require(window.undoManager)
        model.applyListing(archive(), complete: true)
        // No second attach or SwiftUI onChange: a real streamed open replaces the session.
        #expect(model.editSession.undoManager === undo)
        model.editSession.rename("a.txt", to: "b.txt")
        #expect(undo.canUndo)
        undo.undo()
        #expect(model.editSession.operations.isEmpty)
    }

    @Test func anotherArchiveAndWindowSwitchKeepHistoriesSeparate() throws {
        let first = BrowserModel(archive: archive()), second = BrowserModel(archive: archive())
        let delegate = EditingWindowDelegate(), full = NSWindow(), glance = NSWindow()
        delegate.attach(full, model: first)
        let firstUndo = try #require(full.undoManager)
        first.editSession.rename("a.txt", to: "first.txt")
        delegate.attach(full, model: second)
        let secondUndo = try #require(full.undoManager)
        #expect(secondUndo !== firstUndo && !secondUndo.canUndo)
        second.editSession.rename("a.txt", to: "second.txt")
        delegate.attach(glance, model: second)
        #expect(glance.undoManager === secondUndo)
        secondUndo.undo()
        #expect(second.editSession.operations.isEmpty)
        #expect(first.editSession.isEdited)
        delegate.attach(full, model: second)
        #expect(full.undoManager === secondUndo && secondUndo.canRedo)
        secondUndo.redo()
        #expect(second.editSession.pending.entries.contains { $0.path == "second.txt" })
        delegate.attach(full, model: first)
        #expect(full.undoManager === firstUndo && firstUndo.canUndo)
        firstUndo.undo()
        #expect(first.editSession.operations.isEmpty)
    }

    @Test func savingLocksNativeUndoWithoutDiscardingHistory() throws {
        let model = BrowserModel(archive: archive())
        let delegate = EditingWindowDelegate(), window = NSWindow()
        delegate.attach(window, model: model)
        let undo = try #require(window.undoManager)
        model.editSession.rename("a.txt", to: "b.txt")
        model.editSession.rename("b.txt", to: "c.txt")
        undo.undo()
        #expect(undo.canUndo && undo.canRedo)
        model.editSession.showSavingForDemo(progress: 0.5)
        #expect(!undo.canUndo && !undo.canRedo)
        undo.undo()
        undo.redo()
        #expect(model.editSession.operations.count == 1)
        // Unlock the test manager; a real save's defer ends the lock on either outcome.
        model.editingUndoManager.isLocked = { false }
        #expect(undo.canRedo)
        undo.redo()
        #expect(model.editSession.operations.count == 2)
    }
}
