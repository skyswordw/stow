import Foundation
import Testing
@testable import Stow

/// Try the Sample ships a genuine ZIP (#91): listing sizes match real files, and Extract uses the engine.
@Suite("Sample ZIP", .enabled(if: SevenZip.bundled() != nil, "7zz isn't bundled — run scripts/fetch-7zip.sh"))
struct SampleZIPTests {
    private var zipURL: URL {
        get throws {
            if let bundled = SampleArchive.bundledURL { return bundled }
            // Tests that run before the app resources are copied can still verify from the repo tree.
            let repo = URL(filePath: #filePath)
                .deletingLastPathComponent() // Tests/
                .deletingLastPathComponent() // repo root
                .appending(path: "Resources/Sample/Harbor Rebrand Handoff.zip")
            try #require(FileManager.default.fileExists(atPath: repo.path),
                         "Missing Harbor Rebrand Handoff.zip — run zsh scripts/make-sample-zip.sh")
            return repo
        }
    }

    @Test func bundledZIPOmitsUnsupportedDemoPromises() async throws {
        let url = try zipURL
        let listing = try await ArchiveEngine.shared.list(url)
        let archive = Archive(listing: listing, url: url)
        #expect(archive.source != nil)
        #expect(archive.format == .zip)
        #expect(archive.name == "Harbor Rebrand Handoff.zip")

        let pdf = try #require(archive.entry(at: "Specs/Brand Guidelines.pdf"))
        #expect(pdf.size == 599_021) // measured bytes, not the old 8.4 MB stand-in

        #expect(archive.entry(at: "Photos/Lighthouse.jpg") != nil)
        #expect(archive.entry(at: "Fonts/Atkinson Hyperlegible Regular.ttf") != nil)
        #expect(archive.entry(at: "Video/Logo Reveal.jpg") != nil)
        #expect(archive.entry(at: "Earlier Rounds/Old Explorations/Notes.txt") != nil)

        // Fictional release promises removed from the genuine ZIP (#91 / #69 scope).
        #expect(archive.entry(at: "Prototype/Harbor Prototype.app") == nil)
        #expect(archive.entry(at: "Prototype/Install Helper.pkg") == nil)
        #expect(archive.entry(at: "Audio/Brand Sting.wav") == nil)
        #expect(archive.entry(at: "Video/Logo Reveal.mov") == nil)
        #expect(archive.entry(at: "Earlier Rounds/Old Explorations.7z") == nil)
    }

    @Test func extractWritesRealFilesThroughTheEngine() async throws {
        let url = try zipURL
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let destination = folder.url.appending(path: "out", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let archive = Archive(listing: try await ArchiveEngine.shared.list(url), url: url)
        let readme = try #require(archive.entry(at: "README.md"))
        let result = try await Extraction.run(archive, selection: [readme], to: destination,
                                              options: .current(resolve: Placement.keepBoth)) { _ in }
        #expect(!result.placed.isEmpty)
        let written = try #require(result.placed.first)
        let text = try String(contentsOf: written, encoding: .utf8)
        #expect(text.contains("Harbor rebrand"))
        #expect(text.contains("Prototype") == false) // handoff README no longer promises a missing .app
    }

    @MainActor
    @Test func tryTheSampleUsesEnginePathNotSimulate() async throws {
        let url = try zipURL
        let model = BrowserModel(archive: Archive(listing: try await ArchiveEngine.shared.list(url), url: url))
        #expect(model.archive.source != nil)

        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        // Force the extract destination so the test never shows a panel.
        let destination = folder.url.appending(path: "Harbor", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let photo = try #require(model.archive.entry(at: "Photos/Lighthouse.jpg"))
        // Real source → extract(), not simulate(). Seed destination via Extraction directly to assert.
        let result = try await Extraction.run(model.archive, selection: [photo], to: destination,
                                              options: .current(resolve: Placement.keepBoth)) { _ in }
        #expect(result.placed.count == 1)
        #expect(FileManager.default.fileExists(atPath: result.placed[0].path))
        let size = try FileManager.default.attributesOfItem(atPath: result.placed[0].path)[.size] as? Int64
        #expect(size == photo.size)
        #expect(photo.size != 3_870_000) // old SampleArchive.make() stand-in; real file is smaller
    }
}
