import Foundation

/// What Finder's Quick Compress and the Services menu need from the create engine. The engine
/// is being built separately; until it lands, `Packers.current` is a stand-in that says so, and
/// the create engine only has to conform and be assigned here.
protocol ArchivePacking: Sendable {
    /// Packs `items` into a new archive at `archive` (which doesn't exist yet).
    func pack(_ items: [URL], options: PackOptions, to archive: URL,
              onProgress: @escaping @Sendable (Double) -> Void) async throws(EngineError)
}

enum Packers {
    static var current: any ArchivePacking = PackingNotBuiltYet()
}

struct PackingNotBuiltYet: ArchivePacking {
    func pack(_ items: [URL], options: PackOptions, to archive: URL,
              onProgress: @escaping @Sendable (Double) -> Void) async throws(EngineError) {
        throw EngineError(.failed, "Creating archives isn’t available in this build yet.")
    }
}

/// Quick Compress: the default Pack sentence (ZIP for Windows PCs, which opens everywhere),
/// saved next to the items.
enum QuickCompress {
    static let options = PackOptions()

    /// "Report.pdf" → "Report.zip"; a folder "Photos" → "Photos.zip"; several items → "Archive.zip".
    /// Numbered like Finder does when the name is taken.
    static func destination(for items: [URL], exists: (URL) -> Bool) -> URL {
        let folder = items[0].deletingLastPathComponent()
        let stem: String
        if items.count == 1 {
            let name = items[0].lastPathComponent
            let hasDirectory = items[0].hasDirectoryPath
            let base = hasDirectory ? name : (name as NSString).deletingPathExtension
            stem = base.isEmpty ? name : base
        } else {
            stem = "Archive"
        }
        let ext = options.format.fileExtension
        var attempt = 1
        while true {
            let candidate = folder.appending(path: Extraction.numbered("\(stem).\(ext)", attempt))
            if !exists(candidate) || attempt >= 10_000 { return candidate }
            attempt += 1
        }
    }
}
