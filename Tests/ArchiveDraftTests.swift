import Foundation
import Testing
@testable import Stow

@MainActor
@Suite("New archive drafts", .serialized)
struct ArchiveDraftTests {
    @Test func importsCollisionsAndUndoWithoutChangingSources() async throws {
        let temp = try TemporaryFolder()
        defer { temp.cleanUp() }
        let a = temp.url.appending(path: "A"), b = temp.url.appending(path: "B")
        for folder in [a,b] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(folder.lastPathComponent.utf8).write(to: folder.appending(path: "same.txt"))
        }
        let draft = ArchiveDraft()
        defer { draft.close() }
        await draft.add([a.appending(path: "same.txt"), b.appending(path: "same.txt")])
        #expect(draft.problem == nil && draft.files.count == 2)
        #expect(Set(draft.files.map(\.path)).count == 2)
        await draft.add([a.appending(path: "same.txt")])
        #expect(draft.files.count == 2, "Adding the same source twice is idempotent")
        draft.selection = [draft.files[0].path]
        draft.removeSelection()
        #expect(draft.files.count == 1)
        draft.undoManager.undo()
        #expect(draft.files.count == 2)
        draft.undoManager.redo()
        #expect(draft.files.count == 1)
        #expect(try String(contentsOf: a.appending(path: "same.txt"), encoding: .utf8) == "A")
        draft.prepareSave()
        #expect(draft.packRequest?.isSample == false)
        draft.packRequest = nil // Cancelling configuration preserves the draft.
        #expect(draft.files.count == 1 && draft.canSave)
    }

    @Test func missingSourceFailsAtomicallyAndCannotSilentlyDisappearOnSave() async throws {
        let temp = try TemporaryFolder()
        defer { temp.cleanUp() }
        let source = temp.url.appending(path: "real.txt")
        try Data("real".utf8).write(to: source)
        let draft = ArchiveDraft()
        defer { draft.close() }
        await draft.add([source])
        await draft.add([temp.url.appending(path: "missing.txt")])
        #expect(draft.files.count == 1 && draft.problem != nil)
        try FileManager.default.removeItem(at: source)
        draft.prepareSave()
        #expect(draft.packRequest == nil && draft.problem != nil)
        #expect(draft.files.count == 1)
    }

    @Test func removingAFolderRemovesItsSubtreeButUndoRetainsIt() async throws {
        let temp = try TemporaryFolder()
        defer { temp.cleanUp() }
        let nested = temp.url.appending(path: "Folder/Nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("contents".utf8).write(to: nested.appending(path: "a.txt"))
        let draft = ArchiveDraft()
        defer { draft.close() }
        await draft.add([temp.url.appending(path: "Folder")])
        draft.selection = ["Folder/Nested"]
        draft.removeSelection()
        #expect(draft.files.map(\.path) == ["Folder"])
        draft.undoManager.undo()
        #expect(draft.files.count == 3)
        draft.close()
        await draft.add([temp.url.appending(path: "Folder")])
        #expect(!draft.canSave, "A closed draft cannot receive late sources")
    }

    @Test func newCommandFocusesExistingDraftAndNeverReplacesAnEditedArchive() {
        let app = AppState()
        app.openArchive(named: "Existing.zip")
        let browser = app.browser
        var presentations = 0
        app.showCreationWindow = { presentations += 1 }
        app.beginNewArchive()
        let draft = app.archiveDraft
        app.beginNewArchive()
        #expect(app.archiveDraft === draft && presentations == 2)
        #expect(app.browser === browser)
        #expect(draft?.files.isEmpty == true && draft?.canSave == false)
        draft?.close()
    }
    @Test(.enabled(if: SevenZip.bundled() != nil))
    func draftCreatesARealArchiveWithOnlyTheRetainedContents() async throws {
        let temp = try TemporaryFolder()
        defer { temp.cleanUp() }
        let source = temp.url.appending(path: "input")
        let output = temp.url.appending(path: "output")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try Data("keep these exact bytes".utf8).write(to: source.appending(path: "keep.txt"))
        try Data("omit".utf8).write(to: source.appending(path: "omit.txt"))
        let draft = ArchiveDraft()
        defer { draft.close() }
        await draft.add([source])
        draft.selection = ["input/omit.txt"]
        draft.removeSelection()
        draft.prepareSave()
        let request = try #require(draft.packRequest)
        let report = Compatibility.report(for: request.files, options: PackOptions(), password: "", overrides: [:])
        let create = CreateRequest(operationID: UUID().uuidString, archiveName: "Draft", format: .zip,
                                   level: .balanced, password: nil, volumeSize: nil, keepsMacMetadata: false, verify: true)
        let result = try await ArchiveCreation.run(report.items, totalBytes: report.totalBytes, attributes: false,
                                                   request: create, named: "Draft", in: output, onProgress: { _ in })
        let url = try #require(result.placed.first)
        let listing = try await ArchiveEngine.shared.list(url)
        #expect(listing.entries.contains { $0.path == "input/keep.txt" && $0.size == 22 })
        #expect(!listing.entries.contains { $0.path == "input/omit.txt" })
        #expect(try Data(contentsOf: source.appending(path: "omit.txt")) == Data("omit".utf8))
        #expect(result.report.verified)
    }

}
