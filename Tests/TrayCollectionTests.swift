import Foundation
import Testing
@testable import Stow

@Suite("Tray collection transactions")
struct TrayCollectionTests {
    private func root() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "TrayCollection-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func successfulCollectionKeepsDuplicateNamesAndOriginalBytes() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let a = root.appending(path: "A"), b = root.appending(path: "B")
        for dir in [a, b] { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false) }
        let first = a.appending(path: "same.txt"), second = b.appending(path: "same.txt")
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)
        let made = try TrayCollection.copy([first, second], named: "Collected", into: root)
        let copies = try FileManager.default.contentsOfDirectory(at: made, includingPropertiesForKeys: nil)
        #expect(copies.count == 2)
        #expect(Set(try copies.map { try Data(contentsOf: $0) }) == [Data("first".utf8), Data("second".utf8)])
        #expect(try Data(contentsOf: first) == Data("first".utf8))
        #expect(try Data(contentsOf: second) == Data("second".utf8))
        #expect(try leftovers(in: root).isEmpty)
    }

    @Test func aLaterCopyFailurePublishesNothingAndCleansTheFirstCopy() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "first.txt")
        try Data("original".utf8).write(to: source)
        #expect(throws: (any Error).self) {
            try TrayCollection.copy([source, root.appending(path: "missing.txt")], named: "Collected", into: root)
        }
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "Collected").path))
        #expect(try leftovers(in: root).isEmpty)
        #expect(try Data(contentsOf: source) == Data("original".utf8))
    }

    @Test func committingNeverReplacesAnExistingDestination() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appending(path: "Collected"), source = root.appending(path: "source.txt")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        let sentinel = destination.appending(path: "keep.txt")
        try Data("keep".utf8).write(to: sentinel)
        try Data("source".utf8).write(to: source)
        #expect(throws: (any Error).self) { try TrayCollection.copy([source], named: "Collected", into: root) }
        #expect(try Data(contentsOf: sentinel) == Data("keep".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: destination.path) == ["keep.txt"])
        #expect(try leftovers(in: root).isEmpty)
    }

    @Test func aFolderCannotBeCollectedIntoItselfOrItsDescendant() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let child = root.appending(path: "Child")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: false)
        for parent in [root, child] {
            #expect(throws: TrayCollection.RecursiveDestination.self) {
                try TrayCollection.copy([root], named: "Collected", into: parent)
            }
            #expect(try leftovers(in: parent).isEmpty)
        }
    }

    private nonisolated final class RefusesCleanup: FileManager, @unchecked Sendable {
        override func removeItem(at URL: URL) throws { throw CocoaError(.fileWriteNoPermission) }
    }

    @Test func cleanupFailureReportsWhereThePartialCopiesRemain() throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "first.txt")
        try Data("copied".utf8).write(to: source)
        do {
            _ = try TrayCollection.copy([source, root.appending(path: "missing.txt")], named: "Collected",
                                        into: root, fileManager: RefusesCleanup())
            Issue.record("Expected both copy failure and refused cleanup")
        } catch let retained as TrayCollection.RetainedCopies {
            #expect(try Data(contentsOf: retained.folder.appending(path: "first.txt")) == Data("copied".utf8))
            #expect(!FileManager.default.fileExists(atPath: root.appending(path: "Collected").path))
        }
    }

    @Test @MainActor func failedCollectionKeepsTrayRowsAndSelection() async throws {
        let root = try root()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appending(path: "first.txt"), missing = root.appending(path: "missing.txt")
        try Data("first".utf8).write(to: first)
        let tray = TrayController()
        tray.add([first, missing])
        tray.selection = Set(tray.items.map(\.id))
        let selected = tray.selection, ids = tray.items.map(\.id)
        tray.beginCollecting(remembered: nil)
        tray.collectingName = "Collected"
        await tray.collectIntoFolder()
        #expect(tray.failure != nil && tray.collected == nil)
        #expect(tray.items.map(\.id) == ids && tray.selection == selected)
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "Collected").path))
        #expect(try leftovers(in: root).isEmpty)
    }

    private func leftovers(in root: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix(".stow-collect-") }
    }
}

@Suite("Tray Save To")
struct TrayExportTests {
    private func fixture() throws -> (root: URL, owned: URL, source: URL, destination: URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "TrayExport-\(UUID().uuidString)")
        let owned = root.appending(path: "Owned"), source = owned.appending(path: "Result")
        let destination = root.appending(path: "Destination")
        for folder in [source, destination] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        try Data("original".utf8).write(to: source.appending(path: "file.txt"))
        return (root, owned, source, destination)
    }

    @Test func exportNumbersConflictsWithoutChangingEitherOriginal() throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let existing = f.destination.appending(path: "Result")
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: false)
        try Data("keep".utf8).write(to: existing.appending(path: "keep.txt"))
        let saved = try TrayExport.copy(f.source, into: f.destination, ownedRoot: f.owned)
        #expect(saved.lastPathComponent == "Result 2")
        #expect(try Data(contentsOf: saved.appending(path: "file.txt")) == Data("original".utf8))
        #expect(try Data(contentsOf: f.source.appending(path: "file.txt")) == Data("original".utf8))
        #expect(try Data(contentsOf: existing.appending(path: "keep.txt")) == Data("keep".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.destination.path).sorted() == ["Result", "Result 2"])
    }

    @Test func cancellationAfterCopyPublishesNothingAndKeepsSource() throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        var checkpoints = 0
        #expect(throws: CancellationError.self) {
            try TrayExport.copy(f.source, into: f.destination, ownedRoot: f.owned, checkCancellation: {
                checkpoints += 1
                if checkpoints == 2 { throw CancellationError() }
            })
        }
        #expect(checkpoints == 2)
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.destination.path).isEmpty)
        #expect(try Data(contentsOf: f.source.appending(path: "file.txt")) == Data("original".utf8))
    }

    private nonisolated final class PartialCopyFailure: FileManager, @unchecked Sendable {
        override func copyItem(at source: URL, to destination: URL) throws {
            try super.copyItem(at: source, to: destination)
            throw CocoaError(.fileWriteOutOfSpace)
        }
    }

    @Test func failedCopyCleansPrivateOutputAndKeepsSource() throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        #expect(throws: (any Error).self) {
            try TrayExport.copy(f.source, into: f.destination, ownedRoot: f.owned, fileManager: PartialCopyFailure())
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.destination.path).isEmpty)
        #expect(try Data(contentsOf: f.source.appending(path: "file.txt")) == Data("original".utf8))
    }

    private nonisolated final class RacingWriter: FileManager, @unchecked Sendable {
        override func copyItem(at source: URL, to destination: URL) throws {
            try super.copyItem(at: source, to: destination)
            let collision = destination.deletingLastPathComponent().deletingLastPathComponent()
                .appending(path: source.lastPathComponent)
            try Data("another writer".utf8).write(to: collision)
        }
    }

    @Test func aDestinationCreatedDuringCopyIsPreserved() throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let saved = try TrayExport.copy(f.source, into: f.destination, ownedRoot: f.owned, fileManager: RacingWriter())
        #expect(saved.lastPathComponent == "Result 2")
        #expect(try Data(contentsOf: f.destination.appending(path: "Result")) == Data("another writer".utf8))
        #expect(try Data(contentsOf: saved.appending(path: "file.txt")) == Data("original".utf8))
    }

    private nonisolated final class RefusesExportCleanup: FileManager, @unchecked Sendable {
        override func removeItem(at URL: URL) throws { throw CocoaError(.fileWriteNoPermission) }
    }

    @Test func cancelledExportReportsRetainedStagingIfCleanupFails() throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        var checkpoints = 0
        do {
            _ = try TrayExport.copy(f.source, into: f.destination, ownedRoot: f.owned,
                                    fileManager: RefusesExportCleanup(), checkCancellation: {
                checkpoints += 1
                if checkpoints == 2 { throw CancellationError() }
            })
            Issue.record("Expected failed cleanup to retain its location")
        } catch let retained as TrayCollection.RetainedCopies {
            #expect(retained.copyError is CancellationError)
            #expect(FileManager.default.fileExists(atPath: retained.folder.appending(path: "Result/file.txt").path))
            #expect(!FileManager.default.fileExists(atPath: f.destination.appending(path: "Result").path))
            #expect(try Data(contentsOf: f.source.appending(path: "file.txt")) == Data("original".utf8))
        }
    }

    @Test func ownershipAndRecursiveDestinationsAreCheckedBeforeCopy() throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let link = f.owned.appending(path: "Link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: f.destination)
        for source in [f.owned, f.destination, link] {
            #expect(throws: (any Error).self) {
                try TrayExport.copy(source, into: f.destination, ownedRoot: f.owned)
            }
        }
        #expect(throws: TrayCollection.RecursiveDestination.self) {
            try TrayExport.copy(f.source, into: f.source, ownedRoot: f.owned)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.destination.path).isEmpty)
    }

    @Test @MainActor func pickerCancellationKeepsRowsAndSelection() async throws {
        let tray = TrayController(monitorsSystemEvents: false)
        let source = TrayTemporaryGroups.root().appending(path: "Unwritten-\(UUID().uuidString)")
        let item = TrayItem(name: "Result", size: 0, url: source, isFolder: true, isTemporaryGroup: true)
        tray.items = [item]
        tray.selection = [item.id]
        await tray.saveTemporaryResult(chooseDestination: { nil }, copy: { _, _ in
            Issue.record("Cancelling the picker must never start a copy")
            throw CancellationError()
        })
        #expect(tray.items == [item] && tray.selection == [item.id])
        #expect(!tray.isSavingTemporaryResult && tray.failure == nil)
    }

    @Test @MainActor func failedExportKeepsRowsAndDoesNotRememberDestination() async throws {
        let name = "TrayExportTests-\(UUID().uuidString)"
        let settings = try #require(UserDefaults(suiteName: name))
        defer { settings.removePersistentDomain(forName: name) }
        let tray = TrayController(settings: settings, monitorsSystemEvents: false)
        let source = TrayTemporaryGroups.root().appending(path: "Unwritten-\(UUID().uuidString)")
        let item = TrayItem(name: "Result", size: 0, url: source, isFolder: true, isTemporaryGroup: true)
        tray.items = [item]
        tray.selection = [item.id]
        await tray.saveTemporaryResult(chooseDestination: { FileManager.default.temporaryDirectory }, copy: { _, _ in
            throw CocoaError(.fileWriteOutOfSpace)
        })
        #expect(tray.items == [item] && tray.selection == [item.id])
        #expect(tray.failure != nil && !tray.isSavingTemporaryResult)
        #expect(settings.string(forKey: TrayExport.destinationKey) == nil)
    }

    @Test @MainActor func successfulExportReplacesOnlyTheTemporaryRowAndRemembersDestination() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let name = "TrayExportTests-\(UUID().uuidString)"
        let settings = try #require(UserDefaults(suiteName: name))
        defer { settings.removePersistentDomain(forName: name) }
        let tray = TrayController(settings: settings, monitorsSystemEvents: false)
        let source = TrayTemporaryGroups.root().appending(path: "Unwritten-\(UUID().uuidString)")
        let item = TrayItem(name: "Result", size: 0, url: source, isFolder: true, isTemporaryGroup: true)
        let unrelated = TrayItem(name: "Other", size: 0)
        tray.items = [item, unrelated]
        tray.selection = [item.id]
        await tray.saveTemporaryResult(chooseDestination: { f.destination }, copy: { _, _ in f.source })
        #expect(tray.items.count == 2 && tray.items[1] == unrelated)
        #expect(tray.items[0].url == f.source && !tray.items[0].isTemporaryGroup)
        #expect(tray.selection == [tray.items[0].id])
        #expect(settings.string(forKey: TrayExport.destinationKey) == f.destination.path)
        #expect(tray.failure == nil && !tray.isSavingTemporaryResult)
    }

    @Test @MainActor func saveToRejectsOrdinaryInputsAndMixedSelections() {
        let tray = TrayController(monitorsSystemEvents: false)
        let source = TrayTemporaryGroups.root().appending(path: "Unwritten-\(UUID().uuidString)")
        let item = TrayItem(name: "Result", size: 0, url: source, isFolder: true, isTemporaryGroup: true)
        let ordinary = TrayItem(url: FileManager.default.temporaryDirectory)
        tray.items = [item, ordinary]
        #expect(tray.temporaryResultToSave == nil)
        tray.selection = [ordinary.id]
        #expect(tray.temporaryResultToSave == nil)
        tray.selection = [item.id]
        #expect(tray.temporaryResultToSave == item)
    }

    @Test @MainActor func packSheetRunningJobAndRetryBlockExportOfTheirTemporarySource() async throws {
        let app = AppState()
        let tray = app.tray
        let source = TrayTemporaryGroups.root().appending(path: "Unwritten-\(UUID().uuidString)")
        let item = TrayItem(name: "Result", size: 0, url: source, isFolder: true, isTemporaryGroup: true)
        tray.items = [item]
        tray.selection = [item.id]
        var request = PackRequest(files: [PackFile(path: "Result", size: 0, isFolder: true, source: source)])
        request.cleanupDirectory = source
        request.cleanupOnlyOnSuccess = true
        app.packRequest = request
        #expect(tray.temporaryResultToSave == nil)
        await tray.saveTemporaryResult(chooseDestination: {
            Issue.record("Save To must not open a picker while Pack owns source cleanup")
            return nil
        })
        #expect(!tray.isSavingTemporaryResult && tray.items == [item])
        app.packRequest = nil
        app.packing.preview(name: "Result.zip", phase: .running(0.5))
        #expect(tray.temporaryResultToSave == nil)
        app.packing.preview(name: "Result.zip", phase: .failed(Failure("Failed", advice: "Retry")))
        #expect(tray.temporaryResultToSave == nil, "A retained Pack retry can still remove the source")
        app.packing.dismiss()
        #expect(tray.temporaryResultToSave == item)

        let other = AppState(workspaceOwner: app)
        app.additionalSessions.append(other)
        other.packRequest = request
        #expect(tray.temporaryResultToSave == nil, "Another archive window can own the packing request")
        other.packRequest = nil
        #expect(tray.temporaryResultToSave == item)
    }
}
