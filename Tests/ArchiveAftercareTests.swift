import Foundation
import Testing
@testable import Stow

@Suite("Archive cleanup after complete extraction")
@MainActor
struct ArchiveAftercareTests {
    @Test func selectedVolumeSetExcludesUnrelatedSiblings() throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        for name in ["a.zip.001", "a.zip.002", "a.zip.notes", "other.zip.001"] {
            try Data(name.utf8).write(to: folder.url.appending(path: name))
        }
        let source = try #require(ArchiveAftercare.Source.capture(folder.url.appending(path: "a.zip.001")))
        #expect(source.files.map { $0.url.lastPathComponent } == ["a.zip.001", "a.zip.002"])
        let trash = folder.url.appending(path: "trash", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: false)
        try ArchiveAftercare.moveToTrash(source, trash: { url in
            let target = trash.appending(path: url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: target)
            return target
        })
        #expect(FileManager.default.fileExists(atPath: folder.url.appending(path: "other.zip.001").path))
        #expect(FileManager.default.fileExists(atPath: folder.url.appending(path: "a.zip.notes").path))
        #expect(TemporaryFolder.contents(of: trash) == ["a.zip.001", "a.zip.002"])
    }

    @Test func missingMalformedAndUnsupportedVolumeSetsAreRetained() throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        for name in ["gap.7z.001", "gap.7z.003", "odd.7z.001", "odd.7z.0002", "movie.part1.rar", "legacy.rar", "legacy.r00"] {
            try Data([1]).write(to: folder.url.appending(path: name))
        }
        for name in ["gap.7z.001", "gap.7z.003", "odd.7z.001", "movie.part1.rar", "legacy.rar"] {
            #expect(ArchiveAftercare.Source.capture(folder.url.appending(path: name)) == nil)
        }
        let privateFile = folder.url.appending(path: "private.txt")
        try Data([1]).write(to: privateFile)
        let link = folder.url.appending(path: "link.zip.001")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: privateFile)
        #expect(ArchiveAftercare.Source.capture(link) == nil)
    }

    @Test func changedOrNewPartsPreventEveryTrashOperation() throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let first = folder.url.appending(path: "a.7z.001")
        try Data([1]).write(to: first)
        let source = try #require(ArchiveAftercare.Source.capture(first))
        try Data([2]).write(to: folder.url.appending(path: "a.7z.002"))
        var called = false
        #expect(throws: (any Error).self) {
            try ArchiveAftercare.moveToTrash(source, trash: { url in called = true; return url })
        }
        #expect(!called && FileManager.default.fileExists(atPath: first.path))
        let current = try #require(ArchiveAftercare.Source.capture(first))
        try Data([4, 5]).write(to: first)
        #expect(!current.isUnchanged)
        #expect(throws: (any Error).self) {
            try ArchiveAftercare.moveToTrash(current, trash: { url in called = true; return url })
        }
        #expect(!called)
    }

    @Test func failedTrashRollsEarlierVolumesBackWithoutClobbering() throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let first = folder.url.appending(path: "a.zip.001")
        let second = folder.url.appending(path: "a.zip.002")
        try Data([1]).write(to: first)
        try Data([2]).write(to: second)
        let source = try #require(ArchiveAftercare.Source.capture(first))
        let trashed = folder.url.appending(path: "moved-first")
        #expect(throws: (any Error).self) {
            try ArchiveAftercare.moveToTrash(source, trash: { url in
                if url == second { throw CocoaError(.fileWriteNoPermission) }
                try FileManager.default.moveItem(at: url, to: trashed)
                return trashed
            })
        }
        #expect(try Data(contentsOf: first) == Data([1]))
        #expect(try Data(contentsOf: second) == Data([2]))
        #expect(!FileManager.default.fileExists(atPath: trashed.path))
    }

    @Test func failedRollbackKeepsRecoverableTrashCopyAndReplacement() throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let first = folder.url.appending(path: "a.zip.001")
        let second = folder.url.appending(path: "a.zip.002")
        try Data([1]).write(to: first)
        try Data([2]).write(to: second)
        let source = try #require(ArchiveAftercare.Source.capture(first))
        let trashed = folder.url.appending(path: "moved-first")
        #expect(throws: (any Error).self) {
            try ArchiveAftercare.moveToTrash(source, trash: { url in
                if url == second {
                    try Data([9]).write(to: first)
                    throw CocoaError(.fileWriteNoPermission)
                }
                try FileManager.default.moveItem(at: url, to: trashed)
                return trashed
            })
        }
        #expect(try Data(contentsOf: first) == Data([9]))
        #expect(try Data(contentsOf: trashed) == Data([1]))
        #expect(try Data(contentsOf: second) == Data([2]))
    }

    @Test func incompletePlacementAndFilteredPayloadNeverPermitAftercare() {
        var result = Extraction.Result(placed: [], report: ExtractReport())
        #expect(result.isComplete)
        result.placement.skipped = 1
        #expect(!result.isComplete)
        result.placement.skipped = 0
        result.report.removedItems = ["unsafe"]
        #expect(!result.isComplete)
    }
}
