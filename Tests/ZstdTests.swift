import Foundation
import Testing
@testable import Stow

/// Stow's zstd writer for .tar.zst: levels, the pack plan, and streams the bundled 7zz can read back.
@Suite("Zstandard")
struct ZstdTests {
    @Test func namedLevelsMapToZstdLevels() {
        #expect(CompressionLevel.allCases.map(Zstd.level(for:)) == [1, 1, 2, 3, 12, 19])
        #expect(Zstd.isAvailable)
    }

    @Test func tarZstIsATarThenStowsOwnCompression() {
        var request = CreateRequest(operationID: "x", archiveName: "P", format: .tarZst)
        request.level = .smallest
        request.volumeSize = 1000
        let archive = URL(filePath: "/out/P.tar.zst")
        let steps = SevenZip.createSteps(for: request, archive: archive, input: URL(filePath: "/in"), work: URL(filePath: "/work"))
        #expect(steps.count == 2)
        #expect(steps[0].arguments[1] == "-ttar" && !steps[0].arguments.contains("-v1000b"))
        #expect(steps[0].intermediate == URL(filePath: "/work/P.tar") && steps[0].zstd == nil)
        #expect(steps[1].zstd == SevenZip.ZstdStep(source: URL(filePath: "/work/P.tar"), archive: archive,
                                                     level: 19, volumeSize: 1000))
    }

    @Test func formatsAndNames() {
        #expect(PackFormat.tarZst.fileExtension == "tar.zst" && PackFormat.tarZst.displayName == "TAR.ZST")
        #expect(PackFormat.tarZst.isCompressed && !PackFormat.tarZst.supportsPassword)
        #expect(Audience.linux.formats.contains(.tarZst) && !Audience.mac.formats.contains(.tarZst))
        #expect(ArchiveFormat.infer(fromName: "Logs.tar.zst") == .tarZst)
        #expect(ArchiveFormat.infer(fromName: "logs.TZST") == .tarZst)
        #expect(ArchiveFormat(sevenZipType: "zstd", name: "Logs.tar.zst") == .tarZst)
        #expect(ArchiveFormat(sevenZipType: "zstd", name: "dump.zst") == .other)
        #expect(ArchiveFormat.tarZst.badge == "TZST" && ArchiveFormat.tarZst.fileExtension == "tar.zst")
    }

    @Test @MainActor func packingTarZstSaysWhatOpensIt() {
        var options = PackOptions()
        options.setAudience(.linux)
        options.setFormat(.tarZst)
        let titles = Compatibility.report(for: [], options: options).notes.map(\.title)
        #expect(titles.contains("Needs a recent tar to open"))
        #expect(titles.contains("Keeps permissions and symlinks"))
        options.setFormat(.tarGz)
        #expect(!Compatibility.report(for: [], options: options).notes.map(\.title).contains("Needs a recent tar to open"))
    }
}

@Suite("Zstandard streams", .enabled(if: SevenZip.bundled() != nil, "7zz isn't bundled — run scripts/fetch-7zip.sh"))
struct ZstdStreamTests {
    private func noise(_ count: Int) -> Data {
        // Half random, half repeated: something to compress, and something that won't.
        var bytes = [UInt8](repeating: 0x41, count: count)
        for index in stride(from: 0, to: count, by: 2) { bytes[index] = UInt8.random(in: 0...255) }
        return Data(bytes)
    }

    @Test func sevenZipReadsWhatStowWrites() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let data = noise(3_000_000) // larger than one zstd input chunk
        let source = folder.url.appending(path: "dump.bin")
        try data.write(to: source)
        let archive = folder.url.appending(path: "dump.bin.zst")
        var fractions: [Double] = []
        try Zstd.compressNow(source, into: archive, level: 3, volumeSize: nil) { fractions.append($0) }
        #expect(fractions.last == 1 && fractions == fractions.sorted())
        let size = try #require(try archive.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        #expect(size < data.count)

        let sevenZip = try #require(SevenZip.bundled())
        let listing = try await sevenZip.list(archive)
        #expect(listing.type == "zstd")
        let back = folder.url.appending(path: "back", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: back, withIntermediateDirectories: false)
        _ = try await sevenZip.extract(archive, into: back) { _ in }
        #expect(try Data(contentsOf: back.appending(path: "dump.bin")) == data)
    }

    @Test func splitsIntoNumberedVolumes() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let data = noise(50_000)
        let source = folder.url.appending(path: "dump.bin")
        try data.write(to: source)
        let out = folder.url.appending(path: "out", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: false)
        try Zstd.compressNow(source, into: out.appending(path: "dump.bin.zst"), level: 1, volumeSize: 10_000)

        let names = TemporaryFolder.contents(of: out)
        #expect(names.count >= 3 && names.first == "dump.bin.zst.001")
        let sizes = try names.map { try #require(try out.appending(path: $0).resourceValues(forKeys: [.fileSizeKey]).fileSize) }
        #expect(sizes.dropLast().allSatisfy { $0 == 10_000 } && (sizes.last ?? 0) <= 10_000)

        let sevenZip = try #require(SevenZip.bundled())
        let back = folder.url.appending(path: "back", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: back, withIntermediateDirectories: false)
        _ = try await sevenZip.extract(out.appending(path: "dump.bin.zst.001"), into: back) { _ in }
        #expect(try Data(contentsOf: back.appending(path: "dump.bin")) == data)
    }

    @Test func cancellingRemovesWhatWasWritten() throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let source = folder.url.appending(path: "dump.bin")
        try noise(10_000).write(to: source)
        let out = folder.url.appending(path: "out", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: false)
        var checks = 0
        #expect(throws: EngineError(.cancelled)) {
            try Zstd.compressNow(source, into: out.appending(path: "dump.bin.zst"), level: 1, volumeSize: nil,
                                 cancelled: { checks += 1; return checks > 1 })
        }
        #expect(TemporaryFolder.contents(of: out).isEmpty)
    }
}
