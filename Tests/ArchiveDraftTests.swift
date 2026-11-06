import Foundation
import Testing
@testable import Stow

@MainActor
@Suite("New archive drafts", .serialized)
struct ArchiveDraftTests {
    @Test func navigationAndSearchCannotDeleteHiddenSelections() async throws {
        let temp = try TemporaryFolder()
        defer { temp.cleanUp() }
        let folder = temp.url.appending(path: "Folder")
        let root = temp.url.appending(path: "root.txt")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("child".utf8).write(to: folder.appending(path: "child.txt"))
        try Data("root".utf8).write(to: root)
        let draft = ArchiveDraft()
        defer { draft.close() }
        await draft.add([folder, root])
        draft.selection = ["root.txt"]
        draft.browsing.go(to: "Folder")
        #expect(draft.selection.isEmpty)
        draft.removeSelection()
        #expect(draft.files.count == 3, "Delete must not act on an item hidden by navigation")
        draft.selection = ["Folder/child.txt"]
        draft.browsing.query = "root"
        #expect(draft.selection.isEmpty)
        draft.removeSelection()
        #expect(draft.files.count == 3)
        draft.browsing.query = "child"
        draft.browsing.go(to: "")
        draft.browsing.query = "child"
        draft.open(try #require(draft.browsing.nodes["Folder/child.txt"]))
        #expect(draft.browsing.folder == "Folder" && !draft.browsing.isSearching)
        #expect(draft.selection == ["Folder/child.txt"])
    }

    @Test func columnSelectionStaysVisibleButDoesNotLeakIntoList() {
        let draft = ArchiveDraft()
        defer { draft.close() }
        draft.browsing.update(tree: DraftNode.tree(from: [
            PackFile(path: "Folder", size: 0, isFolder: true),
            PackFile(path: "Folder/child.txt", size: 5)
        ]))
        draft.browsing.viewMode = .columns
        draft.selection = ["Folder"]
        draft.browsing.go(to: "Folder")
        #expect(draft.selection == ["Folder"], "The folder is still visible in the previous column")
        draft.browsing.viewMode = .list
        #expect(draft.selection.isEmpty)
        draft.browsing.go(to: "missing")
        #expect(draft.browsing.folder == "Folder")
    }

    @Test func gridAndColumnKeyboardNavigationUsesDisplayedItems() {
        let browsing = DraftBrowsing()
        browsing.update(tree: DraftNode.tree(from: [
            PackFile(path: "Folder", size: 0, isFolder: true),
            PackFile(path: "Folder/child.txt", size: 5),
            PackFile(path: "a.txt", size: 1), PackFile(path: "b.txt", size: 2)
        ]))
        browsing.viewMode = .grid
        browsing.gridColumns = 2
        var selection = browsing.move(.down, selection: [], extending: false)
        #expect(selection == ["Folder"])
        selection = browsing.move(.right, selection: selection, extending: true)
        #expect(selection == ["Folder", "a.txt"])
        selection = browsing.move(.down, selection: selection, extending: false)
        #expect(selection == ["b.txt"])
        browsing.viewMode = .columns
        selection = browsing.move(.right, selection: ["Folder"], extending: false)
        #expect(selection == ["Folder/child.txt"] && browsing.folder == "Folder")
        selection = browsing.move(.left, selection: selection, extending: false)
        #expect(selection == ["Folder"])
        selection = browsing.move(.down, selection: selection, extending: false)
        #expect(selection == ["a.txt"] && browsing.folder == "")
        browsing.query = "child"
        selection = browsing.move(.down, selection: [], extending: false)
        #expect(selection == ["Folder/child.txt"], "Columns search uses the result list")
    }

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

    @Test func discardingADraftClosesItsWindowBeforeRemovingTheSceneContent() throws {
        let app = AppState()
        app.beginNewArchive()
        let draft = try #require(app.archiveDraft)
        var closed = false
        app.closeCreationWindow = {
            #expect(app.archiveDraft === draft)
            #expect(draft.allowDiscardOrSave(), "An approved discard must not ask twice")
            closed = true
        }
        app.discardArchiveDraft()
        #expect(closed && app.archiveDraft == nil && !draft.canSave)
    }

    @Test(arguments: [false, true])
    func unsuccessfulSaveAndQuitDoesNotQuitAfterALaterSave(cancelled: Bool) async throws {
        let temp = try TemporaryFolder()
        defer { temp.cleanUp() }
        let source = temp.url.appending(path: "keep.txt")
        try Data("keep".utf8).write(to: source)
        let draft = ArchiveDraft()
        defer { draft.close() }
        await draft.add([source])
        draft.quitAfterSave = true
        draft.beganSaving()
        draft.finishedSaving(.failure(cancelled ? EngineError(.cancelled, "cancelled") : EngineError(.failed, "failed")))
        #expect(!draft.quitAfterSave && !draft.isSaving && draft.canSave)
        #expect(draft.files.count == 1)
        #expect((draft.problem == nil) == cancelled)
        draft.beganSaving()
        draft.finishedSaving(.success([temp.url.appending(path: "Archive.zip")]))
        #expect(!draft.quitAfterSave, "A later Save must return to the archive, not terminate Stow")
    }

    @Test func failedDraftPackCannotReplayAnOutdatedJobFromAnotherWindow() async throws {
        let temp = try TemporaryFolder()
        defer { temp.cleanUp() }
        let packing = PackController()
        let request = CreateRequest(operationID: UUID().uuidString, archiveName: "Draft", format: .zip,
                                    level: .balanced, password: nil, volumeSize: nil, keepsMacMetadata: false, verify: false)
        let result: Result<[URL], Error> = await withCheckedContinuation { continuation in
            packing.start(.init(items: [], totalBytes: 0, attributes: false, request: request,
                                name: "Draft", destination: temp.url.appending(path: "missing/output")),
                          allowsRetry: false) { continuation.resume(returning: $0) }
        }
        guard case .failure = result else {
            Issue.record("A missing destination must fail")
            return
        }
        #expect(packing.activity == nil, "The draft owns its error; other windows must not offer a stale retry")
        packing.follow(.tryAgain)
        #expect(!packing.isRunning)
    }


    /// Details and the Size column only ever describe the originals (#302): a folder's size is what's
    /// inside it, and its place in the archive follows the draft's name and format.
    @Test func detailsDescribeTheOriginalsBeforePacking() {
        let files = [
            PackFile(path: "Photos", size: 0, isFolder: true),
            PackFile(path: "Photos/a.jpg", size: 300),
            PackFile(path: "Photos/Raw", size: 0, isFolder: true),
            PackFile(path: "Photos/Raw/b.dng", size: 700),
            PackFile(path: "Notes.txt", size: 12),
        ]
        let tree = DraftNode.tree(from: files)
        #expect(tree.map(\.name) == ["Photos", "Notes.txt"])
        #expect(tree[0].bytes == 1000 && tree[0].count == 3)
        #expect(tree[1].bytes == 12)

        let inside = DraftDetails.contents(of: files[0], in: files)
        #expect(inside.items == 3 && inside.bytes == 1000)
        #expect(DraftDetails.contents(of: files[4], in: files).bytes == 12)

        let draft = ArchiveDraft()
        defer { draft.close() }
        draft.name = "Harbor Handoff"
        draft.format = .tarXz
        #expect(draft.fileName == "Harbor Handoff.tar.xz")
        #expect(DraftDetails.location(of: files[3], archiveName: draft.fileName) == "Harbor Handoff.tar.xz › Photos › Raw")
        #expect(DraftDetails.location(of: files[4], archiveName: draft.fileName) == "Harbor Handoff.tar.xz")
        draft.name = "  "
        #expect(draft.fileName == String(localized: "Untitled Archive") + ".tar.xz")
    }

    /// The draft's window gets the Browser's way around (#302): folders, history, Up, Search, and a
    /// removed folder falls back to the nearest one still planned.
    @Test func browsingFollowsFoldersHistoryAndSearch() {
        let files = [
            PackFile(path: "Photos", size: 0, isFolder: true),
            PackFile(path: "Photos/Raw", size: 0, isFolder: true),
            PackFile(path: "Photos/Raw/b.dng", size: 700),
            PackFile(path: "Notes.txt", size: 12),
        ]
        let browsing = DraftBrowsing()
        browsing.update(tree: DraftNode.tree(from: files))
        #expect(browsing.visible.map(\.name) == ["Photos", "Notes.txt"])
        browsing.open(browsing.nodes["Photos"]!)
        browsing.go(to: "Photos/Raw")
        #expect(browsing.visible.map(\.name) == ["b.dng"])
        #expect(browsing.segments.map(\.title) == ["Photos", "Raw"])
        browsing.goBack()
        #expect(browsing.folder == "Photos" && browsing.canGoForward)
        browsing.goForward()
        browsing.goUp()
        #expect(browsing.folder == "Photos")

        browsing.query = "dng"
        #expect(browsing.visible.map(\.id) == ["Photos/Raw/b.dng"])
        browsing.open(browsing.visible[0])
        #expect(browsing.folder == "Photos/Raw" && !browsing.isSearching)

        browsing.update(tree: DraftNode.tree(from: files.filter { !$0.path.hasPrefix("Photos") }))
        #expect(browsing.folder == "" && browsing.visible.map(\.name) == ["Notes.txt"])
    }
}
