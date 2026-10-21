import Foundation

/// Extraction and install settings, stored in UserDefaults under `Preferences.Key`. The Settings
/// window hosts `ExtractionOptionsView` and `InstallOptionsView`; everything else reads `current`.
nonisolated enum Preferences {
    enum Key {
        static let extractAllFolder = "extract.allFolder"
        static let afterExtractAll = "extract.afterExtractAll"
        static let afterInstall = "install.afterInstall"
        static let closeWindowAfter = "extract.closeWindowAfter"
        static let folderConflict = "extract.folderConflict"
        static let fileConflict = "extract.fileConflict"
        static let skipSystemFiles = "extract.skipSystemFiles"
        static let removeQuarantine = "install.removeQuarantine"
    }

    /// Where Extract All puts things.
    enum ExtractAllFolder: String, CaseIterable, Identifiable, Sendable {
        /// One top-level item lands as itself; several go into a folder named after the archive.
        case automatic
        /// Always a folder named after the archive (unless its only item already is that folder).
        case always
        var id: Self { self }
    }

    /// What happens to the archive once Extract All (or an install) finished.
    enum AfterwardsArchive: String, CaseIterable, Identifiable, Sendable {
        case keep, trash, ask
        var id: Self { self }
    }

    enum FolderConflict: String, CaseIterable, Identifiable, Sendable {
        case ask, merge, keepBoth
        var id: Self { self }
    }

    enum FileConflict: String, CaseIterable, Identifiable, Sendable {
        case ask, replace, keepBoth, skip
        var id: Self { self }
    }

    struct Values: Equatable, Sendable {
        var extractAllFolder = ExtractAllFolder.automatic
        var afterExtractAll = AfterwardsArchive.keep
        var afterInstall = AfterwardsArchive.keep
        var closeWindowAfter = false
        var folderConflict = FolderConflict.ask
        var fileConflict = FileConflict.ask
        /// `__MACOSX`, `._*`, `.DS_Store`, `Thumbs.db`, `desktop.ini`… — dotfiles like `.gitignore` stay.
        var skipSystemFiles = true
        /// Off by default: the quarantine flag is what makes Gatekeeper check an app on first open.
        var removeQuarantine = false
    }

    static let defaults = Values()

    static var current: Values { values(in: .standard) }

    static func values(in store: UserDefaults) -> Values {
        func value<T: RawRepresentable<String>>(_ key: String, _ fallback: T) -> T {
            store.string(forKey: key).flatMap(T.init(rawValue:)) ?? fallback
        }
        func flag(_ key: String, _ fallback: Bool) -> Bool {
            store.object(forKey: key) == nil ? fallback : store.bool(forKey: key)
        }
        return Values(
            extractAllFolder: value(Key.extractAllFolder, defaults.extractAllFolder),
            afterExtractAll: value(Key.afterExtractAll, defaults.afterExtractAll),
            afterInstall: value(Key.afterInstall, defaults.afterInstall),
            closeWindowAfter: flag(Key.closeWindowAfter, defaults.closeWindowAfter),
            folderConflict: value(Key.folderConflict, defaults.folderConflict),
            fileConflict: value(Key.fileConflict, defaults.fileConflict),
            skipSystemFiles: flag(Key.skipSystemFiles, defaults.skipSystemFiles),
            removeQuarantine: flag(Key.removeQuarantine, defaults.removeQuarantine)
        )
    }

    static func set(_ value: some RawRepresentable<String>, for key: String, in store: UserDefaults = .standard) {
        store.set(value.rawValue, forKey: key)
    }
}
