import Foundation
import Synchronization

/// A byte-level reader for `7zz l -slt`, for the common formats only (ZIP, 7z, RAR, tar). A
/// 100,000-entry archive lists as well over a million lines; this reads them without making a
/// string per line or a dictionary per entry, about twice as fast as `parseListing` end to end.
/// Everything else (single streams, disk images, …) goes through `parseListing`, which knows
/// their quirks; this returns nil for those.
nonisolated extension SevenZip {
    private static let fastTypes: Set<String> = ["zip", "7z", "Rar", "Rar5", "tar"]

    /// The listing, and the indices of ZIP entries stored without the UTF-8 flag (7-Zip lists it
    /// under "Characteristics") whose names aren't ASCII.
    static func parseListingFast(_ text: String) -> (listing: ArchiveListing, legacy: [Int])? {
        var text = text
        return text.withUTF8 { parseFast($0) }
    }

    fileprivate struct Fields: Sendable {
        var path: String?
        var folder = false
        var size: Int64?
        var packedSize: Int64?
        var modified: Date?
        var attributes = ""
        var encrypted = false
        var link: String?
        var utf8Flag = false
    }

    private static func parseFast(_ bytes: UnsafeBufferPointer<UInt8>) -> (listing: ArchiveListing, legacy: [Int])? {
        var parser = ListingParser()
        parser.consumeLines(bytes)
        return parser.finish()
    }

    /// A `ListingParser` that 7-Zip's output handler can feed from its own queue.
    final class ListingStream: Sendable {
        private let parser = Mutex(ListingParser())

        func consume(_ chunk: Data) { parser.withLock { $0.consume(chunk) } }
        func finish() -> (listing: ArchiveListing, legacy: [Int])? { parser.withLock { $0.finish() } }
    }

    /// Reads `7zz l -slt` as it arrives (issue #22): feed each chunk of output to `consume` while
    /// 7-Zip is still listing, then `finish`. Parsing overlaps the listing instead of starting
    /// after it, and a chunk is read once, as bytes. Gives up (nil from `finish`) as soon as the
    /// header names a format the fast path doesn't know; `parseListing` takes those.
    struct ListingParser: Sendable {
        private var type: String?
        private var physicalSize: Int64?
        private var archiveFields: [String: String] = [:]
        private var entries: [ListedEntry] = []
        private var legacy: [Int] = []
        private var current = Fields()
        private var hasFields = false
        private var section = 0 // 0: preamble, 1: archive properties ("--"), 2: entries ("----------")
        private var rejected = false
        /// The end of the last chunk, up to its last newline: a line cut in two.
        private var carry: [UInt8] = []

        init() {}

        /// Entries read so far.
        var count: Int { entries.count }
        /// False once the header named a format only `parseListing` reads.
        var isUsable: Bool { !rejected }

        /// The next piece of output, cut anywhere.
        mutating func consume(_ chunk: Data) {
            guard !rejected, !chunk.isEmpty else { return }
            chunk.withUnsafeBytes { raw in
                let bytes = raw.bindMemory(to: UInt8.self)
                guard let last = bytes.lastIndex(of: 10) else {
                    carry.append(contentsOf: bytes)
                    return
                }
                let complete = UnsafeBufferPointer(rebasing: bytes[...last])
                if carry.isEmpty {
                    consumeLines(complete)
                } else {
                    var joined = carry
                    carry = []
                    joined.append(contentsOf: complete)
                    joined.withUnsafeBufferPointer { consumeLines($0) }
                }
                carry.append(contentsOf: bytes[(last + 1)...])
            }
        }

        /// The listing, once the output has ended.
        mutating func finish() -> (listing: ArchiveListing, legacy: [Int])? {
            if !carry.isEmpty {
                let rest = carry
                carry = []
                rest.withUnsafeBufferPointer { consumeLines($0) }
            }
            flush()
            guard !rejected, let type, SevenZip.fastTypes.contains(type), section == 2 else { return nil }
            return (ArchiveListing(type: type, physicalSize: physicalSize, entries: entries,
                                   startOffset: SevenZip.startOffset(archiveFields),
                                   tailSize: archiveFields["Tail Size"].flatMap { Int64($0) }), legacy)
        }

        private mutating func flush() {
            defer { current = Fields(); hasFields = false }
            guard section == 2, hasFields, let entry = SevenZip.entry(from: current) else { return }
            if type == "zip", !current.utf8Flag, !entry.path.allSatisfy(\.isASCII) { legacy.append(entries.count) }
            entries.append(entry)
        }

        /// Whole lines; a final line without its newline counts as whole too.
        fileprivate mutating func consumeLines(_ bytes: UnsafeBufferPointer<UInt8>) {
            var start = 0
            while start < bytes.count, !rejected {
                var end = start
                while end < bytes.count, bytes[end] != 10 { end += 1 }
                let whole = UnsafeBufferPointer(rebasing: bytes[start..<end])
                start = end + 1
                line(whole)
            }
        }

        private mutating func line(_ whole: UnsafeBufferPointer<UInt8>) {
            // A stray carriage return goes, except on names: "Icon\r" really ends in one.
            let isPath = whole.starts(with: "Path = ".utf8)
            let line = !isPath && whole.last == 13 ? UnsafeBufferPointer(rebasing: whole.dropLast()) : whole

            if section == 0, SevenZip.matches(line, "--") { section = 1; return }
            if section == 1, SevenZip.matches(line, "----------") {
                guard let type, SevenZip.fastTypes.contains(type) else { rejected = true; return }
                section = 2
                return
            }
            guard section > 0 else { return }
            if line.isEmpty { flush(); return }
            guard let separator = SevenZip.separatorIndex(in: line) else { return }
            let key = UnsafeBufferPointer(rebasing: line[..<separator])
            let value = UnsafeBufferPointer(rebasing: line[min(separator + 3, line.count)...])
            if section == 1 {
                if type == nil, SevenZip.matches(key, "Type") { type = SevenZip.string(value) }
                if physicalSize == nil, SevenZip.matches(key, "Physical Size") { physicalSize = SevenZip.number(value) }
                if SevenZip.matches(key, "Offset") || SevenZip.matches(key, "Embedded Stub Size") || SevenZip.matches(key, "Tail Size") {
                    archiveFields[SevenZip.string(key)] = archiveFields[SevenZip.string(key)] ?? SevenZip.string(value)
                }
                return
            }
            if SevenZip.matches(key, "Path") {
                flush()
                current.path = SevenZip.string(value)
            } else if SevenZip.matches(key, "Folder") {
                current.folder = SevenZip.matches(value, "+")
            } else if SevenZip.matches(key, "Size") {
                current.size = SevenZip.number(value)
            } else if SevenZip.matches(key, "Packed Size") {
                current.packedSize = SevenZip.number(value)
            } else if SevenZip.matches(key, "Modified") {
                current.modified = SevenZip.parseDate(SevenZip.string(value))
            } else if SevenZip.matches(key, "Attributes") {
                current.attributes = SevenZip.string(value)
            } else if SevenZip.matches(key, "Encrypted") {
                current.encrypted = SevenZip.matches(value, "+")
            } else if SevenZip.matches(key, "Symbolic Link") {
                current.link = value.isEmpty ? nil : SevenZip.string(value)
            } else if SevenZip.matches(key, "Characteristics") {
                current.utf8Flag = SevenZip.string(value).contains("UTF8")
            }
            hasFields = true
        }
    }

    /// Where " = " (or a closing " =") splits a line into key and value.
    private static func separatorIndex(in line: UnsafeBufferPointer<UInt8>) -> Int? {
        guard line.count >= 2 else { return nil }
        for index in 0..<(line.count - 1) where line[index] == 32 && line[index + 1] == 61 {
            if index + 2 == line.count || line[index + 2] == 32 { return index }
        }
        return nil
    }

    private static func matches(_ bytes: UnsafeBufferPointer<UInt8>, _ literal: StaticString) -> Bool {
        guard bytes.count == literal.utf8CodeUnitCount else { return false }
        return bytes.elementsEqual(UnsafeBufferPointer(start: literal.utf8Start, count: literal.utf8CodeUnitCount))
    }

    private static func string(_ bytes: UnsafeBufferPointer<UInt8>) -> String {
        String(decoding: bytes, as: UTF8.self)
    }

    private static func number(_ bytes: UnsafeBufferPointer<UInt8>) -> Int64? {
        guard !bytes.isEmpty else { return nil }
        var value: Int64 = 0
        for byte in bytes {
            guard (48...57).contains(byte) else { return nil }
            value = value &* 10 &+ Int64(byte - 48)
        }
        return value
    }

    private static func entry(from fields: Fields) -> ListedEntry? {
        guard let path = fields.path, !path.isEmpty else { return nil }
        let attributes = fields.attributes
        // "D drwxr-xr-x", " lrwxr-xr-x", "A -rw-r--r--": DOS flags, then a Unix mode string.
        let mode = attributes.split(separator: " ").last.map(String.init) ?? ""
        let isFolder = fields.folder || attributes.hasPrefix("D") || mode.hasPrefix("d")
        return ListedEntry(
            path: path,
            isFolder: isFolder,
            isSymlink: fields.link != nil || (mode.count == 10 && mode.hasPrefix("l")),
            linkTarget: fields.link,
            size: fields.size ?? 0,
            packedSize: fields.packedSize,
            modified: fields.modified,
            isEncrypted: fields.encrypted
        )
    }
}
