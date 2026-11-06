import AppKit
import Testing
import UniformTypeIdentifiers
@testable import Stow

@MainActor
@Suite("Independent archive sessions", .serialized)
struct ArchiveWindowsTests {
    @Test func finderMultiOpenKeepsEveryArchiveAndDeduplicatesCanonicalPaths() async throws {
        let temp = try TemporaryFolder()
        defer { temp.cleanUp() }
        let a = temp.url.appending(path: "a.zip"), b = temp.url.appending(path: "b.zip")
        try ZipFixture(entries: [.file("a.txt", "a")]).write(to: a)
        try ZipFixture(entries: [.file("b.txt", "b")]).write(to: b)
        let app = AppState()
        app.presentsArchiveWindows = false
        app.glance.presentsWindow = false
        let store = try #require(UserDefaults(suiteName: UUID().uuidString))
        app.presentationDefaults = store
        app.receive([a, b, a])
        #expect(app.archiveSessions.count == 2)
        try await loaded(app)
        let second = try #require(app.additionalSessions.first)
        #expect(app.browser?.archive.name == "a.zip")
        #expect(second.browser?.archive.name == "b.zip")
        #expect(second.tray === app.tray && second.recents === app.recents)
        #expect(second.passwords !== app.passwords)
        #expect(second.browser?.editingUndoManager !== app.browser?.editingUndoManager)
        let alias = temp.url.appending(path: "alias.zip")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: a)
        #expect(app.sessionForOpening(alias) === app)
        second.mainWindowDidClose(.browser)
        #expect(second.browser == nil && app.browser?.archive.name == "a.zip")
        app.releaseFinishedWork()
        #expect(app.additionalSessions.isEmpty)
        app.mainWindowDidClose(.browser)
    }

    @Test func openingAnotherArchiveKeepsDirtySelectionAndUndoInTheOriginal() async throws {
        let app = AppState()
        app.presentsArchiveWindows = false
        app.openArchive(named: "First.zip")
        let first = try #require(app.browser)
        let path = try #require(first.archive.files.first?.path)
        first.select([path])
        first.editSession.delete([path])
        let other = app.sessionForOpening(URL(filePath: "/tmp/Second.zip"))
        other.openArchive(named: "Second.zip")
        #expect(app.browser === first && first.editSession.isEdited)
        #expect(!other.browser!.editSession.isEdited)
        #expect(other.browser!.editingUndoManager !== first.editingUndoManager)
        other.mainWindowDidClose(.browser)
        #expect(first.editSession.isEdited)
        first.editingUndoManager.undo()
        #expect(!first.editSession.isEdited)
    }

    @Test func focusAndGlanceOwnershipNeverIncludeAnotherArchiveWindow() throws {
        let app = AppState()
        app.presentsArchiveWindows = false
        app.openArchive(named: "First.zip")
        let second = app.sessionForOpening(URL(filePath: "/tmp/Second.zip"))
        second.openArchive(named: "Second.zip")
        let firstWindow = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        let secondWindow = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        app.archiveWindow = firstWindow
        second.archiveWindow = secondWindow
        #expect(app.session(owning: firstWindow) === app)
        #expect(app.session(owning: secondWindow) === second)
        #expect(app.glance.ownedMainWindows == [firstWindow])
        #expect(second.glance.ownedMainWindows == [secondWindow])
        #expect(app.session(owning: NSWindow()) == nil)
        second.glance.presentsWindow = false
        second.glance.closeMainWindow = { second.mainWindowDidClose(.browser) }
        second.glance.collapse(near: .zero, animated: false)
        #expect(second.browser != nil && app.browser != nil)
        #expect(second.glance.isShown && !app.glance.isShown)
    }

    @Test func passwordQuestionsAndBusyStateBelongToTheirSessions() async throws {
        let app = AppState()
        app.presentsArchiveWindows = false
        app.openArchive(named: "First.zip")
        let second = app.sessionForOpening(URL(filePath: "/tmp/Second.zip"))
        let q1 = PasswordPrompt.Question(archiveName: "a", purpose: .open, isRetry: false)
        let q2 = PasswordPrompt.Question(archiveName: "b", purpose: .open, isRetry: false)
        let a = Task { await app.passwords.ask(q1) }, b = Task { await second.passwords.ask(q2) }
        await Task.yield()
        #expect(app.passwords.question?.id == q1.id && second.passwords.question?.id == q2.id)
        app.passwords.answer("first", to: q1.id)
        #expect(second.passwords.question?.id == q2.id)
        #expect(app.isBusy && app.hasLifetimeWork)
        second.passwords.answer(nil, to: q2.id)
        #expect(await a.value == "first")
        #expect(await b.value == nil)
        #expect(!app.isBusy)
    }

    private func loaded(_ app: AppState) async throws {
        let deadline = ContinuousClock.now + .seconds(15)
        while app.archiveSessions.contains(where: \.isOpening), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(app.archiveSessions.allSatisfy { !$0.isOpening && $0.openFailure == nil })
    }
}

@MainActor
@Suite("Cross-archive copying", .serialized)
struct ArchiveTransferTests {
    @Test func copiesSelectionAsOneUndoableEditAndSavesExactBytes() async throws {
        let temp = try TemporaryFolder()
        defer { temp.cleanUp() }
        let source = try await model("source.zip", entries: [.file("Folder/a.txt", "alpha"), .file("b.txt", "beta")], in: temp.url)
        let target = try await model("target.zip", entries: [.file("Dest/keep.txt", "keep")], in: temp.url)
        let original = try Data(contentsOf: source.archive.source!.url)
        let transfer = ArchiveTransfer(source: source, entries: [try #require(source.archive.entry(at: "Folder")), try #require(source.archive.entry(at: "b.txt"))])
        try await transfer.copy(to: target, level: target.level, folder: "Dest") { _ in }
        #expect(target.editSession.operations.count == 1)
        #expect(target.archive.entry(at: "Dest/Folder/a.txt") != nil)
        #expect(target.archive.entry(at: "Dest/b.txt") != nil)
        let staged = try #require(target.editSession.source(for: "Dest/b.txt"))
        target.editingUndoManager.undo()
        #expect(!target.editSession.isEdited)
        #expect(FileManager.default.fileExists(atPath: staged.path))
        target.editingUndoManager.redo()
        #expect(target.archive.entry(at: "Dest/b.txt") != nil)
        #expect(await target.saveEdits())
        #expect(!FileManager.default.fileExists(atPath: staged.path))
        let saved = try await ArchiveEngine.shared.list(target.archive.source!.url)
        let reopened = Archive(listing: saved, url: target.archive.source!.url)
        let output = try await Extraction.stage(reopened, selection: nil, near: temp.url, skipSystemFiles: false) { _ in }
        defer { output.discard() }
        #expect(try String(contentsOf: output.root.appending(path: "Dest/Folder/a.txt"), encoding: .utf8) == "alpha")
        #expect(try String(contentsOf: output.root.appending(path: "Dest/b.txt"), encoding: .utf8) == "beta")
        #expect(try Data(contentsOf: source.archive.source!.url) == original)
    }

    @Test func copiesPendingRenamesAndAddedFilesWithoutSavingSource() async throws {
        let temp = try TemporaryFolder()
        defer { temp.cleanUp() }
        let source = try await model("source.zip", entries: [.file("old.txt", "original")], in: temp.url)
        let target = try await model("target.zip", entries: [.file("renamed.txt", "existing")], in: temp.url)
        let original = try Data(contentsOf: source.archive.source!.url)
        source.editSession.rename("old.txt", to: "renamed.txt")
        let extra = temp.url.appending(path: "extra.txt")
        try Data("new".utf8).write(to: extra)
        source.editSession.add([extra], into: "")
        let transfer = ArchiveTransfer(source: source, entries: source.archive.files)
        try await transfer.copy(to: target, level: target.level, folder: "") { _ in }
        #expect(source.editSession.operations.count == 2)
        #expect(try Data(contentsOf: source.archive.source!.url) == original)
        #expect(target.archive.entry(at: "renamed 2.txt") != nil)
        #expect(try String(contentsOf: #require(target.editSession.source(for: "renamed 2.txt")), encoding: .utf8) == "original")
        #expect(try String(contentsOf: #require(target.editSession.source(for: "extra.txt")), encoding: .utf8) == "new")
        target.editSession.discardChanges()
    }

    @Test func rejectsStaleSourceAndClosedDestinationWithoutMutatingEither() async throws {
        let temp = try TemporaryFolder()
        defer { temp.cleanUp() }
        let source = try await model("source.zip", entries: [.file("a.txt", "a")], in: temp.url)
        let target = try await model("target.zip", entries: [.file("b.txt", "b")], in: temp.url)
        let transfer = ArchiveTransfer(source: source, entries: source.archive.files)
        source.editSession.delete(["a.txt"])
        await #expect(throws: (any Error).self) {
            try await transfer.copy(to: target, level: target.level, folder: "") { _ in }
        }
        #expect(!target.editSession.isEdited)
        source.editingUndoManager.undo()
        let current = ArchiveTransfer(source: source, entries: source.archive.files)
        target.cancelTransfers()
        await #expect(throws: (any Error).self) {
            try await current.copy(to: target, level: target.level, folder: "") { _ in }
        }
        #expect(!target.editSession.isEdited)
    }

    @Test func privateTokenSurvivesNativePasteboardEncodingAndCancellationRevokesIt() throws {
        let declarations = try #require(Bundle.main.object(forInfoDictionaryKey: "UTExportedTypeDeclarations") as? [[String: Any]])
        #expect(declarations.contains { $0["UTTypeIdentifier"] as? String == ArchiveTransfer.typeIdentifier })
        let type = try #require(UTType(ArchiveTransfer.typeIdentifier), "SwiftUI must resolve the native drop type")
        #expect(type.conforms(to: .data))
        let source = BrowserModel(archive: Archive(name: "a.zip", format: .zip, files: [ArchiveEntry(path: "a.txt", isFolder: false, size: 1, packedSize: 1, modified: .now)]))
        let token = ArchiveTransfer.register(source: source, entries: source.archive.files)
        let provider = ArchiveDragPromise(fileType: "public.plain-text", delegate: source.dragOut)
        provider.transferToken = token
        provider.userInfo = "a.txt"
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        #expect(pasteboard.writeObjects([provider]))
        let bytes = try #require(pasteboard.data(forType: .init(ArchiveTransfer.typeIdentifier)))
        #expect(String(data: bytes, encoding: .utf8) == token)
        ArchiveTransfer.finish(token, cancelled: true)
        #expect(ArchiveTransfer.pending[token] == nil)
    }

    @Test func readOnlyAndSelfDropsDoNotStageAnything() async throws {
        let temp = try TemporaryFolder()
        defer { temp.cleanUp() }
        let source = try await model("source.zip", entries: [.file("a.txt", "a")], in: temp.url)
        let transfer = ArchiveTransfer(source: source, entries: source.archive.files)
        let readOnly = BrowserModel(archive: Archive(name: "read-only.rar", format: .rar, files: []))
        await #expect(throws: (any Error).self) {
            try await transfer.copy(to: readOnly, level: readOnly.level, folder: "") { _ in }
        }
        #expect(readOnly.editSession.showsReadOnly && !readOnly.editSession.isEdited)
        await #expect(throws: (any Error).self) {
            try await transfer.copy(to: source, level: source.level, folder: "") { _ in }
        }
        #expect(!source.editSession.isEdited)
    }

    @Test func nativeDragSurvivesProviderNormalizationButCannotLeakIntoAnotherGesture() throws {
        let source = BrowserModel(archive: Archive(name: "a.zip", format: .zip, files: []))
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        // SwiftUI normalizes a file promise to a file URL provider, dropping its extra UTI.
        // The source delegate's active native gesture is the trusted capability boundary.
        board.setString("file:///tmp/placeholder", forType: .fileURL)
        let first = ArchiveTransfer.register(source: source, entries: [])
        ArchiveTransfer.began(token: first, on: board)
        #expect(ArchiveTransfer.takeNativeDrop()?.source === source)
        #expect(ArchiveTransfer.takeNativeDrop() == nil, "Nested drop targets cannot consume a gesture twice")
        ArchiveTransfer.finish(first, cancelled: false)
        #expect(ArchiveTransfer.takeNativeDrop() == nil)

        let second = ArchiveTransfer.register(source: source, entries: [])
        ArchiveTransfer.began(token: second, on: board)
        board.clearContents()
        board.setString("file:///tmp/external", forType: .fileURL)
        #expect(ArchiveTransfer.takeNativeDrop() == nil, "A new external drag must not reuse the internal capability")
        ArchiveTransfer.finish(second, cancelled: true)
        #expect(ArchiveTransfer.pending[second] == nil)
    }

    @Test func externalSourceChangeIsRejectedEvenBeforeTheWatcherNotifies() async throws {
        let temp = try TemporaryFolder()
        defer { temp.cleanUp() }
        let source = try await model("source.zip", entries: [.file("a.txt", "a")], in: temp.url)
        let target = try await model("target.zip", entries: [.file("b.txt", "b")], in: temp.url)
        let transfer = ArchiveTransfer(source: source, entries: source.archive.files)
        try ZipFixture(entries: [.file("a.txt", "replaced externally")]).write(to: source.archive.source!.url)
        await #expect(throws: (any Error).self) {
            try await transfer.copy(to: target, level: target.level, folder: "") { _ in }
        }
        #expect(!target.editSession.isEdited)
    }

    @Test(arguments: [false, true])
    func encryptedSourceRequestsItsOwnPasswordAndCanCancel(cancel: Bool) async throws {
        let temp = try TemporaryFolder()
        defer { temp.cleanUp() }
        let files = temp.url.appending(path: "Files"), output = temp.url.appending(path: "Output")
        let work = temp.url.appending(path: "Work")
        for url in [files, output, work] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false) }
        try Data("encrypted bytes".utf8).write(to: files.appending(path: "secret.txt"))
        let engine = try #require(SevenZip.bundled())
        let request = CreateRequest(operationID: UUID().uuidString, archiveName: "Encrypted",
                                    format: .zip, password: "drag-secret", verify: true)
        _ = try await engine.create(request, from: files, into: output, work: work) { _ in }
        let url = output.appending(path: "Encrypted.zip")
        let source = BrowserModel(archive: Archive(listing: try await ArchiveEngine.shared.list(url), url: url))
        let target = try await model("target.zip", entries: [.file("b.txt", "b")], in: temp.url)
        let prompt = PasswordPrompt()
        source.passwords = PasswordHook(prompt: prompt)
        target.receiveTransfer(ArchiveTransfer(source: source, entries: source.archive.files), into: "", level: target.level)
        let deadline = ContinuousClock.now + .seconds(15)
        while prompt.question == nil, source.isTransferring, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let question = try #require(prompt.question)
        #expect(question.archiveName == "Encrypted.zip")
        if cancel { source.cancelTransfers() }
        else { prompt.answer("drag-secret", to: question.id) }
        while source.isTransferring, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!source.isTransferring && !target.isTransferring && prompt.question == nil)
        if cancel { #expect(!target.editSession.isEdited) }
        else {
            #expect(target.editSession.isEdited)
            #expect(try String(contentsOf: #require(target.editSession.source(for: "secret.txt")), encoding: .utf8) == "encrypted bytes")
            #expect(source.level.password == "drag-secret")
            target.editSession.discardChanges()
        }
    }

    private func model(_ name: String, entries: [ZipFixture.Entry], in folder: URL) async throws -> BrowserModel {
        let url = folder.appending(path: name)
        try ZipFixture(entries: entries).write(to: url)
        return BrowserModel(archive: Archive(listing: try await ArchiveEngine.shared.list(url), url: url))
    }
}
