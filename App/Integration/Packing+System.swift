import Foundation

/// What Finder's Quick Compress and the Services menu need from the create engine
/// (`EnginePacker`); tests can swap in their own.
protocol ArchivePacking: Sendable {
    /// Packs `items` into a new archive at `archive` (which doesn't exist yet).
    func pack(_ items: [URL], options: PackOptions, to archive: URL,
              onProgress: @escaping @Sendable (Double) -> Void) async throws(EngineError)
}

enum Packers {
    static var current: any ArchivePacking = EnginePacker()
}

/// Quick Compress uses a snapshot of the configured recipient's defaults, saved beside the items.
/// It remains a single unencrypted output; password and split choices require the Pack window.
enum QuickCompress {
    static var options: PackOptions { options(in: .standard) }

    static func options(in store: UserDefaults) -> PackOptions {
        var options = PackPreferences.options(in: store)
        options.split = .none
        return options
    }

    /// "Report.pdf" → "Report.zip"; a folder "Photos" → "Photos.zip"; several items → "Archive.zip".
    /// Numbered like Finder does when the name is taken.
    static func destination(for items: [URL], format: PackFormat = .zip, exists: (URL) -> Bool) -> URL {
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
        let ext = format.fileExtension
        var attempt = 1
        while true {
            let numberedStem = attempt == 1 ? stem : "\(stem) \(attempt)"
            let candidate = folder.appending(path: "\(numberedStem).\(ext)")
            if !exists(candidate) || attempt >= 10_000 { return candidate }
            attempt += 1
        }
    }
}
