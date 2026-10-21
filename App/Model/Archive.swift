import Foundation
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
        case "jpg", "jpeg", "png", "heic", "gif", "tiff", "webp": return .image
        case "svg", "ai", "eps": return .vector
        case "pdf", "pages", "docx", "key", "numbers", "xlsx": return .document
        case "txt", "md", "rtf": return .text
        case "json", "yml", "yaml", "xml", "csv": return .data
        case "otf", "ttf", "ttc", "woff2": return .font
        case "app": return .app
        case "pkg", "mpkg": return .installer
        case "zip", "7z", "rar", "gz", "xz", "tar", "tgz", "dmg", "iso": return .archive
        case "wav", "mp3", "m4a", "aiff", "flac": return .audio
        case "mov", "mp4", "m4v": return .video
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

    /// Whether a hover / inspector preview is meaningful without extracting to disk.
    var isPreviewable: Bool {
        switch self {
        case .image, .vector, .document, .text, .data, .font: true
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

    var id: String { path }
    var name: String { (path as NSString).lastPathComponent }
    var parent: String { (path as NSString).deletingLastPathComponent }
    /// App bundles are folders inside an archive, but they're one thing to the person.
    var kind: EntryKind {
        guard isFolder else { return EntryKind.infer(fromName: name) }
        return switch (name as NSString).pathExtension.lowercased() {
        case "app": .app
        case "pkg", "mpkg": .installer
        default: .folder
        }
    }

    var contentType: UTType {
        if kind == .app { return .applicationBundle }
        if isFolder { return .folder }
        return UTType(filenameExtension: (name as NSString).pathExtension) ?? .data
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
    private(set) var entries: [ArchiveEntry]
    /// Nil for sample data: there is nothing on disk to extract.
    var source: ArchiveSource?
    /// Disk images: the folder that stands for the volume ("" when the image lists its contents at
    /// the top), the window dressing left out (see `DiskImageLayout`), and "drag here" shortcuts.
    var volumeRoot = ""
    var installerExtras: [String] = []
    /// Stored paths of the AppleDouble files a Mac packed (`__MACOSX/…/._name`, `._name`).
    var appleDoublePaths: Set<String> = []
    var dropTargets: [DiskImageLayout.DropTarget] = []

    var isDiskImage: Bool { format == .dmg || format == .iso }

    /// Builds folder entries (with aggregated sizes) from a flat list of files,
    /// the same shape a real archive listing comes in.
    init(name: String, format: ArchiveFormat, isEncrypted: Bool = false,
         files: [ArchiveEntry], checkup: [CheckupFinding] = []) {
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
                parent = (parent as NSString).deletingLastPathComponent
            }
        }
        let folderEntries = folders.map { path, info in
            ArchiveEntry(path: path, isFolder: true, size: info.size,
                         packedSize: info.packed, modified: info.modified)
        }
        entries = folderEntries + files
    }

    var files: [ArchiveEntry] { entries.filter { !$0.isFolder } }
    var totalSize: Int64 { files.reduce(0) { $0 + $1.size } }
    var packedSize: Int64 { files.reduce(0) { $0 + $1.packedSize } }

    var hasCautions: Bool { checkup.contains { $0.severity == .caution } }

    func children(of folder: String) -> [ArchiveEntry] {
        entries
            .filter { $0.parent == folder }
            .sorted { lhs, rhs in
                if lhs.isFolder != rhs.isFolder { return lhs.isFolder }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    func entry(at path: String) -> ArchiveEntry? {
        entries.first { $0.path == path }
    }

    func search(_ query: String) -> [ArchiveEntry] {
        let terms = query.split(separator: " ").map(String.init)
        return entries
            .filter { entry in terms.allSatisfy { entry.name.localizedStandardContains($0) } }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func folderTree(under folder: String = "") -> [FolderNode] {
        children(of: folder)
            .filter(\.isFolder)
            .map { entry in
                let sub = folderTree(under: entry.path)
                return FolderNode(id: entry.path, name: entry.name, children: sub.isEmpty ? nil : sub)
            }
    }
}

nonisolated extension Int64 {
    var bytes: String { formatted(.byteCount(style: .file)) }
}
