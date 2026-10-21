import Foundation
import Synchronization
import UniformTypeIdentifiers

nonisolated enum ArchiveFormat: String, CaseIterable, Identifiable, Sendable {
    case zip, sevenZip, tarGz, tarXz, rar, dmg, iso, tar, gzip, bzip2, xz, other

    var id: Self { self }

    var badge: String {
        switch self {
        case .zip: "ZIP"
        case .sevenZip: "7Z"
        case .tarGz: "TGZ"
        case .tarXz: "TXZ"
        case .rar: "RAR"
        case .dmg: "DMG"
        case .iso: "ISO"
        case .tar: "TAR"
        case .gzip: "GZ"
        case .bzip2: "BZ2"
        case .xz: "XZ"
        case .other: "ARC"
        }
    }

    var displayName: String {
        switch self {
        case .zip: "ZIP"
        case .sevenZip: "7Z"
        case .tarGz: "TAR.GZ"
        case .tarXz: "TAR.XZ"
        case .rar: "RAR"
        case .dmg: "Disk Image"
        case .iso: "ISO Image"
        case .tar: "TAR"
        case .gzip: "GZIP"
        case .bzip2: "BZIP2"
        case .xz: "XZ"
        case .other: "Archive"
        }
    }

    var fileExtension: String {
        switch self {
        case .zip: "zip"
        case .sevenZip: "7z"
        case .tarGz: "tar.gz"
        case .tarXz: "tar.xz"
        case .rar: "rar"
        case .dmg: "dmg"
        case .iso: "iso"
        case .tar: "tar"
        case .gzip: "gz"
        case .bzip2: "bz2"
        case .xz: "xz"
        case .other: ""
        }
    }

    var supportsPassword: Bool { self == .zip || self == .sevenZip }

    static func infer(fromName name: String) -> ArchiveFormat? {
        let lower = name.lowercased()
        if lower.hasSuffix(".tar.gz") || lower.hasSuffix(".tgz") { return .tarGz }
        if lower.hasSuffix(".tar.xz") || lower.hasSuffix(".txz") { return .tarXz }
        return allCases.first { $0 != .other && lower.hasSuffix("." + $0.fileExtension) }
    }

    /// From 7-Zip's `Type` ("zip", "7z", "Rar5", "gzip", …); the name tells a .tar.gz from a .gz.
    init(sevenZipType type: String, name: String) {
        let inferred = Self.infer(fromName: name)
        switch type.lowercased() {
        case "zip": self = .zip
        case "7z": self = .sevenZip
        case "rar", "rar5": self = .rar
        case "dmg", "apfs", "hfs": self = .dmg
        case "iso", "udf": self = .iso
        case "tar": self = .tar
        case "gzip": self = inferred == .tarGz ? .tarGz : .gzip
        case "xz": self = inferred == .tarXz ? .tarXz : .xz
        case "bzip2": self = .bzip2
        default: self = .other
        }
    }
}

nonisolated enum EntryKind: Sendable {
    case folder, image, vector, document, text, data, font, app, installer, archive, audio, video, other

    static func infer(fromName name: String) -> EntryKind {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "heic", "heif", "gif", "tiff", "tif", "webp", "bmp", "avif", "jxl", "ico", "icns",
             "dng", "cr2", "cr3", "nef", "arw", "raf", "orf":
            return .image
        case "svg", "ai", "eps": return .vector
        case "pdf", "pages", "key", "numbers", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "odt", "ods", "odp", "epub":
            return .document
        case "txt", "md", "markdown", "rtf", "log", "readme", "nfo",
             "swift", "c", "h", "m", "mm", "cc", "cpp", "hpp", "cs", "java", "kt", "kts", "go", "rs", "py", "rb",
             "js", "mjs", "cjs", "ts", "tsx", "jsx", "php", "pl", "lua", "r", "scala", "dart", "sh", "zsh", "bash",
             "fish", "ps1", "bat", "cmd", "html", "htm", "css", "scss", "less", "sql", "ini", "cfg", "conf", "toml",
             "env", "gradle", "make", "cmake", "dockerfile", "gitignore", "editorconfig", "srt", "vtt", "tex":
            return .text
        case "json", "yml", "yaml", "xml", "csv", "tsv", "plist", "strings", "geojson": return .data
        case "otf", "ttf", "ttc", "woff", "woff2": return .font
        case "app": return .app
        case "pkg", "mpkg", "dmg": return .installer
        case "zip", "zipx", "7z", "rar", "gz", "tgz", "bz2", "tbz", "tbz2", "xz", "txz", "lz", "lzma", "zst", "tar",
             "cab", "cpio", "xar", "jar", "apk", "ipa", "cbz", "cbr", "cb7", "lzh", "lha", "arj", "z", "001":
            return .archive
        case "wav", "mp3", "m4a", "aiff", "aif", "flac", "aac", "ogg", "opus", "caf", "m4b", "alac": return .audio
        case "mov", "mp4", "m4v", "avi", "mkv", "webm", "mpg", "mpeg", "3gp", "mts": return .video
        default: return .other
        }
    }

    var label: String {
        switch self {
        case .folder: "Folder"
        case .image: "Image"
        case .vector: "Vector Image"
        case .document: "Document"
        case .text: "Text"
        case .data: "Data"
        case .font: "Font"
        case .app: "Application"
        case .installer: "Installer Package"
        case .archive: "Archive"
        case .audio: "Audio"
        case .video: "Movie"
        case .other: "File"
        }
    }

    /// Rough packed/unpacked ratio for estimates, until the engine measures real data.
    var typicalCompressionRatio: Double {
        switch self {
        case .image: 0.97
        case .vector: 0.24
        case .document: 0.86
        case .text, .data: 0.28
        case .font: 0.58
        case .app: 0.44
        case .installer: 0.96
        case .archive: 1.0
        case .audio: 0.81
        case .video: 0.99
        case .folder, .other: 0.7
        }
    }

    /// Whether a hover / inspector preview shows the file's real content.
    var isPreviewable: Bool {
        switch self {
        case .image, .vector, .document, .text, .data, .font, .audio, .video: true
        default: false
        }
    }
}

nonisolated struct ArchiveEntry: Identifiable, Hashable, Sendable {
    let path: String
    let isFolder: Bool
    let size: Int64
    let packedSize: Int64
    let modified: Date
    /// Finder metadata (`.DS_Store`, `._*`, `__MACOSX`): hidden unless people ask to see it.
    var isHelper = false

    var id: String { path }
    var name: String { path.lastIndex(of: "/").map { String(path[path.index(after: $0)...]) } ?? path }
    var parent: String { Self.parent(of: path) }

    /// Paths here are already contained (no leading, trailing or doubled `/`), so this is plain
    /// string work — no bridging, which matters across 100,000 entries.
    static func parent(of path: String) -> String {
        path.lastIndex(of: "/").map { String(path[..<$0]) } ?? ""
    }
    var kind: EntryKind { isFolder && !isPackage ? .folder : EntryKind.infer(fromName: name) }

    /// A folder macOS shows as one file: apps, bundles, `.rtfd`. Opened with Show Package Contents.
    var isPackage: Bool {
        guard isFolder else { return false }
        let ext = (name as NSString).pathExtension
        guard !ext.isEmpty, let type = UTType(filenameExtension: ext, conformingTo: .directory), !type.isDynamic else {
            return false
        }
        return type.conforms(to: .package) || type.conforms(to: .bundle)
    }

    /// Something to step into: a plain folder, not a package.
    var isNavigable: Bool { isFolder && !isPackage }

    /// Finder's words for it ("JPEG image", "Swift Source"), falling back to Stow's own.
    var kindDescription: String {
        if isNavigable { return EntryKind.folder.label }
        return contentType.localizedDescription ?? kind.label
    }

    var contentType: UTType {
        if isNavigable { return .folder }
        if kind == .app { return .applicationBundle }
        return UTType(filenameExtension: (name as NSString).pathExtension) ?? (isFolder ? .package : .data)
    }
}

nonisolated struct FolderNode: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    var children: [FolderNode]?
}

nonisolated struct CheckupFinding: Identifiable, Hashable, Sendable {
    enum Severity: Sendable { case fine, info, handled, caution }

    let id = UUID()
    let severity: Severity
    let title: String
    let detail: String
}

/// Where a real archive lives, and how its entries are named inside it.
nonisolated struct ArchiveSource: Sendable {
    let url: URL
    /// Names stored in an older encoding: where 7-Zip writes each (contained path) → where Stow
    /// shows it. Extraction renames after receiving the files.
    var renamed: [String: String] = [:]
    /// Up to 200 stored names that aren't valid UTF-8, for the encoding picker's preview.
    var legacyNames: [Data] = []
    /// How legacy names were read; nil reads each name in the encoding that suits it best.
    var nameEncoding: NameEncoding?
    /// Kept only when there are legacy names, so they can be read again in another encoding.
    var listing: ArchiveListing?
    /// Displayed (contained) path → the names the archive stores for it. Several hostile names can
    /// land on one path (`../a.txt` and `a.txt`), so it's a list.
    let storedPaths: [String: [String]]
}

nonisolated struct Archive: Identifiable, Sendable {
    let id = UUID()
    var name: String
    var format: ArchiveFormat
    var isEncrypted: Bool
    var checkup: [CheckupFinding]
    /// Everything but macOS helper items, folders included.
    var entries: [ArchiveEntry] { index.visible }
    /// Nil for sample data: there is nothing on disk to extract.
    var source: ArchiveSource?
    /// Children, lookups and totals, built once — archives can hold hundreds of thousands of entries.
    let index: ArchiveIndex

    /// Builds folder entries (with aggregated sizes) from a flat list of files,
    /// the same shape a real archive listing comes in. `helpers` are macOS helper items.
    init(name: String, format: ArchiveFormat, isEncrypted: Bool = false,
         files: [ArchiveEntry], helpers: [ArchiveEntry] = [], checkup: [CheckupFinding] = []) {
        self.name = name
        self.format = format
        self.isEncrypted = isEncrypted
        self.checkup = checkup

        var folders: [String: (size: Int64, packed: Int64, modified: Date)] = [:]
        for file in files {
            var parent = file.parent
            while !parent.isEmpty {
                let current = folders[parent] ?? (0, 0, .distantPast)
                folders[parent] = (current.size + file.size,
                                   current.packed + file.packedSize,
                                   max(current.modified, file.modified))
                parent = ArchiveEntry.parent(of: parent)
            }
        }
        var visible = files.filter { !$0.isFolder || folders[$0.path] == nil }
        visible += folders.map { path, info in
            ArchiveEntry(path: path, isFolder: true, size: info.size, packedSize: info.packed, modified: info.modified)
        }
        // Helper items may sit in folders of their own (`__MACOSX/…`); those folders are helpers too.
        var helperEntries = helpers
        var known = Set(visible.map(\.path)).union(helpers.map(\.path))
        for helper in helpers {
            var parent = helper.parent
            while !parent.isEmpty, known.insert(parent).inserted {
                helperEntries.append(ArchiveEntry(path: parent, isFolder: true, size: 0, packedSize: 0,
                                                  modified: helper.modified, isHelper: true))
                parent = ArchiveEntry.parent(of: parent)
            }
        }
        index = ArchiveIndex(visible: visible, helpers: helperEntries)
    }

    /// The same archive with names read another way (entries, Checkup and source replaced).
    init(_ other: Archive, files: [ArchiveEntry], helpers: [ArchiveEntry], source: ArchiveSource) {
        self.init(name: other.name, format: other.format, isEncrypted: other.isEncrypted,
                  files: files, helpers: helpers, checkup: other.checkup)
        self.source = source
    }

    var files: [ArchiveEntry] { index.files }
    var totalSize: Int64 { index.totalSize }
    var packedSize: Int64 { index.packedSize }
    var hasHelpers: Bool { !index.helpers.isEmpty }

    var hasCautions: Bool { checkup.contains { $0.severity == .caution } }

    func children(of folder: String, includingHelpers: Bool = false) -> [ArchiveEntry] {
        index.children(of: folder, includingHelpers: includingHelpers)
    }

    func entry(at path: String) -> ArchiveEntry? {
        index.entry(at: path)
    }

    /// Every term must appear in the name or the path; name matches come first.
    func search(_ query: String, includingHelpers: Bool = false) -> [ArchiveEntry] {
        let terms = SearchIndex.terms(in: query)
        guard !terms.isEmpty else { return [] }
        let pool = includingHelpers ? index.visible + index.helpers : index.visible
        let matches = pool.compactMap { entry -> (ArchiveEntry, Bool)? in
            let path = SearchIndex.fold(entry.path)
            guard terms.allSatisfy(path.contains) else { return nil }
            let name = SearchIndex.fold(entry.name)
            return (entry, terms.allSatisfy(name.contains))
        }
        return SearchIndex.ranked(matches)
    }

    func folderTree(under folder: String = "", includingHelpers: Bool = false) -> [FolderNode] {
        index.folderTree(under: folder, includingHelpers: includingHelpers)
    }
}

/// Lookups over an archive's entries. Built once, read from any thread; children are sorted the
/// first time a folder is shown, so opening a huge archive doesn't sort folders nobody visits.
nonisolated final class ArchiveIndex: Sendable {
    let visible: [ArchiveEntry]
    let helpers: [ArchiveEntry]
    let files: [ArchiveEntry]
    let totalSize: Int64
    let packedSize: Int64
    private let byPath: [String: ArchiveEntry]
    private let unsorted: [String: [ArchiveEntry]]
    private let sorted = Mutex<[String: [ArchiveEntry]]>([:])
    private let trees = Mutex<[Bool: [String: [FolderNode]]]>([:])

    init(visible: [ArchiveEntry], helpers: [ArchiveEntry]) {
        self.visible = visible
        self.helpers = helpers
        files = visible.filter { !$0.isFolder }
        totalSize = files.reduce(0) { $0 + $1.size }
        packedSize = files.reduce(0) { $0 + $1.packedSize }
        var byPath: [String: ArchiveEntry] = [:]
        byPath.reserveCapacity(visible.count + helpers.count)
        var unsorted: [String: [ArchiveEntry]] = [:]
        for entry in helpers + visible {
            byPath[entry.path] = entry
            unsorted[entry.parent, default: []].append(entry)
        }
        self.byPath = byPath
        self.unsorted = unsorted
    }

    var count: Int { visible.count }

    func entry(at path: String) -> ArchiveEntry? { byPath[path] }

    func children(of folder: String, includingHelpers: Bool) -> [ArchiveEntry] {
        let all = sorted.withLock { cache in
            if let hit = cache[folder] { return hit }
            let result = Self.sort(unsorted[folder] ?? [])
            cache[folder] = result
            return result
        }
        return includingHelpers ? all : all.filter { !$0.isHelper }
    }

    func folderTree(under folder: String, includingHelpers: Bool) -> [FolderNode] {
        if let hit = trees.withLock({ $0[includingHelpers]?[folder] }) { return hit }
        func build(_ folder: String) -> [FolderNode] {
            Self.sort((unsorted[folder] ?? []).filter { $0.isNavigable && (includingHelpers || !$0.isHelper) })
                .map { entry in
                    let sub = build(entry.path)
                    return FolderNode(id: entry.path, name: entry.name, children: sub.isEmpty ? nil : sub)
                }
        }
        let tree = build(folder)
        trees.withLock { $0[includingHelpers, default: [:]][folder] = tree }
        return tree
    }

    /// Folders first, then Finder's order ("File 2" before "File 10").
    static func sort(_ entries: [ArchiveEntry]) -> [ArchiveEntry] {
        let keyed = entries.map { (entry: $0, key: SortKey($0.name)) }
        return keyed.sorted { lhs, rhs in
            if lhs.entry.isNavigable != rhs.entry.isNavigable { return lhs.entry.isNavigable }
            return lhs.key < rhs.key
        }.map(\.entry)
    }
}

/// A precomputed Finder-style sort key: case- and accent-insensitive, digits compared as numbers.
/// Comparing these is far cheaper than `localizedStandardCompare` on every comparison.
nonisolated struct SortKey: Comparable, Sendable {
    private enum Part: Comparable {
        case number(Double, Int)
        case text(String)
    }
    private let parts: [Part]
    private let tiebreak: String

    init(_ name: String) {
        tiebreak = name
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        var parts: [Part] = []
        var digits = "", text = ""
        for character in folded {
            if character.isASCII, character.isNumber {
                if !text.isEmpty { parts.append(.text(text)); text = "" }
                digits.append(character)
            } else {
                if !digits.isEmpty { parts.append(.number(Double(digits) ?? 0, digits.count)); digits = "" }
                text.append(character)
            }
        }
        if !digits.isEmpty { parts.append(.number(Double(digits) ?? 0, digits.count)) }
        if !text.isEmpty { parts.append(.text(text)) }
        self.parts = parts
    }

    static func < (lhs: SortKey, rhs: SortKey) -> Bool {
        for (left, right) in zip(lhs.parts, rhs.parts) where left != right {
            switch (left, right) {
            case (.number, .text): return true
            case (.text, .number): return false
            default: return left < right
            }
        }
        if lhs.parts.count != rhs.parts.count { return lhs.parts.count < rhs.parts.count }
        return lhs.tiebreak < rhs.tiebreak
    }
}

nonisolated extension Int64 {
    var bytes: String { formatted(.byteCount(style: .file)) }
}
