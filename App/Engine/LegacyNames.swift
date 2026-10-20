import Foundation

/// 7-Zip writes names stored in an older encoding the way it reads them under UTF-8 — garbled.
/// Once the files are received, they're moved to the names Stow shows (`ArchiveSource.renamed`).
nonisolated enum LegacyNames {
    /// `renamed` maps contained paths as written → as shown. Never replaces anything; folders left
    /// empty by the moves are removed.
    static func repair(_ renamed: [String: String], in root: URL) {
        guard !renamed.isEmpty else { return }
        let fileManager = FileManager.default
        var emptied = Set<String>()
        // Deepest first, so a folder's contents move before the folder itself is considered.
        for (written, shown) in renamed.sorted(by: { $0.key.count > $1.key.count }) {
            let from = root.appending(path: written), to = root.appending(path: shown)
            guard (try? fileManager.attributesOfItem(atPath: from.path)) != nil,
                  (try? fileManager.attributesOfItem(atPath: to.path)) == nil else { continue }
            var isFolder: ObjCBool = false
            fileManager.fileExists(atPath: from.path, isDirectory: &isFolder)
            if isFolder.boolValue {
                // Explicit folder entries: the shown folder is created by its files' moves.
                try? fileManager.createDirectory(at: to, withIntermediateDirectories: true)
                emptied.insert(written)
                continue
            }
            try? fileManager.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? fileManager.moveItem(at: from, to: to)) != nil {
                var parent = (written as NSString).deletingLastPathComponent
                while !parent.isEmpty, emptied.insert(parent).inserted {
                    parent = (parent as NSString).deletingLastPathComponent
                }
            }
        }
        for folder in emptied.sorted(by: { $0.count > $1.count }) {
            let url = root.appending(path: folder)
            if (try? fileManager.contentsOfDirectory(atPath: url.path))?.isEmpty == true {
                try? fileManager.removeItem(at: url)
            }
        }
    }
}
