import Foundation

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

    private struct Fields {
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
        var type: String?
        var physicalSize: Int64?
        var entries: [ListedEntry] = []
        var legacy: [Int] = []
        var current = Fields()
        var hasFields = false
        var section = 0 // 0: preamble, 1: archive properties ("--"), 2: entries ("----------")

        func flush() {
            defer { current = Fields(); hasFields = false }
            guard section == 2, hasFields, let entry = entry(from: current) else { return }
            if type == "zip", !current.utf8Flag, !entry.path.allSatisfy(\.isASCII) { legacy.append(entries.count) }
            entries.append(entry)
        }

        var start = 0
        while start < bytes.count {
            var end = start
            while end < bytes.count, bytes[end] != 10 { end += 1 }
            let whole = UnsafeBufferPointer(rebasing: bytes[start..<end])
            start = end + 1
            // A stray carriage return goes, except on names: "Icon\r" really ends in one.
            let isPath = whole.starts(with: "Path = ".utf8)
            let line = !isPath && whole.last == 13 ? UnsafeBufferPointer(rebasing: whole.dropLast()) : whole

            if section == 0, matches(line, "--") { section = 1; continue }
            if section == 1, matches(line, "----------") {
                guard let type, fastTypes.contains(type) else { return nil }
                section = 2
                continue
            }
            guard section > 0 else { continue }
            if line.isEmpty { flush(); continue }
            guard let separator = separatorIndex(in: line) else { continue }
            let key = UnsafeBufferPointer(rebasing: line[..<separator])
            let value = UnsafeBufferPointer(rebasing: line[min(separator + 3, line.count)...])
            if section == 1 {
                if type == nil, matches(key, "Type") { type = string(value) }
                if physicalSize == nil, matches(key, "Physical Size") { physicalSize = number(value) }
                continue
            }
            if matches(key, "Path") {
                flush()
                current.path = string(value)
            } else if matches(key, "Folder") {
                current.folder = matches(value, "+")
            } else if matches(key, "Size") {
                current.size = number(value)
            } else if matches(key, "Packed Size") {
                current.packedSize = number(value)
            } else if matches(key, "Modified") {
                current.modified = parseDate(string(value))
            } else if matches(key, "Attributes") {
                current.attributes = string(value)
            } else if matches(key, "Encrypted") {
                current.encrypted = matches(value, "+")
            } else if matches(key, "Symbolic Link") {
                current.link = value.isEmpty ? nil : string(value)
            } else if matches(key, "Characteristics") {
                current.utf8Flag = string(value).contains("UTF8")
            }
            hasFields = true
        }
        flush()

        guard let type, fastTypes.contains(type), section == 2 else { return nil }
        return (ArchiveListing(type: type, physicalSize: physicalSize, entries: entries), legacy)
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
