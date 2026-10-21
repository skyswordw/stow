import Foundation

/// Disk images are browsed through the engine, read-only and without mounting: 7-Zip reads HFS+,
/// APFS and ISO 9660 straight from the file, so nothing is attached, nothing needs detaching, and a
/// busy or already-mounted image opens just the same.
///
/// What a developer adds to lay out the Finder window — background art, a volume icon, the
/// "drag here" shortcut to Applications — isn't content. It's hidden, left out when extracting, and
/// the shortcuts become install targets.
nonisolated enum DiskImageLayout {
    /// Top-level names on a volume that are layout or file-system bookkeeping.
    static let extraNames: Set<String> = [
        ".background", ".VolumeIcon.icns", ".DS_Store", ".fseventsd", ".Trashes", ".Spotlight-V100",
        ".HFS+ Private Directory Data\r", ".HFS+ Private Directory Data", "[HFS+ Private Data]", ".journal", ".journal_info_block",
        ".TemporaryItems", ".DocumentRevisions-V100", ".apdisk", ".com.apple.timemachine.donotpresent",
        ".PKInstallSandboxManager", ".PKInstallSandboxManager-SystemSoftware",
    ]

    /// A shortcut on the volume, like "Applications → /Applications": the developer's "drag here".
    struct DropTarget: Hashable, Sendable {
        /// The link's path in the browser.
        let path: String
        /// Absolute folder it points at.
        let folder: String

        var name: String { (path as NSString).lastPathComponent }
        var url: URL { URL(filePath: folder, directoryHint: .isDirectory) }
    }

    struct Layout: Equatable, Sendable {
        var volumeRoot = ""
        /// Contained paths of hidden top-level items (drop-target links included).
        var extras: [String] = []
        var dropTargets: [DropTarget] = []

        func hides(_ path: String) -> Bool {
            extras.contains { path == $0 || path.hasPrefix($0 + "/") }
        }
    }

    /// `entries` with contained paths. HFS+ images list everything under the volume's name;
    /// APFS and ISO images list the volume's contents at the top.
    static func layout(of entries: [(path: String, isFolder: Bool, isSymlink: Bool, linkTarget: String?)]) -> Layout {
        var layout = Layout()
        let firsts = Set(entries.map { $0.path.split(separator: "/").first.map(String.init) ?? "" })
        if firsts.count == 1, let only = firsts.first, (only as NSString).pathExtension.isEmpty,
           entries.contains(where: { $0.path.hasPrefix(only + "/") }) {
            layout.volumeRoot = only
        }
        let prefix = layout.volumeRoot.isEmpty ? "" : layout.volumeRoot + "/"
        for entry in entries where entry.path.hasPrefix(prefix) {
            let relative = String(entry.path.dropFirst(prefix.count))
            guard !relative.isEmpty, !relative.contains("/") else { continue }
            if extraNames.contains(relative) {
                layout.extras.append(entry.path)
            } else if entry.isSymlink, let folder = dropFolder(name: relative, target: entry.linkTarget) {
                layout.extras.append(entry.path)
                layout.dropTargets.append(DropTarget(path: entry.path, folder: folder))
            }
        }
        layout.extras.sort()
        return layout
    }

    /// APFS listings carry the link target; HFS+ ones don't, so a link named "Applications" is
    /// taken at its word.
    private static func dropFolder(name: String, target: String?) -> String? {
        if let target, target.hasPrefix("/") { return target }
        if (target ?? "").isEmpty, name == "Applications" { return "/Applications" }
        return nil
    }
}
