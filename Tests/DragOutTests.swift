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
        #expect(model.dragOut.handle(event) == nil)
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
