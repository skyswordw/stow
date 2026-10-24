import Foundation

/// When a Mac packs files into a ZIP (Finder's Compress, `ditto -c -k --sequesterRsrc`), each
/// file's extended attributes — Finder tags, comments, Finder info, resource forks — travel as an
/// AppleDouble file in `__MACOSX/…/._name` (or `._name` beside it). Archive Utility puts them back;
/// so does Stow, then drops the helper files.
///
/// Format: Apple's AppleSingle/AppleDouble (RFC 1740), version 2, with macOS's extended-attribute
/// block appended to the Finder-info entry. Everything is big-endian.
nonisolated enum AppleDouble {
    static let magic: UInt32 = 0x0005_1607
    private static let finderInfoID: UInt32 = 9
    private static let resourceForkID: UInt32 = 2
    private static let attributesMagic: UInt32 = 0x4154_5452 // "ATTR"

    /// Never restored: security and provenance markers belong to this Mac, not the archive.
    static let skipped: Set<String> = [
        "com.apple.quarantine", "com.apple.provenance", "com.apple.macl", "com.apple.rootless",
    ]

    /// Attribute name → value. Nil if `data` isn't AppleDouble.
    static func attributes(in data: Data) -> [String: Data]? {
        let bytes = [UInt8](data)
        guard bytes.count >= 26, u32(bytes, 0) == magic else { return nil }
        let count = Int(u16(bytes, 24))
        var result: [String: Data] = [:]
        for index in 0..<count {
            let base = 26 + index * 12
            guard base + 12 <= bytes.count else { return nil }
            let id = u32(bytes, base), offset = Int(u32(bytes, base + 4)), length = Int(u32(bytes, base + 8))
            guard offset >= 0, length >= 0, offset + length <= bytes.count else { return nil }
            switch id {
            case finderInfoID:
                let info = Data(bytes[offset..<(offset + min(32, length))])
                if info.count == 32, info.contains(where: { $0 != 0 }) { result["com.apple.FinderInfo"] = info }
                if length > 32 { extended(bytes, at: offset + 34, into: &result) }
            case resourceForkID where length > 0:
                result["com.apple.ResourceFork"] = Data(bytes[offset..<(offset + length)])
            default:
                break
            }
        }
        return result
    }

    /// The extended-attribute block after the 32 bytes of Finder info (and 2 bytes of padding).
    private static func extended(_ bytes: [UInt8], at start: Int, into result: inout [String: Data]) {
        guard start + 36 <= bytes.count, u32(bytes, start) == attributesMagic else { return }
        let count = Int(u16(bytes, start + 34))
        var cursor = start + 36
        for _ in 0..<count {
            guard cursor + 11 <= bytes.count else { return }
            let offset = Int(u32(bytes, cursor)), length = Int(u32(bytes, cursor + 4))
            let nameLength = Int(bytes[cursor + 10])
            guard nameLength > 0, cursor + 11 + nameLength <= bytes.count,
                  offset + length <= bytes.count else { return }
            let nameBytes = bytes[(cursor + 11)..<(cursor + 11 + nameLength)].prefix { $0 != 0 }
            let name = String(decoding: nameBytes, as: UTF8.self)
            result[name] = Data(bytes[offset..<(offset + length)])
            cursor = (cursor + 11 + nameLength + 3) & ~3
        }
    }

    struct Restored: Equatable, Sendable {
        var files = 0
        var attributes = 0
    }

    /// At most this much attribute data travels back from the engine (resource forks can be big).
    static let transferLimit = 32 << 20

    /// Engine side. Reads AppleDouble companions and deletes those not explicitly selected.
    /// Companions are found by exact path: inside a sandbox, directory listings hide `._` files
    /// even though they exist. Keys are paths relative to `root`.
    static func collect(in root: URL, preserving paths: [String] = []) -> [String: [String: Data]] {
        let fileManager = FileManager.default
        guard let walker = fileManager.enumerator(at: root, includingPropertiesForKeys: nil) else { return [:] }
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        let items = walker.compactMap { $0 as? URL }.map { String($0.path.dropFirst(rootPath.count)) }
            .filter { !$0.hasPrefix("__MACOSX") }
        var collected: [String: [String: Data]] = [:]
        var budget = transferLimit
        for relative in items {
            let name = (relative as NSString).lastPathComponent
            let parent = (relative as NSString).deletingLastPathComponent
            let inline = parent.isEmpty ? "._\(name)" : "\(parent)/._\(name)"
            for companion in ["__MACOSX/" + inline, inline] {
                let url = root.appending(path: companion)
                guard let data = try? Data(contentsOf: url) else { continue }
                let explicitlySelected = paths.contains {
                    let selected = PathContainment.containedPath(for: $0)
                    return companion == selected || companion.hasPrefix(selected + "/")
                }
                if !explicitlySelected { try? fileManager.removeItem(at: url) }
                guard var attributes = attributes(in: data) else { continue }
                attributes = attributes.filter { !skipped.contains($0.key) }
                let size = attributes.values.reduce(0) { $0 + $1.count }
                guard !attributes.isEmpty, size <= budget else { continue }
                budget -= size
                collected[relative, default: [:]].merge(attributes) { _, new in new }
            }
        }
        return collected
    }

    /// App side. Puts collected details back on the staged files under `root`.
    @discardableResult
    static func apply(_ metadata: [String: [String: Data]], in root: URL) -> Restored {
        var restored = Restored()
        for (relative, attributes) in metadata {
            let target = root.appending(path: relative)
            var applied = 0
            for (name, value) in attributes where !skipped.contains(name) {
                let status = value.withUnsafeBytes {
                    setxattr(target.path, name, $0.baseAddress, value.count, 0, XATTR_NOFOLLOW)
                }
                if status == 0 { applied += 1 }
            }
            if applied > 0 {
                restored.files += 1
                restored.attributes += applied
            }
        }
        return restored
    }

    /// Whether the archive's listing shows it was packed on a Mac.
    static func cameFromMac(_ storedPaths: some Sequence<String>) -> Bool {
        storedPaths.contains { path in
            path.hasPrefix("__MACOSX/") || (path as NSString).lastPathComponent.hasPrefix("._")
        }
    }

    private static func u32(_ bytes: [UInt8], _ at: Int) -> UInt32 {
        bytes[at..<(at + 4)].reduce(0) { $0 << 8 | UInt32($1) }
    }

    private static func u16(_ bytes: [UInt8], _ at: Int) -> UInt16 {
        UInt16(bytes[at]) << 8 | UInt16(bytes[at + 1])
    }
}
