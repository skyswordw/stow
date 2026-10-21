import Foundation
import Testing
@testable import Stow

@Suite("Checkup: extension against real format")
struct CheckupFormatTests {
    private static let sfxListing = """
    Listing archive: Setup.exe

    --
    Path = Setup.exe
    Open WARNING: Cannot open the file as [PE] archive
    Type = 7z
    Offset = 70000
    Physical Size = 124
    Headers Size = 114
    Method = LZMA2:12
    Solid = -
    Blocks = 1

    ----------
    Path = a.txt
    Size = 6
    Packed Size = 10
    Modified = 2026-10-20 00:13:47
    Attributes = A -rw-r--r--
    Encrypted = -

    """

    private static let stubAndTailListing = """
    --
    Path = both.zip
    Warning: The archive is open with offset
    Type = zip
    WARNINGS:
    There are data after the end of archive
    Physical Size = 4140
    Tail Size = 500
    Embedded Stub Size = 4027

    ----------
    Path = a.txt
    Size = 5
    Packed Size = 5
    Modified = 2026-10-20 00:13:47
    Attributes = A -rw-r--r--
    Encrypted = -
    Characteristics = UTF8

    """

    @Test func parserReadsOffsetAndTail() throws {
        let sfx = try #require(SevenZip.parseListing(Self.sfxListing))
        #expect(sfx.type == "7z" && sfx.startOffset == 70000 && sfx.tailSize == nil)
        let both = try #require(SevenZip.parseListing(Self.stubAndTailListing))
        #expect(both.startOffset == 4027 && both.tailSize == 500)
        #expect(both.entries.map(\.path) == ["a.txt"])
    }

    @Test func fastParserAgrees() throws {
        for text in [Self.sfxListing, Self.stubAndTailListing] {
            let fast = try #require(SevenZip.parseListingFast(text)).listing
            let general = try #require(SevenZip.parseListing(text))
            #expect(fast.startOffset == general.startOffset)
            #expect(fast.tailSize == general.tailSize)
            #expect(fast.entries.map(\.path) == general.entries.map(\.path))
        }
    }

    @Test func plainArchivesHaveNoOffset() throws {
        let text = Self.sfxListing.replacingOccurrences(of: "Offset = 70000\n", with: "")
        let listing = try #require(SevenZip.parseListing(text))
        #expect(listing.startOffset == nil && listing.tailSize == nil)
    }

    @Test func mismatchedExtensionIsACaution() throws {
        let scan = Checkup.FormatScan(name: "Report.zip", real: .sevenZip, realType: "7z")
        #expect(scan.isMismatched && !scan.isSelfExtracting)
        let finding = try #require(scan.findings.first)
        #expect(scan.findings.count == 1)
        #expect(finding.severity == .caution)
        #expect(finding.title == "Named .zip, but it’s really 7Z")
        #expect(finding.detail.contains("“.7z”"))
    }

    @Test func unknownRealFormatUsesSevenZipsName() throws {
        let scan = Checkup.FormatScan(name: "Drivers.zip", real: .other, realType: "Cab")
        let finding = try #require(scan.findings.first)
        #expect(finding.title == "Named .zip, but it’s really CAB")
        #expect(!finding.detail.contains("“."))
    }

    @Test(arguments: [
        ("Photos.zip", ArchiveFormat.zip, "zip"),
        ("logs.tar.gz", .tarGz, "gzip"),
        ("logs.tgz", .tarGz, "gzip"),
        ("Backup.rar", .rar, "Rar5"),
        ("Installer.dmg", .dmg, "APFS"),
        ("Disc.iso", .dmg, "HFS"),
        ("Letter.docx", .zip, "zip"),
        ("Tool.jar", .zip, "zip"),
        ("Photos.cpio", .other, "Cpio"),
    ])
    func matchingNamesSayNothing(name: String, real: ArchiveFormat, type: String) {
        let scan = Checkup.FormatScan(name: name, real: real, realType: type)
        #expect(!scan.isMismatched)
        #expect(scan.findings.isEmpty)
    }

    @Test func selfExtractingExecutable() throws {
        let scan = Checkup.FormatScan(name: "Setup.exe", real: .sevenZip, realType: "7z", startOffset: 70_000)
        #expect(scan.isSelfExtracting && !scan.isMismatched)
        #expect(scan.findings.count == 1)
        let finding = try #require(scan.findings.first)
        #expect(finding.severity == .caution)
        #expect(finding.title == "Self-extracting 7Z archive")
        #expect(finding.detail.contains("never runs the program"))
    }

    @Test func prependedDataOnAnArchiveName() throws {
        let scan = Checkup.FormatScan(name: "Photos.zip", real: .zip, realType: "zip", startOffset: 4027, tailSize: 500)
        #expect(!scan.isSelfExtracting)
        #expect(scan.findings.map(\.title) == ["Extra data before the archive", "Extra data after the archive"])
        #expect(scan.findings.allSatisfy { $0.severity == .caution })
    }

    @Test func appendedDataOnly() {
        let scan = Checkup.FormatScan(name: "Photos.zip", real: .zip, realType: "zip", tailSize: 3000)
        #expect(scan.findings.map(\.title) == ["Extra data after the archive"])
    }

    @Test func archiveFromListingCarriesTheFindingAndDropsAllClear() throws {
        var listing = try #require(SevenZip.parseListing(Self.sfxListing))
        let archive = Archive(listing: listing, url: URL(filePath: "/tmp/Setup.exe"))
        #expect(archive.format == .sevenZip)
        #expect(archive.checkup.first?.title == "Self-extracting 7Z archive")
        #expect(!archive.checkup.contains { $0.severity == .fine })

        listing.startOffset = nil
        let renamed = Archive(listing: listing, url: URL(filePath: "/tmp/Quarterly.zip"))
        #expect(renamed.checkup.first?.title == "Named .zip, but it’s really 7Z")

        let honest = Archive(listing: listing, url: URL(filePath: "/tmp/Quarterly.7z"))
        #expect(honest.checkup.contains { $0.severity == .fine })
        #expect(!honest.checkup.contains { $0.severity == .caution })
    }
}

@Suite("Checkup: real format through 7-Zip", .enabled(if: SevenZip.bundled() != nil, "7zz isn't bundled — run scripts/fetch-7zip.sh"))
struct CheckupFormatEngineTests {
    let sevenZip = SevenZip.bundled()!
    let entries: [ZipFixture.Entry] = [.file("Docs/a.txt", "hello"), .file("b.txt", "world")]
    let stub = Data("#!/bin/sh\necho 'self-extracting stub'\nexit 0\n".utf8) + Data(repeating: 0x90, count: 4000)

    @Test func zipWithStubAsExecutableIsSelfExtracting() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let url = folder.url.appending(path: "Setup.exe")
        try ZipFixture(entries: entries, prefix: stub).write(to: url)
        let listing = try await sevenZip.list(url)
        #expect(listing.type == "zip")
        #expect(listing.startOffset == Int64(stub.count))
        let archive = Archive(listing: listing, url: url)
        #expect(archive.checkup.first?.title == "Self-extracting ZIP archive")
        #expect(archive.files.count == 2)
    }

    @Test func zipWithPrependedAndAppendedData() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let url = folder.url.appending(path: "Photos.zip")
        try ZipFixture(entries: entries, prefix: stub, suffix: Data(repeating: 7, count: 777)).write(to: url)
        let listing = try await sevenZip.list(url)
        #expect(listing.startOffset == Int64(stub.count))
        #expect(listing.tailSize == 777)
        let titles = Archive(listing: listing, url: url).checkup.map(\.title)
        #expect(titles.contains("Extra data before the archive"))
        #expect(titles.contains("Extra data after the archive"))

        // The archive inside still extracts in full; the extra data doesn't.
        let out = folder.url.appending(path: "out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: false)
        _ = try await sevenZip.extract(url, into: out) { _ in }
        #expect(try String(contentsOf: out.appending(path: "Docs/a.txt"), encoding: .utf8) == "hello")
        #expect(try FileManager.default.contentsOfDirectory(atPath: out.path).sorted() == ["Docs", "b.txt"])
    }

    @Test func zipNamedRarIsMismatched() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let url = folder.url.appending(path: "Backup.rar")
        try ZipFixture(entries: entries).write(to: url)
        let listing = try await sevenZip.list(url)
        #expect(listing.type == "zip" && listing.startOffset == nil && listing.tailSize == nil)
        let archive = Archive(listing: listing, url: url)
        #expect(archive.format == .zip)
        #expect(archive.checkup.first?.title == "Named .rar, but it’s really ZIP")
    }

    @Test func honestZipSaysNothingAboutFormat() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let url = folder.url.appending(path: "Plain.zip")
        try ZipFixture(entries: entries).write(to: url)
        let archive = Archive(listing: try await sevenZip.list(url), url: url)
        #expect(!archive.checkup.contains { $0.severity == .caution })
    }
}
