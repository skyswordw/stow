import Foundation
import Testing
@testable import Stow

private final class Zstd7zFixtureLocator: NSObject {}

/// Pins the known #316 limitation and safe failure through the real sandboxed engine.
/// These passing tests are NOT decoder-support acceptance. Replace the unsupported-method
/// expectation with exact payload checks when Zstd-in-7Z decoding is implemented.
@Suite("Zstd-in-7Z known compatibility gap", .serialized)
@MainActor
struct Zstd7zCompatibilityTests {
    @Test(arguments: ["plain.7z", "encrypted.7z", "delta-zstd.7z",
                      "split-zstd.7z.001", "encrypted-split-zstd.7z.001"])
    func unsupportedPayloadDoesNotPublishOrChangeSource(name: String) async throws {
        let fixtures = try #require(Bundle(for: Zstd7zFixtureLocator.self)
            .url(forResource: "Fixtures", withExtension: nil))
            .appending(path: "Zstd7z")
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let source = folder.url.appending(path: "Source")
        try FileManager.default.copyItem(at: fixtures, to: source)
        let archiveURL = source.appending(path: name)
        let original = try Data(contentsOf: archiveURL)
        let password: String? = name == "encrypted.7z" ? "stow-fixture-only"
            : name.hasPrefix("encrypted-split") ? "fixture-only" : nil
        let listing = try await ArchiveEngine.shared.list(archiveURL, password: password)
        #expect(listing.entries.contains { $0.path == "payload.txt" && $0.size == 20_000 })
        var archive = Archive(listing: listing, url: archiveURL)
        archive.source?.password = password
        for selected in [false, true] {
            let destination = folder.url.appending(path: UUID().uuidString)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
            let selection = selected ? archive.entries.filter { $0.path == "payload.txt" } : nil
            do {
                _ = try await Extraction.run(archive, selection: selection, to: destination) { _ in }
                Issue.record("Zstd decoder behavior changed: update #316 with exact-byte support acceptance")
            } catch {
                #expect(error.failure == .failed)
                #expect(error.message.contains("Unsupported Method"))
            }
            #expect(try FileManager.default.contentsOfDirectory(atPath: destination.path).isEmpty)
            #expect(try Data(contentsOf: archiveURL) == original)
        }
    }
}
