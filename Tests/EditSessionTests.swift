import AppKit
import Foundation
import Testing
@testable import Stow

@MainActor
@Suite("Editing session")
struct EditSessionTests {
    private var base: ArchiveListing {
        ArchiveListing(type: "zip", entries: [
            ListedEntry(path: "a.txt", isFolder: false, size: 1),
            ListedEntry(path: "Folder", isFolder: true, size: 0),
            ListedEntry(path: "Folder/b.txt", isFolder: false, size: 1)
        ])
    }
    private func makeSession() -> EditSession { EditSession(base: base, url: nil, name: "Test.zip") }
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func mutationsAndExactUndoRedo() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "new.txt")
        try Data("replacement".utf8).write(to: source)
        let session = makeSession(), undo = UndoManager()
        undo.groupsByEvent = false
        session.undoManager = undo
        var operations: [[EditOperation]] = [[]]
        var listings: [[ListedEntry]] = [session.pending.entries]
        session.add([source], into: "Folder")
        operations.append(session.operations); listings.append(session.pending.entries)
        #expect(session.pending.entries.contains { $0.path == "Folder/new.txt" && $0.size == 11 })
        session.rename("Folder", to: "Renamed")
        operations.append(session.operations); listings.append(session.pending.entries)
        session.replace("a.txt", with: source)
        operations.append(session.operations); listings.append(session.pending.entries)
        #expect(session.pending.entries.first { $0.path == "a.txt" }?.size == 11)
        session.delete(["Renamed/b.txt"])
        operations.append(session.operations); listings.append(session.pending.entries)
        #expect(!session.pending.entries.contains { $0.path == "Renamed/b.txt" })
        for index in (0..<4).reversed() {
            undo.undo()
            #expect(session.operations == operations[index])
            #expect(session.pending.entries == listings[index])
        }
        for index in 1...4 {
            undo.redo()
            #expect(session.operations == operations[index])
            #expect(session.pending.entries == listings[index])
        }
        session.revert()
        #expect(session.operations.isEmpty)
        undo.undo()
        #expect(session.operations == operations[4])
    }

    @Test func deduplicatesAndValidatesNames() {
        let session = makeSession()
        session.add([URL(filePath: "/Stow-Sample/a.txt"), URL(filePath: "/Stow-Sample/a.txt")], into: "")
        #expect(Set(session.pending.entries.map(\.path)).isSuperset(of: ["a 2.txt", "a 3.txt"]))
        let operations = session.operations
        for name in ["", "a/b", ".", "..", "a 2.txt"] {
            session.rename("a.txt", to: name)
            #expect(session.message != nil)
            #expect(session.operations == operations)
            session.message = nil
        }
    }

    @Test func refusesUnknownEncodingWithVisibleReason() {
        var listing = base
        listing.entries[0].rawPath = Data([0xff])
        let session = EditSession(base: listing, url: nil, name: "Test.zip")
        #expect(session.refusal(for: ["a.txt"]) == EditSession.rawPathReason)
        session.delete(["a.txt"])
        #expect(session.message == EditSession.rawPathReason)
        session.message = nil
        session.rename("a.txt", to: "b.txt")
        #expect(session.message == EditSession.rawPathReason)
        #expect(session.operations.isEmpty)
    }

    @Test func detectsReadOnlyFormatsAndNestedArchives() {
        for (type, name) in [("Rar5", "a.rar"), ("gzip", "a.tar.gz"), ("zip", "a.zip.001"), ("xar", "a.pkg"), ("dmg", "a.dmg"), ("iso", "a.iso")] {
            let session = EditSession(base: ArchiveListing(type: type, entries: []), url: nil, name: name)
            #expect(session.format == nil)
            session.delete(["a"])
            #expect(session.showsReadOnly)
        }
        #expect(EditSession(base: base, url: nil, name: "a.zip", nested: true).format == nil)
    }

    @Test func mapsRenamedAncestorsAndFallsBackAfterDeletion() {
        let operations: [EditOperation] = [.rename(from: "Folder", to: "New"), .rename(from: "New/b.txt", to: "New/c.txt")]
        #expect(EditSession.map(path: "Folder/b.txt", through: operations) == "New/c.txt")
        #expect(EditSession.map(path: "Folder/Sub/file", through: operations) == "New/Sub/file")
        let pending = EditPlan.apply(operations + [.delete(paths: ["New/c.txt"])], to: base)
        #expect(EditSession.nearestExistingParent("New/c.txt", in: pending) == "New")
        #expect(EditSession.nearestExistingParent("Deleted/Sub/file", in: pending) == "")
    }

    @Test func addedFolderTreeSupportsFurtherEdits() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let folder = directory.appending(path: "New Folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: folder.appending(path: "child.txt"))
        let session = makeSession()
        session.add([folder], into: "")
        #expect(session.pending.entries.contains { $0.path == "New Folder" && $0.isFolder })
        session.rename("New Folder/child.txt", to: "renamed.txt")
        #expect(session.pending.entries.contains { $0.path == "New Folder/renamed.txt" })
        session.delete(["New Folder/renamed.txt"])
        #expect(!session.pending.entries.contains { $0.path.hasPrefix("New Folder/") })
        #expect(session.message == nil)
    }

    @Test func saveClearsUndoAndKeepsFolder() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Small.zip")
        try ZipFixture(entries: [.folder("Folder"), .file("Folder/a.txt", "hello")]).write(to: url)
        let listing = try await ArchiveEngine.shared.list(url)
        let model = BrowserModel(archive: Archive(listing: listing, url: url))
        let undo = UndoManager()
        undo.groupsByEvent = false
        model.editSession.undoManager = undo
        model.navigate(to: "Folder")
        model.editSession.rename("Folder", to: "Renamed")
        #expect(model.folder == "Renamed")
        #expect(undo.canUndo)
        #expect(await model.saveEdits())
        #expect(model.editSession.operations.isEmpty)
        #expect(model.editSession.pending.entries == model.editSession.base.entries)
        #expect(model.editSession.pending.physicalSize == model.editSession.base.physicalSize)
        #expect(!undo.canUndo && !undo.canRedo)
        #expect(model.folder == "Renamed")
    }

    @Test func savesAnAddedTreeWithRenamedAndDeletedChildren() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Tree.zip")
        try ZipFixture(entries: [.file("original.txt", "original")]).write(to: url)
        let tree = directory.appending(path: "Added")
        try FileManager.default.createDirectory(at: tree, withIntermediateDirectories: true)
        try Data("keep me".utf8).write(to: tree.appending(path: "keep.txt"))
        try Data("delete me".utf8).write(to: tree.appending(path: "delete.txt"))
        let listing = try await ArchiveEngine.shared.list(url)
        let session = EditSession(base: listing, url: url)
        session.add([tree], into: "")
        session.rename("Added/keep.txt", to: "renamed.txt")
        session.delete(["Added/delete.txt"])
        #expect(session.message == nil)
        #expect(await session.save(password: nil))
        let saved = try await ArchiveEngine.shared.list(url)
        #expect(saved.entries.contains { $0.path == "Added/renamed.txt" && $0.size == 7 })
        #expect(!saved.entries.contains { $0.path == "Added/delete.txt" || $0.path == "Added/keep.txt" })
    }

    @Test func externalChangeKeepsOperationsAndUndo() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Changed.zip")
        try ZipFixture(entries: [.file("a.txt", "original")]).write(to: url)
        let listing = try await ArchiveEngine.shared.list(url)
        let session = EditSession(base: listing, url: url)
        let undo = UndoManager()
        undo.groupsByEvent = false
        session.undoManager = undo
        session.rename("a.txt", to: "b.txt")
        let operations = session.operations, pending = session.pending.entries
        try ZipFixture(entries: [.file("a.txt", "external change")]).write(to: url)
        #expect(!(await session.save(password: nil)))
        #expect(session.message == String(localized: "The archive changed on disk. Close and reopen it before saving."))
        #expect(session.operations == operations)
        #expect(session.pending.entries == pending)
        #expect(undo.canUndo)
    }

    @Test func closeDecisions() {
        #expect(EditSession.canClose(.save, saved: true))
        #expect(!EditSession.canClose(.save, saved: false))
        #expect(EditSession.canClose(.discard, saved: false))
        #expect(!EditSession.canClose(.cancel, saved: true))
    }
}
