import Foundation
import Synchronization
import Testing
@testable import Stow

@Suite("Embedded ZIP compatibility", .enabled(if: SevenZip.bundled() != nil))
struct EmbeddedZipTests {
    let sevenZip = SevenZip.bundled()!
    // Beyond 7-Zip's default search window, with unrelated archive signatures in the wrapper.
    private var prefix: Data {
        Data([0, 0, 0, 32]) + Data("ftypisomRar!\u{1a}\u{7}\0".utf8) + Data(repeating: 0x31, count: 9 * 1024 * 1024)
    }
    private var suffix: Data { Data("Rar!\u{1a}\u{7}\0".utf8) + Data(repeating: 7, count: 15370) }

    @Test(arguments: [false, true], [false, true])
    func readsThroughFilesAndDescriptors(descriptor: Bool, streamed: Bool) async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let zip = folder.url.appending(path: "media.zip")
        let fixture = ZipFixture(entries: [.file("Docs/a.txt", "hello"), .file("b.txt", "world")],
                                 prefix: prefix, suffix: suffix, adjustOffsetsForPrefix: false)
        try fixture.write(to: zip)
        let original = try Data(contentsOf: zip)
        let failed = try await sevenZip.run(["l", "-slt", zip.path], input: nil, password: nil)
        #expect(SevenZip.shouldScanForZIP(failed))
        let handle = try FileHandle(forReadingFrom: zip)
        defer { try? handle.close() }
        let input: ArchiveInput = descriptor ? .descriptor(handle, name: "media.zip") : .file(zip)
        let received = Mutex<[String]>([])
        let listing = try await sevenZip.list(input, streamed: streamed) { entries in
            received.withLock { $0 += entries.map(\.path) }
        }
        #expect(listing.type == "zip")
        #expect(listing.startOffset == Int64(fixture.prefix.count))
        #expect(listing.tailSize == Int64(fixture.suffix.count))
        #expect(received.withLock { $0 } == ["Docs/a.txt", "b.txt"])
        #expect(Archive(listing: listing, url: zip).checkup.filter { $0.severity == .caution }.count == 2)
        #expect(EditableFormat(listing: listing, fileName: "media.zip") == nil)
        try await sevenZip.test(input) { _ in }
        try await sevenZip.test(input, type: "zip") { _ in }
        for selected in [[], ["Docs/a.txt"]] {
            let output = folder.url.appending(path: UUID().uuidString)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
            _ = try await sevenZip.extract(input, into: output, paths: selected) { _ in }
            #expect(try String(contentsOf: output.appending(path: "Docs/a.txt"), encoding: .utf8) == "hello")
            #expect(FileManager.default.fileExists(atPath: output.appending(path: "b.txt").path) == selected.isEmpty)
        }
        #expect(try Data(contentsOf: zip) == original)
    }

    @Test func streamsLargeListingOnceAndPreservesLegacyNames() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let zip = folder.url.appending(path: "names.zip")
        let entries = (0..<2100).map { ZipFixture.Entry.file("file-\($0).txt", "x") }
            + [.legacy("café.txt", encoding: .isoLatin1, "coffee")]
        try ZipFixture(entries: entries, prefix: prefix, adjustOffsetsForPrefix: false).write(to: zip)
        let chunks = Mutex<[[ListedEntry]]>([])
        let listing = try await sevenZip.list(.file(zip)) { entries in chunks.withLock { $0.append(entries) } }
        #expect(chunks.withLock { $0.count } >= 2)
        #expect(chunks.withLock { $0.flatMap { $0 }.map(\.path) } == listing.entries.map(\.path))
        #expect(listing.entries.last?.rawPath == "café.txt".data(using: .isoLatin1))
    }

    @Test func crcFailuresStayFailures() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let zip = folder.url.appending(path: "broken.zip")
        try ZipFixture(entries: [.file("a.txt", "unique payload")], prefix: prefix,
                       adjustOffsetsForPrefix: false).write(to: zip)
        var data = try Data(contentsOf: zip)
        let payload = try #require(data.range(of: Data("unique payload".utf8)))
        data[payload.lowerBound] ^= 1
        try data.write(to: zip)
        _ = try await sevenZip.list(zip)
        do {
            try await sevenZip.test(.file(zip)) { _ in }
            Issue.record("Corrupt ZIP passed integrity testing")
        } catch {
            #expect(error.failure == .failed)
            #expect(error.message.contains("CRC Failed"))
        }
    }

    @Test func encryptedEmbeddedZipKeepsPasswordErrors() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let plain = folder.url.appending(path: "a.txt")
        try Data("secret".utf8).write(to: plain)
        let zip = folder.url.appending(path: "encrypted.zip")
        let created = try await sevenZip.run(["a", "-tzip", "-mem=AES256", "-p", zip.path, plain.path],
                                             input: nil, password: "swordfish\nswordfish")
        try SevenZip.check(created)
        try (prefix + Data(contentsOf: zip) + suffix).write(to: zip)
        #expect(try await sevenZip.list(zip).entries.first?.isEncrypted == true)
        await #expect(throws: EngineError(.passwordRequired)) { try await sevenZip.test(.file(zip)) { _ in } }
        await #expect(throws: EngineError(.wrongPassword)) {
            try await sevenZip.test(.file(zip), password: "wrong") { _ in }
        }
        try await sevenZip.test(.file(zip), password: "swordfish") { _ in }
        let out = folder.url.appending(path: "out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: false)
        _ = try await sevenZip.extract(zip, into: out, password: "swordfish") { _ in }
        #expect(try String(contentsOf: out.appending(path: "a.txt"), encoding: .utf8) == "secret")
    }

    @Test func embeddedZipRetainsContainment() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let zip = folder.url.appending(path: "unsafe.zip")
        try ZipFixture(entries: [.file("../../outside.txt", "contained"), .symlink("link", to: "../../outside")],
                       prefix: prefix, adjustOffsetsForPrefix: false).write(to: zip)
        let out = folder.url.appending(path: "out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: false)
        let removed = try await sevenZip.extract(zip, into: out) { _ in }
        #expect(removed.map(\.path) == ["link"])
        #expect(TemporaryFolder.contents(of: out) == ["outside.txt"])
        #expect(!FileManager.default.fileExists(atPath: folder.url.appending(path: "outside.txt").path))
    }

    @Test func cancellationDuringFallbackListingStopsDelivery() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let zip = folder.url.appending(path: "cancel.zip")
        try ZipFixture(entries: (0..<5000).map { .file("\($0).txt", "x") }, prefix: prefix,
                       adjustOffsetsForPrefix: false).write(to: zip)
        let listingTask = Mutex<Task<ArchiveListing, any Error>?>(nil)
        let (chunks, continuation) = AsyncStream<Int>.makeStream()
        let task = Task {
            defer { continuation.finish() }
            return try await sevenZip.list(.file(zip)) { entries in
                continuation.yield(entries.count)
                listingTask.withLock { $0 }?.cancel()
            }
        }
        listingTask.withLock { $0 = task }
        defer { task.cancel() }
        var iterator = chunks.makeAsyncIterator()
        #expect(await iterator.next() == 2048)
        do {
            _ = try await task.value
            Issue.record("Cancelled embedded ZIP listing succeeded")
        } catch { #expect((error as? EngineError)?.failure == .cancelled) }
    }

}

@Suite("ZIP retry policy")
struct ZipRetryPolicyTests {
    @Test func retriesOnlyUnrecognizedInputs() {
        #expect(SevenZip.shouldScanForZIP(.init(status: 2, output: "", errors: "Is not archive")))
        for result in [
            SevenZip.RunResult(status: 0, output: "", errors: ""),
            .init(status: 2, output: "\nType = zip\n", errors: "Is not archive"),
            .init(status: 2, output: "", errors: "CRC Failed : a.txt"),
            .init(status: 2, output: "", errors: "Headers Error\nIs not archive"),
            .init(status: 2, output: "", errors: "Wrong password\nIs not archive"),
            .init(status: 2, output: "", errors: "Enter password\nIs not archive"),
            .init(status: 2, output: "", errors: "Missing volume\nIs not archive"),
        ] { #expect(!SevenZip.shouldScanForZIP(result)) }
    }
}

@MainActor
@Suite("Embedded ZIP through XPC", .enabled(if: SevenZip.bundled() != nil))
struct EmbeddedZipXPCTests {
    @Test func browseExtractVerifyAndRefuseEditing() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let zip = folder.url.appending(path: "embedded.zip")
        try ZipFixture(entries: [.file("a.txt", "hello")], prefix: Data(repeating: 0x31, count: 65536),
                       suffix: Data("Rar!\u{1a}\u{7}\0tail".utf8), adjustOffsetsForPrefix: false).write(to: zip)
        let original = try Data(contentsOf: zip)
        let listing = try await ArchiveEngine.shared.list(zip)
        #expect(listing.startOffset == 65536)
        let session = EditSession(base: listing, url: zip)
        #expect(session.format == nil)
        session.delete(["a.txt"])
        #expect(session.operations.isEmpty && session.showsReadOnly)
        try await ArchiveEngine.shared.verify(zip)
        let out = folder.url.appending(path: "out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: false)
        try await Extraction.run(Archive(listing: listing, url: zip), selection: nil, to: out) { _ in }
        #expect(try String(contentsOf: out.appending(path: "a.txt"), encoding: .utf8) == "hello")
        let request = EditRequest(operationID: UUID().uuidString, format: .zip, operations: [.delete(paths: ["a.txt"])])
        do {
            let report = try await ArchiveEngine.shared.edit(zip, items: [], request: request,
                                                             onSent: { _ in }, onProgress: { _ in })
            ArchiveEngine.shared.discard(operation: request.operationID)
            Issue.record("Engine allowed an embedded ZIP edit: \(report)")
        } catch { #expect(error.failure == .failed) }
        #expect(try Data(contentsOf: zip) == original)
    }

    @Test(arguments: [(Int64(42), Int64(0)), (0, 42), (42, 42)])
    func surroundingBytesMakeZipReadOnly(prefix: Int64, tail: Int64) {
        let listing = ArchiveListing(type: "zip", entries: [], startOffset: prefix, tailSize: tail)
        #expect(EditSession(base: listing, url: nil, name: "wrapped.zip").format == nil)
        #expect(EditableFormat(listing: listing, fileName: "wrapped.zip") == nil)
        #expect(EditableFormat(listing: ArchiveListing(type: "zip", entries: []), fileName: "plain.zip") == .zip)
    }
}
