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
        let delegate = EditingWindowDelegate()
        let window = NSWindow()
        delegate.attach(window, model: model)
        let undo = try #require(window.undoManager)
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
        #expect(window.representedURL == url)
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
        let model = BrowserModel(archive: Archive(listing: listing, url: url))
        let delegate = EditingWindowDelegate(), window = NSWindow()
        delegate.attach(window, model: model)
        let undo = try #require(window.undoManager)
        let session = model.editSession
        session.rename("a.txt", to: "b.txt")
        let operations = session.operations, pending = session.pending.entries
        try ZipFixture(entries: [.file("a.txt", "external change")]).write(to: url)
        #expect(!(await session.save(password: nil)))
        #expect(session.changedOnDisk)
        #expect(session.showsExternalChange)
        #expect(session.message == String(localized: "The archive changed on disk. Reload it or save a copy."))
        #expect(session.operations == operations)
        #expect(session.pending.entries == pending)
        #expect(undo.canUndo)
    }

    @Test func reloadDiscardsEditsAndLoadsNewContent() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Reload.zip")
        try ZipFixture(entries: [.file("a.txt", "original")]).write(to: url)
        let listing = try await ArchiveEngine.shared.list(url)
        let session = EditSession(base: listing, url: url)
        session.rename("a.txt", to: "b.txt")
        try ZipFixture(entries: [.file("a.txt", "external"), .file("c.txt", "new")]).write(to: url)
        #expect(!(await session.save(password: nil)))
        #expect(await session.reload(password: nil))
        #expect(!session.isEdited)
        #expect(!session.changedOnDisk)
        #expect(Set(session.pending.entries.map(\.path)) == ["a.txt", "c.txt"])
        #expect(session.pending.entries.contains { $0.path == "a.txt" && $0.size == 8 })
    }

    @Test func saveCopyLeavesOriginalByteIdentical() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Original.zip")
        try ZipFixture(entries: [.file("a.txt", "original")]).write(to: url)
        let listing = try await ArchiveEngine.shared.list(url)
        let model = BrowserModel(archive: Archive(listing: listing, url: url))
        let delegate = EditingWindowDelegate(), window = NSWindow()
        delegate.attach(window, model: model)
        let session = model.editSession
        session.rename("a.txt", to: "b.txt")
        try ZipFixture(entries: [.file("a.txt", "external change")]).write(to: url)
        let afterExternal = try Data(contentsOf: url)
        #expect(!(await session.save(password: nil)))
        let copy = directory.appending(path: "Copy.zip")
        #expect(await session.saveCopy(to: copy, password: nil))
        #expect(try Data(contentsOf: url) == afterExternal)
        let copied = try await ArchiveEngine.shared.list(copy)
        #expect(copied.entries.contains { $0.path == "b.txt" })
        #expect(!copied.entries.contains { $0.path == "a.txt" })
        #expect(window.representedURL == copy)
        #expect(session.url == copy)
        #expect(!session.isEdited)
        #expect(!session.changedOnDisk)
    }

    @Test func renameArchiveKeepsPendingEdits() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Harbor.zip")
        try ZipFixture(entries: [.file("Photos/a.txt", "a"), .file("Photos/b.txt", "b")]).write(to: url)
        let listing = try await ArchiveEngine.shared.list(url)
        let session = EditSession(base: listing, url: url)
        session.rename("Photos/a.txt", to: "renamed.txt")
        var adopted: URL?
        session.onURLChange = { adopted = $0 }
        #expect(await session.renameArchive(to: "Harbor Renamed.zip"))
        #expect(session.url?.lastPathComponent == "Harbor Renamed.zip")
        #expect(adopted?.lastPathComponent == "Harbor Renamed.zip")
        #expect(session.isEdited)
        #expect(session.pending.entries.contains { $0.path == "Photos/renamed.txt" })
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: "Harbor Renamed.zip").path))
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func renameArchivePreservesBrowserFolder() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Harbor.zip")
        try ZipFixture(entries: [.file("Photos/a.txt", "a"), .file("Photos/b.txt", "b")]).write(to: url)
        let listing = try await ArchiveEngine.shared.list(url)
        let model = BrowserModel(archive: Archive(listing: listing, url: url))
        let delegate = EditingWindowDelegate(), window = NSWindow()
        delegate.attach(window, model: model)
        model.folder = "Photos"
        model.selection = ["Photos/a.txt"]
        model.editSession.rename("Photos/b.txt", to: "Photos/pending.txt")
        #expect(await model.editSession.renameArchive(to: "Harbor Renamed.zip"))
        #expect(window.representedURL == directory.appending(path: "Harbor Renamed.zip"))
        #expect(model.editSession.isEdited)
        #expect(model.editSession.pending.entries.contains { $0.path == "Photos/pending.txt" })
        #expect(model.archive.name == "Harbor Renamed.zip")
        #expect(model.folder == "Photos")
        #expect(model.selection == ["Photos/a.txt"])
        #expect(model.archive.source?.url.lastPathComponent == "Harbor Renamed.zip")
    }

    @Test func makeStagingLeavesOriginalUntouched() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Local.zip")
        try Data("pk".utf8).write(to: url)
        let staging = try ArchiveSaver.makeStaging(for: url)
        defer { staging.cleanup() }
        #expect(!staging.file.path.isEmpty)
        #expect(try Data(contentsOf: url) == Data("pk".utf8))
    }

    @Test func closeDecisions() {
        #expect(EditSession.canClose(.save, saved: true))
        #expect(!EditSession.canClose(.save, saved: false))
        #expect(EditSession.canClose(.discard, saved: false))
        #expect(!EditSession.canClose(.cancel, saved: true))
    }
}
