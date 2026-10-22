import Foundation
import Testing
@testable import Stow

/// What the Quick Look panel is handed for each selected entry. Quick Look draws a zero-byte image
/// or text file as a blank page, so no item may ever point at an empty stand-in.
@Suite("Quick Look panel items")
struct QuickLookPanelTests {
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<800 where !condition() { try await Task.sleep(for: .milliseconds(25)) }
        #expect(condition())
    }

    private func contents(_ url: URL?) -> String {
        url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
    }

    @Test func sampleEntriesShowTheirBundledFiles() throws {
        let model = BrowserModel(archive: SampleArchive.make())
        let readme = try #require(model.archive.entry(at: "README.md"))
        model.select([readme.id])
        model.quickLook.reload()
        let item = try #require(model.quickLook.entries.first)
        #expect(item.url == SampleContent.previewFile(for: readme))
        #expect(item.url.map { FileManager.default.fileExists(atPath: $0.path) } == true)
        #expect(!item.isPending)
    }

    @Test func sampleEntryWithoutAFileGetsAStatusPage() throws {
        let model = BrowserModel(archive: SampleArchive.make())
        let sting = try #require(model.archive.entry(at: "Audio/Brand Sting.wav"))
        model.select([sting.id])
        model.quickLook.reload()
        let item = try #require(model.quickLook.entries.first)
        #expect(item.url?.pathExtension == "html")
        #expect(!item.isPending)
        let page = contents(item.url)
        #expect(page.contains("Brand Sting.wav"))
        #expect(page.contains(String(localized: "This sample file has no content to preview.")))
    }

    /// Space on Try the Sample used to only animate an "Opened" status: no panel at all.
    @Test func quickLookOnTheSampleOpensThePanel() throws {
        let model = BrowserModel(archive: SampleArchive.make())
        let photo = try #require(model.archive.entry(at: "Photos/Lighthouse.jpg"))
        model.select([photo.id])
        model.run(.quickLook)
        defer { model.quickLook.close() }
        #expect(model.activity == nil)
        #expect(model.quickLook.entries.map(\.entry.path) == ["Photos/Lighthouse.jpg"])
        #expect(model.quickLook.entries.first?.url == SampleContent.previewFile(for: photo))
    }

    @Test func realEntryShowsAStatusPageThenTheExtractedFile() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let zip = folder.url.appending(path: "notes.zip")
        try ZipFixture(entries: [.file("Notes/today.txt", "hello from the archive")]).write(to: zip)
        let model = BrowserModel(archive: Archive(listing: try await ArchiveEngine.shared.list(zip), url: zip))
        let entry = try #require(model.archive.entry(at: "Notes/today.txt"))
        model.select([entry.id])
        model.quickLook.reload()
        let item = try #require(model.quickLook.entries.first)
        if item.isPending {
            #expect(contents(item.url).contains("today.txt"))
        }
        try await waitUntil { !item.isPending }
        #expect(item.url?.lastPathComponent == "today.txt")
        #expect(contents(item.url) == "hello from the archive")
    }

    @Test func failedExtractionSaysWhyInsteadOfStayingBlank() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let zip = folder.url.appending(path: "gone.zip")
        try ZipFixture(entries: [.file("a.txt", "a")]).write(to: zip)
        let model = BrowserModel(archive: Archive(listing: try await ArchiveEngine.shared.list(zip), url: zip))
        try FileManager.default.removeItem(at: zip)
        let entry = try #require(model.archive.entry(at: "a.txt"))
        model.select([entry.id])
        model.quickLook.reload()
        let item = try #require(model.quickLook.entries.first)
        try await waitUntil { !item.isPending }
        #expect(item.url?.pathExtension == "html")
        let page = contents(item.url)
        #expect(page.contains("a.txt"))
        #expect(!page.contains(String(localized: "Extracting…")))
    }

    @Test func statusPageEscapesNames() {
        let page = QuickLookController.statusHTML(name: "<b>Q&A</b>.txt", detail: "Text · 1 KB", status: "Locked", iconPNG: Data([1, 2]))
        #expect(page.contains("&lt;b&gt;Q&amp;A&lt;/b&gt;.txt"))
        #expect(!page.contains("<b>Q&A</b>"))
        #expect(page.contains("data:image/png;base64,AQI="))
        #expect(page.contains("Locked"))
    }
}
