import Foundation
import Testing
@testable import Stow

@Suite("Split archive discovery")
struct SplitArchiveTests {
    @Test func discoversOnlyMatchingContiguousParts() throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        for name in ["a.7z.001", "a.7z.002", "other.7z.001", "a.7z.txt"] {
            try Data([1]).write(to: folder.url.appending(path: name))
        }
        let first = folder.url.appending(path: "a.7z.001")
        #expect(try SplitArchive.parts(for: first).map(\.lastPathComponent) == ["a.7z.001", "a.7z.002"])
        #expect(SplitArchive.baseName("a.zip.001") == "a.zip")
        #expect(SplitArchive.baseName("a.7z") == nil)
        #expect(SplitArchive.baseName("notes.001") == nil)
    }

    @Test func missingAndWrongNumberedPartsHaveRecovery() throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let first = folder.url.appending(path: "a.zip.001")
        try Data([1]).write(to: first)
        let third = folder.url.appending(path: "a.zip.003")
        try Data([3]).write(to: third)
        expectEngineFailure(.missingVolume) { try SplitArchive.parts(for: first) }
        expectEngineFailure(.missingVolume) { try SplitArchive.parts(for: third) }
        try FileManager.default.moveItem(at: third, to: folder.url.appending(path: "a.zip.0002"))
        expectEngineFailure(.missingVolume) { try SplitArchive.parts(for: first) }
    }

    @Test func rejectsSymlinkParts() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let target = folder.url.appending(path: "private.txt")
        try Data([1]).write(to: target)
        let link = folder.url.appending(path: "a.7z.001")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        await expectEngineFailure(.missingVolume) { _ = try await SplitArchive.open([link]) }
    }

    @Test func cancelledAssemblyLeavesNoNamedCopy() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let part = folder.url.appending(path: "a.7z.001")
        try Data([1]).write(to: part)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await SplitArchive.open([part])
        }
        await expectEngineFailure(.cancelled) { _ = try await task.value }
        #expect(TemporaryFolder.contents(of: folder.url) == ["a.7z.001"])
    }

    @Test func recoveryPreservesPasswordCancellationAndEngineErrors() {
        for failure in [EngineFailure.passwordRequired, .wrongPassword, .cancelled, .connectionLost] {
            #expect(SplitArchive.recover(EngineError(failure), name: "a.7z.001").failure == failure)
        }
        #expect(SplitArchive.recover(EngineError(.notAnArchive), name: "a.7z.001").failure == .missingVolume)
        #expect(SplitArchive.recover(EngineError(.notAnArchive), name: "a.7z").failure == .notAnArchive)
    }
}

@Suite("Split archive engine", .enabled(if: SevenZip.bundled() != nil, "7zz isn't bundled"))
@MainActor
struct SplitArchiveEngineTests {
    @Test(arguments: [PackFormat.zip, .sevenZip], [false, true])
    func reopensAndExtractsStowCreatedVolumes(format: PackFormat, encrypted: Bool) async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let input = folder.url.appending(path: "input")
        let output = folder.url.appending(path: "parts")
        let work = folder.url.appending(path: "work")
        for url in [input, output, work] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false) }
        let bytes = Data((0..<16_384).map { UInt8(truncatingIfNeeded: $0 * 37) })
        try bytes.write(to: input.appending(path: "payload.bin"))
        let password = encrypted ? "swordfish" : nil
        let sevenZip = SevenZip.bundled()!
        let report = try await sevenZip.create(CreateRequest(operationID: UUID().uuidString, archiveName: "small",
                                                              format: format, level: .store, password: password,
                                                              volumeSize: 1024),
                                                from: input, into: output, work: work) { _ in }
        try #require(report.files.count > 2)
        let first = output.appending(path: report.files[0])
        #expect(first.pathExtension == "001")
        if encrypted && format == .sevenZip {
            await expectEngineFailure(.passwordRequired) { _ = try await ArchiveEngine.shared.list(first) }
        }
        let listing = try await ArchiveEngine.shared.list(first, password: password)
        #expect(listing.type.lowercased() == (format == .zip ? "zip" : "7z"))
        #expect(listing.entries.map(\.path) == ["payload.bin"])
        if encrypted {
            #expect(listing.entries.allSatisfy { $0.isEncrypted })
            await expectEngineFailure(.passwordRequired) { try await ArchiveEngine.shared.verify(first) }
            await expectEngineFailure(.wrongPassword) { try await ArchiveEngine.shared.verify(first, password: "wrong") }
        }
        let extracted = try await ArchiveEngine.shared.extract(first, paths: [], password: password) { _ in }
        defer { ArchiveEngine.shared.discard(extracted) }
        let received = folder.url.appending(path: "received")
        try FileManager.default.createDirectory(at: received, withIntermediateDirectories: false)
        try await ArchiveEngine.shared.receive(extracted, into: received)
        #expect(try Data(contentsOf: received.appending(path: "payload.bin")) == bytes)
        // Missing tails must also report recovery, even without a numbering gap.
        let last = output.appending(path: report.files.last!)
        let tail = try Data(contentsOf: last)
        try FileManager.default.removeItem(at: last)
        await expectEngineFailure(.missingVolume) { try await ArchiveEngine.shared.verify(first, password: password) }
        try tail.write(to: last)
        // Removing an interior volume must fail before a format/password error can obscure it.
        try FileManager.default.removeItem(at: output.appending(path: report.files[1]))
        await expectEngineFailure(.missingVolume) { _ = try await ArchiveEngine.shared.list(first, password: password) }
    }
}
