import Foundation

/// System metadata that means nothing once extracted: Finder's `.DS_Store` and AppleDouble `._`
/// files, `__MACOSX`, volume bookkeeping, and Windows' `Thumbs.db` / `desktop.ini`. Ordinary
/// dotfiles (`.gitignore`, `.env`, `.editorconfig`) are content and always kept.
nonisolated enum MacHelperFiles {
    private static let names: Set<String> = [
        ".DS_Store", ".localized", "Icon\r", ".Spotlight-V100", ".fseventsd", ".Trashes",
        ".TemporaryItems", ".DocumentRevisions-V100", ".apdisk",
    ]
    /// Windows writes these with any capitalisation.
    private static let windowsNames: Set<String> = ["thumbs.db", "ehthumbs.db", "desktop.ini"]

    static func matches(_ path: String) -> Bool {
        let components = path.split(separator: "/").map(String.init)
        guard let name = components.last else { return false }
        if components.contains("__MACOSX") { return true }
        if names.contains(name) || windowsNames.contains(name.lowercased()) { return true }
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
