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

        let excludedExtensions: Set<String> = ["app", "pkg", "mov", "wav", "7z"]
        for entry in listing.entries {
            for component in entry.path.split(separator: "/") {
                #expect(component.lowercased() != "prototype", "Unexpected sample path: \(entry.path)")
                let extensionName = (String(component) as NSString).pathExtension.lowercased()
                #expect(!excludedExtensions.contains(extensionName), "Unexpected sample path: \(entry.path)")
            }
        }
    }

    @Test func bundledZIPContainsRealHandoffPaths() async throws {
        let listing = try await ArchiveEngine.shared.list(zipURL)
        let expectedPaths = [
            "README.md",
            "Specs/Brand Guidelines.pdf",
            "Photos/Pier at Dawn.jpg",
            "Photos/Lighthouse.jpg",
            "Photos/Rope Detail.jpg",
            "Photos/Old Jetty.heic",
            "Photos/Harbor at Night.jpg",
            "Fonts/Atkinson Hyperlegible Regular.ttf",
            "Fonts/Atkinson Hyperlegible Bold.ttf",
            "Fonts/Instrument Serif Italic.ttf",
            "Screens/Home.png",
            "Screens/Checkout.png",
            "Screens/Onboarding 1.png",
            "Screens/Onboarding 2.png",
            "Screens/Onboarding 3.png",
            "Screens/Settings.png",
            "Screens/Dark/Home.png",
            "Screens/Dark/Checkout.png",
            "Logo/Harbor Mark.svg",
            "Logo/Harbor Wordmark.svg",
            "Logo/Harbor Mark@2x.png",
            "Video/Logo Reveal.jpg",
        ]
        for path in expectedPaths {
            let entry = try #require(listing.entries.first { $0.path == path }, "Missing sample file: \(path)")
            #expect(!entry.isFolder)
            #expect(!entry.isSymlink)
            #expect(entry.size > 0, "Empty sample file: \(path)")
        }
    }

    @Test func creditedTableFilesExistInBundledZIP() async throws {
        let url = try zipURL
        let creditsURL = url.deletingLastPathComponent().appending(path: "CREDITS.md")
        let credits = try String(contentsOf: creditsURL, encoding: .utf8)
        let listing = try await ArchiveEngine.shared.list(url)
        let filePaths = Set(listing.entries.filter { !$0.isFolder && !$0.isSymlink }.map(\.path))
        var creditedPaths: [String] = []
        for line in credits.split(whereSeparator: \.isNewline) {
            let row = line.trimmingCharacters(in: .whitespaces)
            guard row.hasPrefix("|") else { continue }
            let cells = row.split(separator: "|", omittingEmptySubsequences: false)
            guard cells.count > 2 else { continue }
            let fileCell = cells[1].trimmingCharacters(in: .whitespaces)
            guard fileCell.hasPrefix("`") else { continue }
            try #require(fileCell.hasSuffix("`"), "Malformed credits file cell: \(fileCell)")
            let path = String(fileCell.dropFirst().dropLast())
            creditedPaths.append(path)
            #expect(filePaths.contains(path), "Credited file missing from sample ZIP: \(path)")
        }
        #expect(creditedPaths.count >= 8, "Expected at least the five photo and three font credits")
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
