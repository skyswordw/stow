import Foundation
import Testing
@testable import Stow

/// Issue #21: search reaches one level into the archives inside the open one.
@MainActor
struct NestedSearchTests {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    private func entry(_ path: String, size: Int64 = 1, folder: Bool = false) -> ArchiveEntry {
        ArchiveEntry(path: path, isFolder: folder, size: size, packedSize: size, modified: date)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<400 where !condition() { try await Task.sleep(for: .milliseconds(25)) }
        try #require(condition())
    }

    @Test func hitShowsUnderItsArchive() {
        var helper = entry("__MACOSX/._a.png")
        helper.isHelper = true
        let hit = NestedHit(container: entry("Rounds/Old.7z"), inner: entry("Round 1/a.png"))
        #expect(hit.entry.path == "Rounds/Old.7z/Round 1/a.png")
        #expect(hit.entry.name == "a.png")
        #expect(hit.entry.parent == "Rounds/Old.7z/Round 1")
        #expect(hit.entry.kind == .image)
        #expect(NestedHit(container: entry("x.zip"), inner: helper).entry.isHelper)
    }

    @Test func limitsKeepSearchFromExtractingEverything() {
        let many = (0..<60).map { entry(String(format: "a%02d.zip", $0)) }
        #expect(NestedSearch.within(many).count == NestedSearch.maxArchives)
        let big = entry("big.zip", size: NestedSearch.maxArchiveSize + 1)
        let half = NestedSearch.maxTotalSize / 2
        let picked = NestedSearch.within([big, entry("b.zip", size: half), entry("c.zip", size: half), entry("d.zip", size: 10)])
        #expect(picked.map(\.path) == ["b.zip", "c.zip"])
        #expect(!picked.contains(big))
    }

    @Test func readsEachInnerArchiveOnceAndSkipsUnreadable() async {
        let archive = Archive(name: "outer.zip", format: .zip,
                              files: [entry("a.zip"), entry("locked.7z"), entry("notes.txt")])
        let nested = NestedSearch(archive: archive)
        #expect(nested.pending == 2)
        var reads: [String] = []
        await nested.load(in: archive, with: { container, _ in
            reads.append(container.path)
            guard container.path == "a.zip" else { throw EngineError(.wrongPassword) }
            return [ArchiveEntry(path: "deep/Target.txt", isFolder: false, size: 3, packedSize: 3, modified: .now)]
        }, progress: {})
        #expect(reads == ["a.zip", "locked.7z"])
        #expect(!nested.isLoading)
        #expect(nested.skipped == 1)
        let hits = await nested.search("target", includingHelpers: false)
        #expect(hits.map(\.entry.path) == ["a.zip/deep/Target.txt"])
        #expect(await nested.search("notes", includingHelpers: false).isEmpty)
    }

    @Test func resultsListInnerMatchesAfterTheOpenLevel() async throws {
        let model = BrowserModel(archive: SampleArchive.make())
        model.nestedLoader = { container, _ in
            guard container.name == "Old Explorations.7z" else { throw EngineError(.failed) }
            return [ArchiveEntry(path: "Round 2/Wordmark Draft.svg", isFolder: false, size: 9, packedSize: 9, modified: .now)]
        }
        model.query = "wordmark"
        let inner = "Earlier Rounds/Old Explorations.7z/Round 2/Wordmark Draft.svg"
        try await waitUntil { model.visibleEntries.contains { $0.id == inner } }
        #expect(model.visibleEntries.map(\.id) == ["Logo/Harbor Wordmark.svg", inner])
        #expect(model.nestedHits[inner]?.container.path == "Earlier Rounds/Old Explorations.7z")

        model.select([inner])
        #expect(model.selectedNestedHit?.inner.path == "Round 2/Wordmark Draft.svg")
        #expect(model.selectedEntries.isEmpty)
        // Nothing in this archive is selected, so Extract doesn't fall back to "everything".
        model.run(.extract)
        #expect(model.activity == nil)

        model.query = ""
        #expect(model.nestedHits.isEmpty)
    }
}

@Suite("Nested search, end to end", .enabled(if: SevenZip.bundled() != nil, "7zz isn't bundled — run scripts/fetch-7zip.sh"))
@MainActor
struct NestedSearchEngineTests {
    @Test func findsAFileInsideAnInnerZipAndOpensThere() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let innerZip = folder.url.appending(path: "inner.zip")
        try ZipFixture(entries: [.folder("deep"), .file("deep/target.txt", "found me"), .file("other.txt", "-")]).write(to: innerZip)
        let outerZip = folder.url.appending(path: "outer.zip")
        try ZipFixture(entries: [
            .file("target list.txt", "outer"),
            .init(name: "Archives/inner.zip", data: try Data(contentsOf: innerZip), mode: 0o100644),
        ]).write(to: outerZip)

        let archive = Archive(listing: try await ArchiveEngine.shared.list(outerZip), url: outerZip)
        let model = BrowserModel(archive: archive)
        model.query = "target"
        let id = "Archives/inner.zip/deep/target.txt"
        for _ in 0..<400 where model.nestedHits[id] == nil { try await Task.sleep(for: .milliseconds(25)) }
        try #require(model.nestedHits[id] != nil)
        #expect(model.visibleEntries.map(\.id) == ["target list.txt", id])

        model.open(try #require(model.visibleEntries.last))
        for _ in 0..<400 where model.levels.count < 2 { try await Task.sleep(for: .milliseconds(25)) }
        #expect(model.levels.count == 2)
        #expect(model.archive.name == "inner.zip")
        #expect(model.folder == "deep")
        #expect(model.selection == ["deep/target.txt"])
        #expect(!model.isSearching)
    }
}
