import Foundation
import Testing
@testable import Stow

/// Issue #22: 7-Zip's listing is parsed as it arrives, in chunks cut anywhere.
struct StreamingListingTests {
    /// `7zz l -slt` output for a small ZIP: a folder, a link, a legacy (non-UTF-8) name, a name
    /// ending in a carriage return.
    static let output: String = {
        var text = "\n7-Zip (z) 24.09 (arm64) : Copyright (c) 1999-2024 Igor Pavlov : 2024-11-29\n\n"
            + "Scanning the drive for archives:\n1 file, 2048 bytes (2 KiB)\n\nListing archive: x.zip\n\n"
            + "--\nPath = x.zip\nType = zip\nPhysical Size = 2048\nTail Size = 12\n\n----------\n"
        func entry(_ path: String, folder: Bool = false, size: Int = 3, attributes: String = "A -rw-r--r--",
                   link: String? = nil, utf8: Bool = true) {
            text += "Path = \(path)\nFolder = \(folder ? "+" : "-")\nSize = \(size)\nPacked Size = \(size)\n"
                + "Modified = 2026-10-20 12:00:00\nAttributes = \(attributes)\nEncrypted = -\n"
            if let link { text += "Symbolic Link = \(link)\n" }
            if utf8 { text += "Characteristics = UTF8\n" }
            text += "\n"
        }
        entry("Docs", folder: true, size: 0, attributes: "D drwxr-xr-x")
        entry("Docs/a.txt")
        entry("Docs/Icon\r", size: 0)
        entry("Docs/link", attributes: " lrwxr-xr-x", link: "a.txt")
        entry("Docs/会议记录.txt", utf8: false)
        for index in 0..<40 { entry("Many/Item \(index).txt", size: index) }
        return text
    }()

    private func streamed(_ text: String, chunk: Int) -> (listing: ArchiveListing, legacy: [Int])? {
        let data = Data(text.utf8)
        var parser = SevenZip.ListingParser()
        var start = 0
        while start < data.count {
            let end = min(start + chunk, data.count)
            parser.consume(data.subdata(in: start..<end))
            start = end
        }
        return parser.finish()
    }

    @Test(arguments: [1, 7, 64, 4_096, 1 << 20])
    func chunksCutAnywhereReadTheSame(chunk: Int) throws {
        let whole = try #require(SevenZip.parseListingFast(Self.output))
        let pieces = try #require(streamed(Self.output, chunk: chunk))
        #expect(pieces.listing.entries == whole.listing.entries)
        #expect(pieces.legacy == whole.legacy)
        #expect(pieces.legacy == [4])
        #expect(pieces.listing.type == "zip")
        #expect(pieces.listing.physicalSize == 2_048)
        #expect(pieces.listing.tailSize == 12)
        #expect(pieces.listing.entries.count == 45)
        #expect(pieces.listing.entries[2].path == "Docs/Icon\r")
        #expect(pieces.listing.entries[3].isSymlink && pieces.listing.entries[3].linkTarget == "a.txt")
    }

    @Test func entriesArriveWhileTheListingRuns() {
        let data = Data(Self.output.utf8)
        var parser = SevenZip.ListingParser()
        parser.consume(data.prefix(data.count / 2))
        let halfway = parser.count
        #expect(halfway > 5 && halfway < 45)
        parser.consume(data.suffix(from: data.count / 2))
        #expect(parser.finish()?.listing.entries.count == 45)
    }

    @Test func otherFormatsGiveUpAtTheHeader() {
        let text = "--\nPath = a.gz\nType = gzip\n\n----------\nPath = a\nSize = 3\n\n"
        var parser = SevenZip.ListingParser()
        parser.consume(Data(text.utf8))
        #expect(!parser.isUsable)
        #expect(parser.count == 0)
        #expect(parser.finish()?.legacy == nil)
        // parseListing still reads it, as before.
        #expect(SevenZip.parseListing(text)?.entries.map(\.path) == ["a"])
    }
}

/// Before/after for PARITY.md: the same 100,000-entry archive listed by 7-Zip, parsed after the
/// listing (before #22) and while it runs (now). Times are printed; limits only catch a collapse.
@Suite("Big listings", .enabled(if: SevenZip.bundled() != nil, "7zz isn't bundled — run scripts/fetch-7zip.sh"))
struct StreamingListingBenchmark {
    @Test func hundredThousandEntriesStreamed() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        // A TAR: ZipFixture writes no ZIP64, so it stops at 65,535 entries. 7-Zip reads TAR on the
        // same fast path as ZIP and 7z.
        let zip = folder.url.appending(path: "big.tar")
        let clock = ContinuousClock()
        let write = try clock.measure {
            try Self.tar((0..<100_000).map { "Folder \($0 / 200)/Item \($0 % 200).txt" }).write(to: zip)
        }
        let sevenZip = try #require(SevenZip.bundled())

        _ = try await sevenZip.list(.file(zip)) // warm the file cache
        var before: ArchiveListing!
        var after: ArchiveListing!
        let parsedAfter = try await clock.measure { before = try await sevenZip.list(.file(zip), streamed: false) }
        let parsedWhile = try await clock.measure { after = try await sevenZip.list(.file(zip)) }
        var wire = Data()
        let encode = try clock.measure { wire = try JSONEncoder.engine.encode(after) }
        let decode = try clock.measure { _ = try JSONDecoder.engine.decode(ArchiveListing.self, from: wire) }
        let model = clock.measure { _ = Archive(listing: after, url: zip) }
        print("100k-entry TAR listing — fixture \(write); parsed after 7-Zip \(parsedAfter), parsed while it lists \(parsedWhile); "
              + "XPC JSON encode \(encode), decode \(decode) (\(wire.count / 1_000_000) MB); browser model \(model)")

        #expect(after.entries == before.entries)
        #expect(after.entries.count == 100_000)
        #expect(parsedWhile < .seconds(30) && parsedAfter < .seconds(30))
    }

    /// A ustar archive of empty files: one 512-byte header each.
    static func tar(_ names: [String]) -> Data {
        var data = Data(capacity: (names.count + 2) * 512)
        for name in names {
            var header = [UInt8](repeating: 0, count: 512)
            func put(_ text: String, at offset: Int) {
                for (index, byte) in text.utf8.enumerated() { header[offset + index] = byte }
            }
            put(name, at: 0)
            put("0000644", at: 100)
            put("0000000", at: 108)
            put("0000000", at: 116)
            put("00000000000", at: 124)
            put("14707275600", at: 136) // 2026-ish, octal seconds
            put("        ", at: 148)
            header[156] = UInt8(ascii: "0")
            put("ustar", at: 257)
            put("00", at: 263)
            let sum = header.reduce(0) { $0 + Int($1) }
            put(String(format: "%06o", sum) + "\0 ", at: 148)
            data.append(contentsOf: header)
        }
        data.append(Data(count: 1_024))
        return data
    }
}
