import Foundation
import Observation
import Synchronization
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
        // Four of 500 MB fill most of the 2 GB budget; a fifth doesn't fit, a small one still does.
        let size: Int64 = 500 * 1_024 * 1_024
        let rounds = (1...5).map { entry("r\($0).zip", size: size) }
        let picked = NestedSearch.within([big] + rounds + [entry("small.zip", size: 10)])
        #expect(picked.map(\.path) == ["r1.zip", "r2.zip", "r3.zip", "r4.zip", "small.zip"])
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
        #expect(nested.omissions.first?.reason == .passwordRequired)
        let hits = await nested.search("target", includingHelpers: false)
        #expect(hits.map(\.entry.path) == ["a.zip/deep/Target.txt"])
        #expect(await nested.search("notes", includingHelpers: false).isEmpty)
    }

    @Test(arguments: [false, true])
    func progressCompletionInvalidatesTheBrowserWithoutNewHits(fails: Bool) async throws {
        let archive = Archive(name: "outer.zip", format: .zip,
                              files: [entry("inner.zip"), entry("notes.txt")])
        let model = BrowserModel(archive: archive)
        var read: CheckedContinuation<[ArchiveEntry], any Error>?
        model.nestedLoader = { _, _ in
            try await withCheckedThrowingContinuation { read = $0 }
        }
        model.query = "notes"
        try await waitUntil { read != nil && model.visibleEntries.count == 1 }

        let invalidated = Mutex(false)
        let progress = withObservationTracking {
            model.indexingProgress
        } onChange: {
            invalidated.withLock { $0 = true }
        }
        #expect(progress != nil)
        #expect(model.searchCoverageSummary == nil)
        let pendingRead = try #require(read)
        if fails { pendingRead.resume(throwing: EngineError(.failed)) }
        else { pendingRead.resume(returning: []) }
        try await waitUntil { model.indexingProgress == nil }

        #expect(invalidated.withLock { $0 })
        #expect(model.visibleEntries.map(\.path) == ["notes.txt"])
    }

    @Test func omissionsDistinguishPasswordAndReadFailures() async {
        let archive = Archive(name: "outer.zip", format: .zip,
                              files: [entry("locked.zip"), entry("broken.zip"), entry("good.zip")])
        let nested = NestedSearch(archive: archive)
        await nested.load(in: archive, with: { container, _ in
            if container.name == "locked.zip" { throw EngineError(.passwordRequired) }
            if container.name == "broken.zip" { throw EngineError(.failed) }
            return []
        }, progress: {})
        #expect(nested.skipped == 2)
        #expect(nested.omissions.map(\.reason) == [.readFailure, .passwordRequired])
        #expect(nested.indexes.count == 1)
    }

    @Test func limitOmissionsRetainEveryAffectedArchive() {
        let size = NestedSearch.maxArchiveSize
        let files = [entry("a-big.zip", size: size + 1)]
            + (0..<5).map { entry("b\($0).zip", size: size) }
        let nested = NestedSearch(archive: Archive(name: "outer.zip", format: .zip, files: files))
        #expect(nested.omissions.map(\.reason) == [.archiveSizeLimit, .totalSizeLimit])
        let allLimited = NestedSearch(archive: Archive(name: "outer.zip", format: .zip, files: [files[0]]))
        #expect(!allLimited.isLoading)
        #expect(allLimited.skipped == 1)
        let many = (0..<42).map { entry(String(format: "a%02d.zip", $0)) }
        let limited = NestedSearch(archive: Archive(name: "outer.zip", format: .zip, files: many))
        #expect(limited.omissions.map(\.reason) == [.archiveCountLimit, .archiveCountLimit])
        #expect(limited.pending == 40)
    }

    @Test func cancellationDoesNotBecomeAReadFailure() async {
        let archive = Archive(name: "outer.zip", format: .zip, files: [entry("inner.zip")])
        let nested = NestedSearch(archive: archive)
        await nested.load(in: archive, with: { _, _ in throw CancellationError() }, progress: {})
        #expect(nested.skipped == 0)
        #expect(nested.indexes.isEmpty)
    }

    @Test(arguments: ["notes", "absent"])
    func browserDisclosesCoverageAndLocatesWithoutOpening(query: String) async throws {
        let archive = Archive(name: "outer.zip", format: .zip,
                              files: [entry("folder/locked.zip"), entry("broken.zip"), entry("notes.txt")])
        let model = BrowserModel(archive: archive)
        var reads = 0
        model.nestedLoader = { _, _ in
            reads += 1
            throw EngineError(.passwordRequired)
        }
        model.query = query
        try await waitUntil { model.searchOmissions.count == 2 && model.indexingProgress == nil }
        try await waitUntil { model.visibleEntries.count == (query == "notes" ? 1 : 0) }
        #expect(model.searchCoverageSummary != nil)
        #expect(reads == 2)
        let omission = try #require(model.searchOmissions.first { $0.container.path == "folder/locked.zip" })
        model.locateSearchOmission(omission)
        #expect(!model.isSearching)
        #expect(model.folder == "folder")
        #expect(model.selection == ["folder/locked.zip"])
        #expect(model.levels.count == 1)
        #expect(model.activity == nil)
        #expect(model.searchOmissions.isEmpty)
        #expect(model.searchCoverageSummary == nil)
        #expect(reads == 2)
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
