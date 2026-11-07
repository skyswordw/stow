import AppKit
import Testing
@testable import Stow

@MainActor
@Suite("Drag-out lifecycle", .serialized)
struct DragOutTests {
    @Test func restoresMultiSelectionAfterTableClearsOrNarrowsIt() async throws {
        let model = makeModel()
        model.select(["alpha.txt", "beta.txt"])
        #expect(model.dragOut.prepareDrag(from: "alpha.txt").map(\.path) == ["alpha.txt", "beta.txt"])
        model.selection = []
        await nextTurn()
        #expect(model.selection == ["alpha.txt", "beta.txt"])
        model.selection = ["alpha.txt"]
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        model.dragOut.finishDrag(pasteboard: pasteboard, operation: [])
        #expect(model.selection == ["alpha.txt", "beta.txt"])
        model.selection = []
        await nextTurn()
        #expect(model.selection == ["alpha.txt", "beta.txt"])
    }

    @Test func draggingAnUnselectedRowSelectsOnlyThatRow() async {
        let model = makeModel()
        model.select(["alpha.txt"])
        #expect(model.dragOut.prepareDrag(from: "beta.txt").map(\.path) == ["beta.txt"])
        model.selection = []
        await nextTurn()
        #expect(model.selection == ["beta.txt"])
    }

    @Test func cancelledDragClearsOnlyItsPasteboardAndResetsEventRouting() throws {
        let model = makeModel()
        let pasteboard = NSPasteboard.withUniqueName()
        let other = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally(); other.releaseGlobally() }
        let provider = NSFilePromiseProvider(fileType: "public.plain-text", delegate: model.dragOut)
        provider.userInfo = "alpha.txt"
        #expect(pasteboard.writeObjects([provider]))
        other.setString("untouched", forType: .string)
        _ = model.dragOut.prepareDrag(from: "alpha.txt")
        let event = try #require(NSEvent.mouseEvent(with: .leftMouseDragged, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1))
        #expect(model.dragOut.handle(event) === event)
        model.dragOut.finishDrag(pasteboard: pasteboard, operation: [])
        #expect(pasteboard.pasteboardItems?.isEmpty != false)
        #expect(other.string(forType: .string) == "untouched")
        #expect(model.dragOut.handle(event) === event)
    }

    @Test func successfulDropKeepsPromisesForAnAsynchronousReceiver() {
        let model = makeModel()
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let provider = NSFilePromiseProvider(fileType: "public.plain-text", delegate: model.dragOut)
        provider.userInfo = "alpha.txt"
        #expect(pasteboard.writeObjects([provider]))
        let changeCount = pasteboard.changeCount
        _ = model.dragOut.prepareDrag(from: "alpha.txt")
        model.dragOut.finishDrag(pasteboard: pasteboard, operation: .copy)
        #expect(pasteboard.changeCount == changeCount)
        #expect(pasteboard.pasteboardItems?.isEmpty == false)
    }

    @Test func aNewDragSupersedesQueuedRestoration() async {
        let model = makeModel()
        _ = model.dragOut.prepareDrag(from: "alpha.txt")
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        model.dragOut.finishDrag(pasteboard: pasteboard, operation: [])
        _ = model.dragOut.prepareDrag(from: "beta.txt")
        model.selection = []
        await nextTurn()
        #expect(model.selection == ["beta.txt"])
    }

    @Test func navigationDoesNotRestoreSelectionFromAnotherFolder() async {
        let model = makeModel()
        _ = model.dragOut.prepareDrag(from: "alpha.txt")
        model.navigate(to: "Docs")
        await nextTurn()
        #expect(model.selection.isEmpty)
    }

    @Test func finishedDragDoesNotOverrideLaterSelection() async {
        let model = makeModel()
        _ = model.dragOut.prepareDrag(from: "alpha.txt")
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        model.dragOut.finishDrag(pasteboard: pasteboard, operation: [])
        await nextTurn()
        model.select(["beta.txt"])
        await nextTurn()
        #expect(model.selection == ["beta.txt"])
    }

    @Test func retainedBrowserAndGlanceBothRouteDragEvents() throws {
        let model = sourceModel()
        let browser = NSWindow(), glance = NSWindow()
        model.dragOut.install(in: browser)
        model.dragOut.install(in: glance)
        // No reinstallation or new view attachment when either retained window returns.
        for window in [browser, glance, browser, glance] {
            model.dragOut.hovered = "alpha.txt"
            #expect(model.dragOut.dragCandidate(for: try mouse(.leftMouseDown, in: window)) == nil)
            #expect(model.dragOut.dragCandidate(for: try mouse(.leftMouseDragged, in: window, x: 2)) == nil)
            #expect(model.dragOut.dragCandidate(for: try mouse(.leftMouseDragged, in: window, x: 12)) == "alpha.txt")
            _ = model.dragOut.dragCandidate(for: try mouse(.leftMouseUp, in: window, x: 12))
            #expect(model.dragOut.dragCandidate(for: try mouse(.leftMouseDragged, in: window, x: 20)) == nil)
        }
    }

    @Test func anotherWindowCannotContinueOrReuseAPress() throws {
        let model = sourceModel()
        let browser = NSWindow(), glance = NSWindow(), other = NSWindow()
        model.dragOut.install(in: browser)
        model.dragOut.install(in: glance)
        model.dragOut.hovered = "alpha.txt"
        _ = model.dragOut.dragCandidate(for: try mouse(.leftMouseDown, in: browser))
        #expect(model.dragOut.dragCandidate(for: try mouse(.leftMouseDragged, in: glance, x: 12)) == nil)
        #expect(model.dragOut.dragCandidate(for: try mouse(.leftMouseDragged, in: other, x: 12)) == nil)
        _ = model.dragOut.dragCandidate(for: try mouse(.leftMouseDown, in: other))
        #expect(model.dragOut.dragCandidate(for: try mouse(.leftMouseDragged, in: browser, x: 12)) == nil)
    }

    @Test func reusedWindowOnlyRoutesToItsCurrentArchive() throws {
        let old = sourceModel(), current = sourceModel(), window = NSWindow()
        old.dragOut.install(in: window)
        old.dragOut.hovered = "alpha.txt"
        current.dragOut.install(in: window)
        current.dragOut.hovered = "alpha.txt"
        let down = try mouse(.leftMouseDown, in: window)
        let drag = try mouse(.leftMouseDragged, in: window, x: 12)
        _ = old.dragOut.dragCandidate(for: down)
        _ = current.dragOut.dragCandidate(for: down)
        #expect(old.dragOut.dragCandidate(for: drag) == nil)
        #expect(current.dragOut.dragCandidate(for: drag) == "alpha.txt")
    }

    @Test func renamingDoesNotStartAnArchiveDrag() throws {
        let model = sourceModel(), window = NSWindow()
        model.dragOut.install(in: window)
        model.dragOut.hovered = "alpha.txt"
        model.beginRename(try #require(model.archive.entry(at: "alpha.txt")))
        _ = model.dragOut.dragCandidate(for: try mouse(.leftMouseDown, in: window))
        #expect(model.dragOut.dragCandidate(for: try mouse(.leftMouseDragged, in: window, x: 12)) == nil)
    }

    private func sourceModel() -> BrowserModel {
        BrowserModel(archive: Archive(listing: ArchiveListing(type: "zip", entries: [
            ListedEntry(path: "alpha.txt", isFolder: false, size: 1)
        ]), url: URL(filePath: "/tmp/Drag-\(UUID().uuidString).zip")))
    }

    private func mouse(_ type: NSEvent.EventType, in window: NSWindow, x: CGFloat = 0, y: CGFloat = 0) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: y),
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1))
    }

    private func makeModel() -> BrowserModel {
        BrowserModel(archive: Archive(name: "Drag.zip", format: .zip, files:
            ["alpha.txt", "beta.txt", "Docs/note.txt"].map {
                ArchiveEntry(path: $0, isFolder: false, size: 1, packedSize: 1, modified: .now)
            }))
    }

    private func nextTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
