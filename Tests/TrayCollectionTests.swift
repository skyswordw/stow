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
