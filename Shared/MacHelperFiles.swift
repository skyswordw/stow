import Foundation

/// Finder metadata and AppleDouble files that mean nothing off a Mac — or inside an archive.
nonisolated enum MacHelperFiles {
    static func matches(_ path: String) -> Bool {
        let components = path.split(separator: "/").map(String.init)
        guard let name = components.last else { return false }
        if components.contains("__MACOSX") { return true }
        if [".DS_Store", ".localized", "Icon\r", ".Spotlight-V100", ".fseventsd", ".Trashes"].contains(name) {
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
