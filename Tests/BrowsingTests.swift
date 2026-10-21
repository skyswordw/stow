import AppKit
import Foundation
import Synchronization
import Testing
@testable import Stow

private func entry(_ path: String, size: Int64 = 1, folder: Bool = false) -> ArchiveEntry {
    ArchiveEntry(path: path, isFolder: folder, size: size, packedSize: size, modified: Date(timeIntervalSince1970: 1_800_000_000))
}

private func archive(_ paths: [String], helpers: [String] = []) -> Archive {
    Archive(name: "t.zip", format: .zip, files: paths.map { entry($0, folder: $0.hasSuffix(".app")) },
            helpers: helpers.map { ArchiveEntry(path: $0, isFolder: false, size: 1, packedSize: 1, modified: .now, isHelper: true) })
}

@Suite("Archive index")
struct ArchiveIndexTests {
    @Test func childrenAreFoldersFirstInFinderOrder() {
        let archive = archive(["File 10.txt", "File 2.txt", "b/x.txt", "A/y.txt", "file 1.txt", "Écran.png"])
        #expect(archive.children(of: "").map(\.name) == ["A", "b", "Écran.png", "file 1.txt", "File 2.txt", "File 10.txt"])
        #expect(archive.entry(at: "b")?.isFolder == true)
        #expect(archive.entry(at: "b/x.txt")?.size == 1)
        #expect(archive.files.count == 6)
    }

    @Test func helperItemsAreHiddenUnlessAskedFor() {
        let archive = archive(["Docs/a.txt"], helpers: ["Docs/.DS_Store", "__MACOSX/Docs/._a.txt"])
        #expect(archive.children(of: "Docs").map(\.name) == ["a.txt"])
        #expect(archive.children(of: "Docs", includingHelpers: true).map(\.name) == [".DS_Store", "a.txt"])
        #expect(archive.children(of: "", includingHelpers: true).map(\.name) == ["__MACOSX", "Docs"])
        #expect(archive.entry(at: "__MACOSX/Docs")?.isHelper == true)
        #expect(archive.folderTree().map(\.name) == ["Docs"])
        #expect(archive.folderTree(includingHelpers: true).map(\.name) == ["__MACOSX", "Docs"])
        #expect(archive.files.count == 1 && archive.hasHelpers)
    }

    @Test func packagesAreFilesThatCanBeOpened() throws {
        let archive = archive(["Harbor.app", "Harbor.app/Contents/Info.plist", "Docs/a.txt"])
        let app = try #require(archive.entry(at: "Harbor.app"))
        #expect(app.isPackage && !app.isNavigable && app.kind == .app)
        #expect(archive.folderTree().map(\.name) == ["Docs"])
        // Packages sort among files, after real folders.
        #expect(archive.children(of: "").map(\.name) == ["Docs", "Harbor.app"])
    }

    @Test func searchMatchesNamesAndPathsNameMatchesFirst() {
        let archive = archive(["Handoff/notes.txt", "Docs/Handoff Notes.pdf", "Docs/Budget.csv", "Résumé.pdf"])
        #expect(archive.search("handoff").map(\.path) == ["Docs/Handoff Notes.pdf", "Handoff", "Handoff/notes.txt"])
        #expect(archive.search("docs/ budget").map(\.path) == ["Docs/Budget.csv"])
        #expect(archive.search("RESUME").map(\.path) == ["Résumé.pdf"])
        #expect(archive.search("   ").isEmpty)
    }

    @Test func searchIndexBuildsInChunksAndSearchesWhatsReady() async {
        let entries = (0..<10_000).map { entry("Folder \($0 / 100)/Item \($0).txt") }
        let index = SearchIndex(total: entries.count)
        let reports = Reports()
        await index.build(entries, chunk: 2_500) { count in reports.add(count) }
        #expect(reports.values == [2_500, 5_000, 7_500, 10_000])
        #expect(index.isComplete)
        let results = await index.search("folder 42/ item 4250", includingHelpers: false)
        #expect(results.map(\.path) == ["Folder 42/Item 4250.txt"])
    }

    @Test func sortKeysCompareLikeFinder() {
        #expect(SortKey("img2") < SortKey("img10"))
        #expect(SortKey("a") < SortKey("B"))
        #expect(SortKey("Écran") < SortKey("f"))
        #expect(!(SortKey("x") < SortKey("x")))
    }
}

@Suite("Legacy names")
struct LegacyNameTests {
    let gbk = NameEncoding.named("gbk")!
    let sjis = NameEncoding.named("sjis")!

    @Test func guessesTheEncodingThatReadsLikeNames() throws {
        let chinese = try #require("项目资料/会议记录.txt".data(using: gbk.encoding))
        let japanese = try #require("日本語のファイル.txt".data(using: sjis.encoding))
        #expect(NameEncoding.bestGuess(for: [chinese])?.id == "gbk")
        #expect(NameEncoding.bestGuess(for: [japanese])?.id == "sjis")
        // Automatic reads each name on its own, so archives mixing encodings still read.
        #expect(NameEncoding.decode(chinese, as: nil) == "项目资料/会议记录.txt")
        #expect(NameEncoding.decode(japanese, as: nil) == "日本語のファイル.txt")
        #expect(NameEncoding.decode(Data("plain é".utf8), as: nil) == "plain é")
    }

    @Test func readsAnArchiveWithoutTheUTF8FlagAndExtractsUnderTheShownNames() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let zip = folder.url.appending(path: "legacy.zip")
        try ZipFixture(entries: [
            .legacy("项目资料/会议记录.txt", encoding: gbk.encoding, "minutes"),
            .legacy("说明.txt", encoding: gbk.encoding, "readme"),
            .file("English.txt", "hi"),
        ]).write(to: zip)

        let listing = try await ArchiveEngine.shared.list(zip)
        #expect(listing.entries.filter { $0.rawPath != nil }.count == 2)
        let archive = Archive(listing: listing, url: zip)
        #expect(Set(archive.files.map(\.path)) == ["项目资料/会议记录.txt", "说明.txt", "English.txt"])
        #expect(archive.source?.legacyNames.count == 2)

        let destination = folder.url.appending(path: "Out", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        _ = try await Extraction.run(archive, selection: nil, to: destination) { _ in }
        #expect(TemporaryFolder.contents(of: destination.appending(path: "legacy"))
                == ["English.txt", "说明.txt", "项目资料", "项目资料/会议记录.txt"])
        let minutes = try String(contentsOf: destination.appending(path: "legacy/项目资料/会议记录.txt"), encoding: .utf8)
        #expect(minutes == "minutes")

        // Read another way: names change, extraction still finds the files.
        let big5 = Archive(listing: listing, url: zip, nameEncoding: NameEncoding.named("cp437"))
        #expect(big5.files.count == 3)
        #expect(!big5.files.map(\.path).contains("说明.txt"))
    }
}

@Suite("Preview cache", .enabled(if: SevenZip.bundled() != nil, "7zz isn't bundled — run scripts/fetch-7zip.sh"))
@MainActor
struct PreviewCacheTests {
    @Test func extractsOnceReadOnlyAndCleansUp() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let zip = folder.url.appending(path: "p.zip")
        try ZipFixture(entries: [.file("Docs/a.txt", "alpha"), .file("Docs/b.txt", "bravo"), .file("c.txt", "charlie")])
            .write(to: zip)
        let archive = Archive(listing: try await ArchiveEngine.shared.list(zip), url: zip)
        var cache: PreviewCache? = PreviewCache()
        let root = cache!.root

        let a = try await cache!.file(for: archive.entry(at: "Docs/a.txt")!, in: archive)
        #expect(try String(contentsOf: a, encoding: .utf8) == "alpha")
        #expect(a.lastPathComponent == "a.txt")
        #expect(!FileManager.default.isWritableFile(atPath: a.path))
        #expect(cache!.cachedFile(for: archive.entry(at: "Docs/a.txt")!, in: archive) == a)

        let batch = try await cache!.files(for: [archive.entry(at: "Docs/b.txt")!, archive.entry(at: "c.txt")!], in: archive)
        #expect(Set(batch.keys) == ["Docs/b.txt", "c.txt"])
        #expect(try String(contentsOf: batch["c.txt"]!, encoding: .utf8) == "charlie")

        cache = nil
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    @Test func staysWithinItsBudget() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let zip = folder.url.appending(path: "p.zip")
        let text = String(repeating: "x", count: 1_000)
        try ZipFixture(entries: (0..<5).map { .file("f\($0).txt", text) }).write(to: zip)
        let archive = Archive(listing: try await ArchiveEngine.shared.list(zip), url: zip)
        let cache = PreviewCache(budget: 2_500)

        var urls: [URL] = []
        for index in 0..<5 {
            urls.append(try await cache.file(for: archive.entry(at: "f\(index).txt")!, in: archive))
        }
        #expect(cache.usedBytes <= 2_500)
        #expect(!FileManager.default.fileExists(atPath: urls[0].path))
        #expect(FileManager.default.fileExists(atPath: urls[4].path))
    }

    @Test func aChangedArchiveIsNotServedFromTheCache() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let zip = folder.url.appending(path: "p.zip")
        try ZipFixture(entries: [.file("a.txt", "first")]).write(to: zip)
        let cache = PreviewCache()
        let first = Archive(listing: try await ArchiveEngine.shared.list(zip), url: zip)
        let key = cache.key(for: first.entry(at: "a.txt")!, in: first)

        try ZipFixture(entries: [.file("a.txt", "second, longer")]).write(to: zip)
        let second = Archive(listing: try await ArchiveEngine.shared.list(zip), url: zip)
        #expect(cache.key(for: second.entry(at: "a.txt")!, in: second) != key)
        let url = try await cache.file(for: second.entry(at: "a.txt")!, in: second)
        #expect(try String(contentsOf: url, encoding: .utf8) == "second, longer")
    }
}

@Suite("Browser navigation")
@MainActor
struct NavigationTests {
    @Test func backForwardAndUpSelectWhereYouCameFrom() {
        let model = BrowserModel(archive: archive(["A/B/c.txt", "A/d.txt", "e.txt"]))
        model.navigate(to: "A")
        model.navigate(to: "A/B")
        #expect(model.canGoBack && !model.canGoForward)
        model.goBack()
        #expect(model.folder == "A" && model.selection == ["A/B"])
        model.goBack()
        #expect(model.folder == "" && model.selection == ["A"] && !model.canGoBack)
        model.goForward()
        model.goForward()
        #expect(model.folder == "A/B")
        model.goUp()
        #expect(model.folder == "A" && model.selection == ["A/B"])
        #expect(model.pathSegments.map(\.title) == ["t.zip", "A"])
    }

    @Test func gridArrowsMoveByRowsAndShiftExtends() {
        let model = BrowserModel(archive: archive((0..<10).map { "f\($0).txt" }))
        model.gridColumns = 4
        model.move(.right)
        #expect(model.selection == ["f0.txt"])
        model.move(.down)
        #expect(model.selection == ["f4.txt"])
        model.move(.right, extending: true)
        model.move(.down, extending: true)
        #expect(model.selection == Set((4...9).map { "f\($0).txt" }))
        model.move(.down)
        #expect(model.selection == ["f9.txt"]) // clamps at the end
    }

    @Test func clicksFollowFinderModifiers() {
        let model = BrowserModel(archive: archive((0..<6).map { "f\($0).txt" }))
        let entries = model.visibleEntries
        model.click(entries[1], modifiers: [])
        model.click(entries[4], modifiers: .shift)
        #expect(model.selection == Set(entries[1...4].map(\.id)))
        model.click(entries[2], modifiers: .command)
        #expect(!model.selection.contains(entries[2].id) && model.selection.count == 3)
        model.marquee([entries[0].id], base: model.selection, toggling: true)
        #expect(model.selection.contains(entries[0].id) && model.selection.count == 4)
    }

    @Test func columnViewMovesIntoAndOutOfFolders() {
        let model = BrowserModel(archive: archive(["A/B/c.txt", "A/d.txt", "e.txt"]))
        model.viewMode = .columns
        model.columnSelect(model.archive.entry(at: "A")!)
        #expect(model.folder == "A" && model.selection == ["A"])
        model.move(.right)
        #expect(model.selection == ["A/B"] && model.folder == "A/B")
        model.move(.down)
        #expect(model.selection == ["A/d.txt"] && model.folder == "A")
        model.move(.left)
        #expect(model.selection == ["A"] && model.folder == "A")
    }

    @Test func typingSelectsByName() {
        let model = BrowserModel(archive: archive(["apple.txt", "banana.txt", "blueberry.txt"]))
        model.typeSelect("b")
        model.typeSelect("l")
        #expect(model.selection == ["blueberry.txt"])
    }

    @Test func gridMetricsFindTilesUnderTheMarquee() {
        let metrics = GridMetrics(width: 4 * 128 + 3 * GridMetrics.spacing + 2 * GridMetrics.inset)
        #expect(metrics.columns == 4)
        let second = metrics.frame(of: 5) // row 1, column 1
        #expect(metrics.indices(in: second.insetBy(dx: 10, dy: 10), count: 20) == [5])
        let span = metrics.frame(of: 0).union(metrics.frame(of: 5))
        #expect(metrics.indices(in: span, count: 20) == [0, 1, 4, 5])
    }
}

@Suite("Nested archives and drag-out", .enabled(if: SevenZip.bundled() != nil, "7zz isn't bundled — run scripts/fetch-7zip.sh"))
@MainActor
struct NestedTests {
    @Test func opensAnArchiveInsideAndComesBackOut() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let inner = folder.url.appending(path: "inner.zip")
        try ZipFixture(entries: [.file("Deep/secret.txt", "found it")]).write(to: inner)
        let outer = folder.url.appending(path: "outer.zip")
        try ZipFixture(entries: [ZipFixture.Entry(name: "Box/inner.zip", data: try Data(contentsOf: inner), mode: 0o100644),
                                 .file("top.txt", "t")]).write(to: outer)
        let model = BrowserModel(archive: Archive(listing: try await ArchiveEngine.shared.list(outer), url: outer))

        model.navigate(to: "Box")
        model.open(model.archive.entry(at: "Box/inner.zip")!)
        try await waitUntil { model.levels.count == 2 }
        #expect(model.archive.name == "inner.zip")
        #expect(model.pathSegments.map(\.title) == ["outer.zip", "Box", "inner.zip"])
        model.navigate(to: "Deep")
        let secret = try await model.previews.file(for: model.archive.entry(at: "Deep/secret.txt")!, in: model.archive)
        #expect(try String(contentsOf: secret, encoding: .utf8) == "found it")

        model.goUp()
        model.goUp()
        #expect(model.levels.count == 1 && model.folder == "Box" && model.selection == ["Box/inner.zip"])
        model.goBack()
        #expect(model.levels.count == 2 && model.folder == "" && model.archive.name == "inner.zip")
    }

    @Test func notAnArchiveInsideSaysSo() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let outer = folder.url.appending(path: "outer.zip")
        try ZipFixture(entries: [.file("fake.zip", "not a zip")]).write(to: outer)
        let model = BrowserModel(archive: Archive(listing: try await ArchiveEngine.shared.list(outer), url: outer))
        model.openInside(model.archive.entry(at: "fake.zip")!)
        try await waitUntil { if case .failed = model.activity?.phase { true } else { false } }
        #expect(model.levels.count == 1)
    }

    @Test func passwordHookIsAskedAndRetried() async throws {
        var asked: [(String, Bool)] = []
        let hook = PasswordHook { name, retry in
            asked.append((name, retry))
            return asked.count == 1 ? "wrong" : "right"
        }
        let (value, password) = try await hook.retrying("x.7z") { password -> String in
            switch password {
            case nil: throw EngineError(.passwordRequired)
            case "wrong": throw EngineError(.wrongPassword)
            default: return "opened"
            }
        }
        #expect(value == "opened" && password == "right")
        #expect(asked.map(\.1) == [false, true])
        await #expect(throws: EngineError(.passwordRequired)) {
            _ = try await PasswordHook.none.retrying("x.7z") { _ -> Int in throw EngineError(.passwordRequired) }
        }
    }

    @Test func aDroppedPromiseExtractsIntoTheDropFolder() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let zip = folder.url.appending(path: "d.zip")
        try ZipFixture(entries: [.file("Docs/report.txt", "dropped")]).write(to: zip)
        let model = BrowserModel(archive: Archive(listing: try await ArchiveEngine.shared.list(zip), url: zip))
        let drop = folder.url.appending(path: "Desktop", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: drop, withIntermediateDirectories: true)

        let provider = NSFilePromiseProvider(fileType: "public.plain-text", delegate: model.dragOut)
        provider.userInfo = "Docs/report.txt"
        #expect(model.dragOut.filePromiseProvider(provider, fileNameForType: "public.plain-text") == "report.txt")
        let error: (any Error)? = await withCheckedContinuation { continuation in
            model.dragOut.filePromiseProvider(provider, writePromiseTo: drop.appending(path: "report.txt")) {
                continuation.resume(returning: $0)
            }
        }
        #expect(error == nil)
        #expect(try String(contentsOf: drop.appending(path: "report.txt"), encoding: .utf8) == "dropped")
    }
}

@Suite("Big archives")
struct PerformanceTests {
    /// 100,000 entries in 500 folders: the shape of a big real archive. Times are printed for
    /// PARITY.md; the limits only catch regressions by an order of magnitude.
    @Test func hundredThousandEntriesStayFast() async {
        let clock = ContinuousClock()
        let listing = ArchiveListing(type: "zip", physicalSize: 1, entries: (0..<100_000).map {
            ListedEntry(path: "Folder \($0 / 200)/Item \($0 % 200).txt", isFolder: false, size: 10, packedSize: 10)
        })
        var archive: Archive!
        let build = clock.measure { archive = Archive(listing: listing, url: URL(filePath: "/tmp/big.zip")) }
        let firstChildren = clock.measure { _ = archive.children(of: "") }
        let folderChildren = clock.measure { _ = archive.children(of: "Folder 250") }
        let again = clock.measure { _ = archive.children(of: "") }
        let tree = clock.measure { _ = archive.folderTree() }
        let index = SearchIndex(total: archive.entries.count)
        let indexing = await clock.measure { await index.build(archive.entries) { _ in } }
        var hits = 0
        let search = await clock.measure { hits = await index.search("item 199.txt", includingHelpers: false).count }
        print("100k entries — model \(build), root children \(firstChildren), a folder \(folderChildren), "
              + "cached \(again), folder tree \(tree), search index \(indexing), search \(search) (\(hits) hits)")
        #expect(archive.entries.count == 100_500)
        #expect(hits == 500)
        #expect(build < .seconds(5) && again < .milliseconds(50) && search < .seconds(1))
    }
}

private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(20)
    while await !condition() {
        guard ContinuousClock.now < deadline else { throw EngineError(.failed, "timed out") }
        try await Task.sleep(for: .milliseconds(20))
    }
}

private nonisolated final class Reports: Sendable {
    private let storage = Mutex<[Int]>([])
    var values: [Int] { storage.withLock { $0 } }
    func add(_ value: Int) { storage.withLock { $0.append(value) } }
}

@Suite("Tarballs", .enabled(if: SevenZip.bundled() != nil, "7zz isn't bundled — run scripts/fetch-7zip.sh"))
@MainActor
struct TarballTests {
    /// .tar.gz and .tar.xz browse as the tar inside and extract from it, selection included.
    @Test(arguments: [("logs.tar.gz", "-czf"), ("logs.tar.xz", "-cJf"), ("logs.tbz2", "-cjf")])
    func browsesAndExtractsTheTarInside(name: String, flag: String) async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let source = folder.url.appending(path: "src")
        try FileManager.default.createDirectory(at: source.appending(path: "Docs"), withIntermediateDirectories: true)
        try Data("alpha".utf8).write(to: source.appending(path: "Docs/a.txt"))
        try Data("bravo".utf8).write(to: source.appending(path: "b.md"))
        let tarball = folder.url.appending(path: name)
        let tar = try Process.run(URL(filePath: "/usr/bin/tar"),
                                  arguments: ["--no-mac-metadata", flag, tarball.path, "-C", source.path, "Docs", "b.md"])
        tar.waitUntilExit()
        try #require(tar.terminationStatus == 0)

        let archive = Archive(listing: try await ArchiveEngine.shared.list(tarball), url: tarball)
        #expect(Set(archive.files.map(\.path)) == ["Docs/a.txt", "b.md"])

        let out = folder.url.appending(path: "Out", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let picked = try await Extraction.run(archive, selection: [archive.entry(at: "Docs/a.txt")!], to: out) { _ in }
        #expect(picked.placed.map(\.lastPathComponent) == ["a.txt"])
        #expect(try String(contentsOf: out.appending(path: "a.txt"), encoding: .utf8) == "alpha")

        let cache = PreviewCache()
        let preview = try await cache.file(for: archive.entry(at: "b.md")!, in: archive)
        #expect(try String(contentsOf: preview, encoding: .utf8) == "bravo")
    }

    @Test func aPlainGzipStaysOneFile() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let text = folder.url.appending(path: "notes.txt")
        try Data(String(repeating: "note ", count: 100).utf8).write(to: text)
        let gzip = try Process.run(URL(filePath: "/usr/bin/gzip"), arguments: ["-k", text.path])
        gzip.waitUntilExit()
        let listing = try await ArchiveEngine.shared.list(folder.url.appending(path: "notes.txt.gz"))
        #expect(listing.type == "gzip" && listing.entries.count == 1)
    }
}

@Suite("Fast listing")
struct FastListingTests {
    @Test func readsTheSameAsTheGeneralParser() throws {
        let fast = try #require(SevenZip.parseListingFast(ListingParserTests.output.replacingOccurrences(of: "Type = 7z", with: "Type = 7z")))
        let general = try #require(SevenZip.parseListing(ListingParserTests.output))
        #expect(fast.listing.entries == general.entries)
        #expect(fast.listing.type == general.type && fast.listing.physicalSize == general.physicalSize)
    }

    @Test func leavesOtherFormatsToTheGeneralParser() {
        let gzip = "--\nPath = a.gz\nType = gzip\n\n----------\nPath = a\nSize = 3\n\n"
        #expect(SevenZip.parseListingFast(gzip) == nil)
        #expect(SevenZip.parseListing(gzip)?.entries.count == 1)
    }

    @Test func flagsUnflaggedNonASCIIZipNames() throws {
        let zip = "--\nPath = a.zip\nType = zip\n\n----------\nPath = é.txt\nSize = 1\nCharacteristics = \n\n"
            + "Path = ü.txt\nSize = 1\nCharacteristics = UTF8\n\nPath = a.txt\nSize = 1\n\nPath = Icon\r\nSize = 0\n\n"
        let parsed = try #require(SevenZip.parseListingFast(zip))
        #expect(parsed.legacy == [0])
        #expect(parsed.listing.entries.map(\.path) == ["é.txt", "ü.txt", "a.txt", "Icon\r"])
    }
}
