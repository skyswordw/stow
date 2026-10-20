import Foundation
import Synchronization
import Testing
@testable import Stow

@Suite("Path containment")
struct PathContainmentTests {
    @Test(arguments: [
        ("Docs/a.txt", "Docs/a.txt"),
        ("../../evil.txt", "evil.txt"),
        ("/abs/evil.txt", "abs/evil.txt"),
        ("a/../../b.txt", "a/b.txt"),
        ("./c.txt", "c.txt"),
        ("d//e.txt", "d/e.txt"),
        ("..", "_"),
        ("foo/..", "foo/_"),
        ("", "_"),
    ])
    func containedPath(stored: String, expected: String) {
        #expect(PathContainment.containedPath(for: stored) == expected)
    }

    @Test func escapingNamesAreRecognised() {
        #expect(PathContainment.escapes("../x"))
        #expect(PathContainment.escapes("a/../../x"))
        #expect(PathContainment.escapes("/etc/passwd"))
        #expect(!PathContainment.escapes("a/..b/x"))
        #expect(!PathContainment.escapes("normal/file.txt"))
    }

    @Test(arguments: [
        ("Docs/link", "../../../etc/passwd", true),
        ("Docs/link", "/etc/passwd", true),
        ("Docs/link", "../README.md", false),
        ("Docs/link", "Sub/../a.txt", false),
        ("link", "..", true),
    ])
    func linkEscapes(link: String, target: String, escapes: Bool) {
        #expect(PathContainment.linkEscapes(linkPath: link, target: target) == escapes)
    }

    @Test func insideIsComponentWise() {
        #expect(PathContainment.isInside("/a/b/c", root: "/a/b"))
        #expect(PathContainment.isInside("/a/b", root: "/a/b"))
        #expect(!PathContainment.isInside("/a/bc", root: "/a/b"))
        #expect(!PathContainment.isInside("/a", root: "/a/b"))
    }

    @Test func auditRemovesLinksThatLeaveAndKeepsLinksThatStay() throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let root = folder.url
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: root.appending(path: "Docs/Sub"), withIntermediateDirectories: true)
        try Data("hi".utf8).write(to: root.appending(path: "Docs/a.txt"))
        try fileManager.createSymbolicLink(atPath: root.appending(path: "Docs/inside").path, withDestinationPath: "a.txt")
        try fileManager.createSymbolicLink(atPath: root.appending(path: "Docs/outside").path, withDestinationPath: "../../x")
        try fileManager.createSymbolicLink(atPath: root.appending(path: "Docs/absolute").path, withDestinationPath: "/etc/hosts")
        // A chain: each hop looks harmless lexically, but together they climb out.
        try fileManager.createSymbolicLink(atPath: root.appending(path: "Docs/Sub/up").path, withDestinationPath: "..")
        try fileManager.createSymbolicLink(atPath: root.appending(path: "chain").path, withDestinationPath: "Docs/Sub/up/../..")

        let audit = try PathContainment.audit(staging: root)

        #expect(Set(audit.removedLinks.map(\.path)) == ["Docs/outside", "Docs/absolute", "chain"])
        #expect(folder.contents() == ["Docs", "Docs/Sub", "Docs/Sub/up", "Docs/a.txt", "Docs/inside"])
    }

    @Test func auditClearsSetUserIDBits() throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let tool = folder.url.appending(path: "tool")
        try Data("#!/bin/sh".utf8).write(to: tool)
        try FileManager.default.setAttributes([.posixPermissions: 0o4755], ofItemAtPath: tool.path)

        _ = try PathContainment.audit(staging: folder.url)

        let mode = try FileManager.default.attributesOfItem(atPath: tool.path)[.posixPermissions] as? Int
        #expect(mode == 0o755)
    }
}

@Suite("Listing parser")
struct ListingParserTests {
    static let output = """
    7-Zip (z) 26.04 (arm64) : Copyright (c) 1999-2026 Igor Pavlov : 2026-10-05

    Scanning the drive for archives:
    1 file, 297 bytes (1 KiB)

    Listing archive: test.7z

    --
    Path = test.7z
    Type = 7z
    Physical Size = 297
    Solid = +

    ----------
    Path = Docs
    Size = 0
    Packed Size = 0
    Modified = 2026-10-20 00:13:47.2028110
    Attributes = D drwxr-xr-x
    Encrypted = -

    Path = Docs/Sub/zeros.bin
    Size = 50000
    Packed Size = 87
    Modified = 2026-10-20 00:13:47
    Attributes = A -rw-r--r--
    CRC = 16B7B325
    Encrypted = -

    Path = Docs/a = b.txt
    Size = 6
    Packed Size =
    Modified = 2026-10-20 00:13:47
    Attributes = A -rw-r--r--
    Encrypted = +

    Path = Docs/link
    Size = 19
    Packed Size =
    Attributes = A lrwxr-xr-x
    Encrypted = -

    """

    @Test func parsesArchiveAndEntries() throws {
        let listing = try #require(SevenZip.parseListing(Self.output))
        #expect(listing.type == "7z")
        #expect(listing.physicalSize == 297)
        #expect(listing.entries.map(\.path) == ["Docs", "Docs/Sub/zeros.bin", "Docs/a = b.txt", "Docs/link"])

        let folder = listing.entries[0], file = listing.entries[1], solid = listing.entries[2], link = listing.entries[3]
        #expect(folder.isFolder)
        #expect(file.size == 50_000 && file.packedSize == 87 && !file.isFolder)
        #expect(solid.packedSize == nil) // shares a solid block
        #expect(solid.isEncrypted)
        #expect(link.isSymlink && !link.isFolder)
        #expect(link.modified == nil)

        let date = try #require(file.modified)
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .second], from: date)
        #expect(parts.year == 2026 && parts.month == 10 && parts.day == 20 && parts.second == 47)
    }

    @Test func notAnArchiveHasNoListing() {
        #expect(SevenZip.parseListing("ERROR: x.txt : Cannot open the file as archive") == nil)
    }

    @Test func refusedLinksAreReadFromErrors() {
        let errors = "\nERROR: Dangerous link path was ignored : Docs/link : ../../../etc/passwd\n"
        #expect(SevenZip.refusedLinks(in: errors) == [RemovedLink(path: "Docs/link", target: "../../../etc/passwd")])
    }

    @Test func progressReadsBackspacedFragments() {
        let parser = ProgressParser()
        #expect(parser.consume(Data("  0M Scan\u{8}\u{8}\u{8}  0%\u{8}\u{8}\u{8}\u{8} 40% 3 - big.bin".utf8)) == 0)
        #expect(parser.consume(Data("\u{8}\u{8}100% 4\u{8}".utf8)) == 1)
        #expect(parser.consume(Data(" 90%\u{8}".utf8)) == nil) // never goes backwards
    }

    @Test func listingMapsIntoArchiveWithFoldersAndCheckup() {
        let listing = ArchiveListing(type: "zip", physicalSize: 100, entries: [
            ListedEntry(path: "Docs/", isFolder: true, size: 0, packedSize: 0),
            ListedEntry(path: "Docs/a.txt", isFolder: false, size: 10, packedSize: 5),
            ListedEntry(path: "Empty/", isFolder: true, size: 0, packedSize: 0),
            ListedEntry(path: "../../evil.txt", isFolder: false, size: 3, packedSize: 3),
            ListedEntry(path: "__MACOSX/Docs/._a.txt", isFolder: false, size: 4, packedSize: 4),
            ListedEntry(path: "Docs/.DS_Store", isFolder: false, size: 4, packedSize: 4),
        ])
        let archive = Archive(listing: listing, url: URL(filePath: "/tmp/x.zip"))

        #expect(archive.format == .zip)
        #expect(Set(archive.entries.map(\.path)) == ["Docs", "Docs/a.txt", "Empty", "evil.txt"])
        #expect(archive.entry(at: "Docs")?.size == 10)
        #expect(archive.totalSize == 13)
        #expect(archive.source?.storedPaths["evil.txt"] == ["../../evil.txt"])
        #expect(archive.storedPaths(for: [archive.entry(at: "Docs")!]) == ["Docs/", "Docs/a.txt"])

        let titles = archive.checkup.map(\.title)
        #expect(titles.contains("1 path tried to leave the folder"))
        #expect(titles.contains("2 macOS helper files hidden"))
        #expect(!archive.checkup.contains { $0.severity == .fine })
    }

    @Test(arguments: [("zip", "a.zip", ArchiveFormat.zip), ("7z", "a.7z", .sevenZip), ("gzip", "a.tar.gz", .tarGz),
                      ("gzip", "a.gz", .gzip), ("Rar5", "a.rar", .rar), ("Cab", "a.cab", .other)])
    func formatsFromSevenZipTypes(type: String, name: String, format: ArchiveFormat) {
        #expect(ArchiveFormat(sevenZipType: type, name: name) == format)
    }
}

/// These run the bundled `7zz` directly from the test host (the app), the way the engine does.
@Suite("7-Zip engine", .enabled(if: SevenZip.bundled() != nil, "7zz isn't bundled — run scripts/fetch-7zip.sh"))
struct SevenZipTests {
    let sevenZip = SevenZip.bundled()!

    @Test func listsRealZipWithSizes() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let zip = folder.url.appending(path: "plain.zip")
        try ZipFixture(entries: [
            .folder("Docs"),
            .file("Docs/a.txt", "hello"),
            .file("Docs/Sub/b.txt", String(repeating: "x", count: 1234)),
            .symlink("Docs/link", to: "a.txt"),
        ]).write(to: zip)

        let listing = try await sevenZip.list(zip)

        #expect(listing.type == "zip")
        let byPath = Dictionary(uniqueKeysWithValues: listing.entries.map { ($0.path, $0) })
        #expect(byPath["Docs/a.txt"]?.size == 5)
        #expect(byPath["Docs/Sub/b.txt"]?.size == 1234)
        #expect(byPath["Docs"]?.isFolder == true)
        #expect(byPath["Docs/link"]?.isSymlink == true)
    }

    /// Pins `PathContainment.containedPath` to what this 7-Zip build actually writes.
    @Test func containedPathsMatchWhatSevenZipWrites() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let names = ["a/../../b1.txt", "./c.txt", "d//e.txt", "x/./y.txt", "../../evil.txt", "/abs/evil2.txt", "foo/.."]
        let zip = folder.url.appending(path: "tricky.zip")
        try ZipFixture(entries: names.map { .file($0, "1") }).write(to: zip)
        let out = folder.url.appending(path: "out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: false)

        _ = try await sevenZip.extract(zip, into: out) { _ in }

        for name in names {
            let expected = out.appending(path: PathContainment.containedPath(for: name))
            #expect(FileManager.default.fileExists(atPath: expected.path), "\(name)")
        }
    }

    @Test func zipSlipIsContainedAndReported() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let zip = folder.url.appending(path: "slip.zip")
        try ZipFixture(entries: [
            .file("ok.txt", "fine"),
            .file("../../evil.txt", "bad"),
            .file("/tmp/stow-absolute-evil.txt", "bad"),
            .symlink("passwd", to: "../../../../etc/passwd"),
        ]).write(to: zip)
        let out = folder.url.appending(path: "out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: false)

        let listing = try await sevenZip.list(zip)
        let archive = Archive(listing: listing, url: zip)
        #expect(archive.checkup.contains { $0.severity == .handled && $0.title == "2 paths tried to leave the folder" })

        let refused = try await sevenZip.extract(zip, into: out) { _ in }
        let audit = try PathContainment.audit(staging: out)

        #expect((refused + audit.removedLinks).map(\.path) == ["passwd"])
        let contents = TemporaryFolder.contents(of: out)
        #expect(contents == ["evil.txt", "ok.txt", "tmp", "tmp/stow-absolute-evil.txt"])
        #expect(TemporaryFolder.contents(of: folder.url).allSatisfy { $0 == "slip.zip" || $0.hasPrefix("out") })
    }

    @Test func encryptedArchiveAsksForPassword() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let source = folder.url.appending(path: "secret.txt")
        try Data("secret".utf8).write(to: source)
        let archive = folder.url.appending(path: "locked.7z")
        let process = try Process.run(sevenZip.executable, arguments: ["a", "-bso0", "-bsp0", "-pswordfish", "-mhe=on",
                                                                        archive.path, source.path])
        process.waitUntilExit()

        await #expect(throws: EngineError(.passwordRequired)) { try await sevenZip.list(archive) }
        let listing = try await sevenZip.list(archive, password: "swordfish")
        #expect(listing.entries.map(\.path) == ["secret.txt"])
    }

    @Test func notAnArchiveIsReported() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let text = folder.url.appending(path: "notes.txt")
        try Data("just text".utf8).write(to: text)
        await #expect(throws: EngineError(.notAnArchive)) { try await sevenZip.list(text) }
    }
}

/// End to end through the sandboxed XPC service, staging and atomic placement.
@Suite("Extraction", .enabled(if: SevenZip.bundled() != nil, "7zz isn't bundled — run scripts/fetch-7zip.sh"))
@MainActor
struct ExtractionTests {
    @Test func extractsEverythingIntoAFolderNamedAfterTheArchive() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let zip = folder.url.appending(path: "Handoff.zip")
        try ZipFixture(entries: [.file("README.md", "read me"), .file("Docs/a.txt", "a")]).write(to: zip)
        let destination = folder.url.appending(path: "Out", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)

        let archive = Archive(listing: try await ArchiveEngine.shared.list(zip), url: zip)
        #expect(archive.totalSize == 8)

        let fractions = Fractions()
        let first = try await Extraction.run(archive, selection: nil, to: destination) { fractions.add($0) }
        let second = try await Extraction.run(archive, selection: nil, to: destination) { _ in }

        #expect(first.placed.map(\.lastPathComponent) == ["Handoff"])
        #expect(second.placed.map(\.lastPathComponent) == ["Handoff 2"]) // never replaces
        #expect(TemporaryFolder.contents(of: destination.appending(path: "Handoff")) == ["Docs", "Docs/a.txt", "README.md"])
        // Progress travels back from the engine over XPC, in order, ending complete.
        #expect(!fractions.values.isEmpty)
        #expect(fractions.values == fractions.values.sorted() && fractions.values.allSatisfy { (0...1).contains($0) })
    }

    @Test func extractsSelectionSideBySide() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let zip = folder.url.appending(path: "photos.zip")
        try ZipFixture(entries: [.file("Photos/Pier.jpg", "p"), .file("Photos/Dock.jpg", "d"), .file("Other/x.txt", "x")])
            .write(to: zip)
        let archive = Archive(listing: try await ArchiveEngine.shared.list(zip), url: zip)
        let selection = archive.children(of: "Photos")

        let result = try await Extraction.run(archive, selection: selection, to: folder.url) { _ in }

        #expect(Set(result.placed.map(\.lastPathComponent)) == ["Pier.jpg", "Dock.jpg"])
        #expect(!FileManager.default.fileExists(atPath: folder.url.appending(path: "x.txt").path))
    }

    @Test func zipSlipThroughTheEngineIsContainedAndReported() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let zip = folder.url.appending(path: "slip.zip")
        try ZipFixture(entries: [
            .file("ok.txt", "fine"),
            .file("../../evil.txt", "bad"),
            .symlink("passwd", to: "../../../../etc/passwd"),
        ]).write(to: zip)
        let destination = folder.url.appending(path: "Out", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)

        var archive = Archive(listing: try await ArchiveEngine.shared.list(zip), url: zip)
        let result = try await Extraction.run(archive, selection: nil, to: destination) { _ in }
        archive.record(Checkup.findings(for: result.report))

        #expect(TemporaryFolder.contents(of: destination) == ["slip", "slip/evil.txt", "slip/ok.txt"])
        #expect(TemporaryFolder.contents(of: folder.url).allSatisfy { $0 == "slip.zip" || $0.hasPrefix("Out") })
        let titles = archive.checkup.map(\.title)
        #expect(titles.contains("1 path tried to leave the folder"))
        #expect(titles.contains("1 link pointed outside the folder"))
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellingLeavesNothingBehind() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let big = folder.url.appending(path: "noise.bin")
        var bytes = [UInt8](repeating: 0, count: 96 << 20)
        for index in stride(from: 0, to: bytes.count, by: 8) { bytes[index] = UInt8.random(in: 0...255) }
        try Data(bytes).write(to: big)
        let archive7z = folder.url.appending(path: "big.7z")
        let process = try Process.run(SevenZip.bundled()!.executable,
                                      arguments: ["a", "-bso0", "-bsp0", "-mx1", archive7z.path, big.path])
        process.waitUntilExit()
        try FileManager.default.removeItem(at: big)
        let destination = folder.url.appending(path: "Out", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        let archive = Archive(listing: try await ArchiveEngine.shared.list(archive7z), url: archive7z)

        let started = Fractions()
        let task = Task { try await Extraction.run(archive, selection: nil, to: destination) { started.add($0) } }
        let deadline = ContinuousClock.now + .seconds(20)
        while started.values.isEmpty, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        try #require(!started.values.isEmpty, "no progress arrived from the engine")
        task.cancel()

        await #expect(throws: EngineError(.cancelled)) { try await task.value }
        #expect(TemporaryFolder.contents(of: destination).isEmpty)
    }

    @Test func listingAFileThatIsntAnArchiveFails() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let text = folder.url.appending(path: "notes.zip")
        try Data("not really a zip".utf8).write(to: text)
        await #expect(throws: EngineError(.notAnArchive)) { try await ArchiveEngine.shared.list(text) }
    }

    @Test func numberedNamesKeepTheExtension() {
        #expect(Extraction.numbered("Report.pdf", 1) == "Report.pdf")
        #expect(Extraction.numbered("Report.pdf", 2) == "Report 2.pdf")
        #expect(Extraction.numbered("Photos", 3) == "Photos 3")
        #expect(Extraction.numbered(".hidden", 2) == ".hidden 2")
    }
}

private nonisolated final class Fractions: Sendable {
    private let storage = Mutex<[Double]>([])
    var values: [Double] { storage.withLock { $0 } }
    func add(_ value: Double) { storage.withLock { $0.append(value) } }
}

extension TemporaryFolder {
    static func contents(of url: URL) -> [String] {
        (FileManager.default.enumerator(atPath: url.path)?.allObjects as? [String] ?? []).sorted()
    }
}
