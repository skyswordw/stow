import Foundation

/// Finder metadata and AppleDouble files that mean nothing off a Mac — or inside an archive.
nonisolated enum MacHelperFiles {
    static func matches(_ path: String) -> Bool {
        // Byte checks first: almost no name has an underscore, and Unicode-aware `contains` is slow
        // across 100,000 names.
        if path.utf8.contains(UInt8(ascii: "_")), path.split(separator: "/").contains("__MACOSX") { return true }
        let trimmed = path.hasSuffix("/") ? path.dropLast() : Substring(path)
        let name = trimmed.lastIndex(of: "/").map { trimmed[trimmed.index(after: $0)...] } ?? trimmed
        guard !name.isEmpty else { return false }
        if [".DS_Store", ".localized", "Icon\r", ".Spotlight-V100", ".fseventsd", ".Trashes"].contains(String(name)) {
            return true
        }
        return name.hasPrefix("._")
    }

    /// Deletes helper files from an extracted tree.
    static func remove(in root: URL) {
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return }
        let matches = walker.compactMap { $0 as? URL }.filter {
            matches(String($0.path.dropFirst(root.path.count)))
        }
        // Deepest last is fine: removing a folder first makes its children's removal a harmless no-op.
        for url in matches { try? FileManager.default.removeItem(at: url) }
    }
}
