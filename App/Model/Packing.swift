import Foundation

/// A file, folder or link to pack. `path` starts with the name of the item people chose.
nonisolated struct PackFile: Hashable, Sendable {
    var path: String
    var size: Int64
    var isFolder = false
    var isLink = false
    /// Nil for sample data: there is nothing on disk to pack.
    var source: URL?
}

/// What people asked to pack: the items they chose, and everything inside them.
nonisolated struct PackRequest: Identifiable, Sendable {
    let id = UUID()
    var files: [PackFile]
    /// Names of the chosen items, as they appear at the top of the archive.
    var roots: [String]
    /// Where the chosen items live; the default place to save the archive. Nil for items from
    /// several folders with no remembered choice (`GatherDestination`): Save Here asks.
    var directory: URL?
    /// The chosen items on disk, so a Save Here choice for a mix can be remembered.
    var origins: [URL] = []
    var suggestedNameOverride: String?
    var cleanupDirectory: URL?
    /// When true, `cleanupDirectory` is removed only after a successful pack (Tray temporary
    /// groups, #179). Extract-and-repack keeps the default (also remove on cancel/failure).
    var cleanupOnlyOnSuccess = false
    var initialFormat: PackFormat?

    /// Sample files: roots are their top-level names.
    init(files: [PackFile]) {
        self.files = files
        var seen = Set<String>()
        roots = files.compactMap { $0.path.split(separator: "/").first.map(String.init) }.filter { seen.insert($0).inserted }
    }

    init(files: [PackFile], roots: [String], directory: URL?) {
        self.files = files
        self.roots = roots
        self.directory = directory
    }

    var isSample: Bool { files.allSatisfy { $0.source == nil } }

    /// "Project" for one folder, "Report" for one file, "Archive" for several (as Archive Utility does).
    var suggestedName: String {
        if let suggestedNameOverride { return suggestedNameOverride }
        guard roots.count == 1, let root = roots.first else { return "Archive" }
        let isFolder = files.first { $0.path == root }?.isFolder ?? files.contains { $0.path.hasPrefix(root + "/") }
        let stem = (root as NSString).deletingPathExtension
        return isFolder || stem.isEmpty ? root : stem
    }

    /// Walks the chosen items (without following links). Two items with the same name get numbered.
    @concurrent
    static func gather(_ urls: [URL]) async -> PackRequest {
        collect(urls)
    }

    static func collect(_ urls: [URL], remembered: URL? = GatherDestination.remembered()) -> PackRequest {
        var files: [PackFile] = []
        var roots: [String] = []
        var taken = Set<String>()
        for url in urls {
            var name = url.lastPathComponent
            var attempt = 1
            while !taken.insert(name.lowercased()).inserted {
                attempt += 1
                name = Compatibility.numbered(url.lastPathComponent, attempt)
            }
            roots.append(name)
            guard let root = file(at: url, path: name) else { continue }
            files.append(root)
            guard root.isFolder else { continue }
            let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
            guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) else { continue }
            let base = url.standardizedFileURL.path
            for case let child as URL in walker {
                let relative = String(child.standardizedFileURL.path.dropFirst(base.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if let file = file(at: child, path: name + "/" + relative) { files.append(file) }
            }
        }
        var request = PackRequest(files: files, roots: roots, directory: GatherDestination.suggestion(for: urls, remembered: remembered))
        request.origins = urls
        return request
    }

    private static func file(at url: URL, path: String) -> PackFile? {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]) else {
            return nil
        }
        let isLink = values.isSymbolicLink ?? false
        return PackFile(path: path, size: Int64(values.fileSize ?? 0), isFolder: !isLink && (values.isDirectory ?? false),
                        isLink: isLink, source: url)
    }
}

nonisolated enum Audience: String, CaseIterable, Identifiable, Sendable {
    case windows, mac, linux, web
    var id: Self { self }

    var phrase: String {
        switch self {
        case .windows: String(localized: "Windows PCs")
        case .mac: String(localized: "Macs")
        case .linux: String(localized: "Linux & servers")
        case .web: String(localized: "uploading to the web")
        }
    }

    var formats: [PackFormat] {
        switch self {
        case .windows: [.zip, .sevenZip]
        case .mac: [.zip, .sevenZip, .dmg]
        case .linux: [.tarXz, .tarGz, .tarZst, .tarBz2, .tar, .zip, .sevenZip]
        case .web: [.zip]
        }
    }

    var dropsMacHelperFiles: Bool { self != .mac }
    /// Windows-safe characters and reserved names.
    var normalizesNames: Bool { self == .windows || self == .web }
    /// Precomposed (NFC) names, which is what everything but a Mac expects.
    var composesNames: Bool { self != .mac }
    /// Links stay links. Elsewhere they can't be recreated, so they're left out.
    var keepsLinks: Bool { self == .mac || self == .linux }
    /// Extended attributes travel as AppleDouble files (ZIP).
    var keepsMacMetadata: Bool { self == .mac }
    var hasCaseInsensitiveNames: Bool { self != .linux }
}

/// How large each volume of a split archive should be (#151).
///
/// Presets cover common media limits; any other positive byte count is a custom size
/// (Settings and Pack both persist the raw byte value under `PackVolumeSize`).
nonisolated struct SplitSize: Hashable, Identifiable, Sendable {
    /// Volume size in bytes. Zero means the archive stays one file.
    var rawValue: Int64

    var id: Int64 { rawValue }

    static let none = SplitSize(rawValue: 0)
    static let mb100 = SplitSize(rawValue: 100_000_000)
    static let mb500 = SplitSize(rawValue: 500_000_000)
    static let mb700 = SplitSize(rawValue: 700_000_000)
    static let gb1 = SplitSize(rawValue: 1_000_000_000)
    static let fat32 = SplitSize(rawValue: 4_000_000_000)

    /// Menu and Settings picker choices (presets only). Custom sizes are chosen separately.
    static let allCases: [SplitSize] = [.none, .mb100, .mb500, .mb700, .gb1, .fat32]

    /// Smallest custom volume the engine accepts (1 KB keeps parts usable).
    static let minimumCustomBytes: Int64 = 1_024
    /// Soft upper bound so a typo cannot ask for multi-petabyte volumes.
    static let maximumCustomBytes: Int64 = 100_000_000_000_000

    var isNone: Bool { rawValue == 0 }
    var isPreset: Bool { Self.allCases.contains(self) }
    var isCustom: Bool { rawValue > 0 && !isPreset }

    /// Builds a size from a stored preference. Unknown positive values become custom; ≤0 → none.
    static func stored(_ value: Int64) -> SplitSize {
        guard value > 0 else { return .none }
        return SplitSize(rawValue: value)
    }

    /// Validated custom size, or `nil` when out of range.
    static func custom(_ bytes: Int64) -> SplitSize? {
        guard bytes >= minimumCustomBytes, bytes <= maximumCustomBytes else { return nil }
        return SplitSize(rawValue: bytes)
    }

    /// Parses a human size such as "250", "1.5", with a unit of MB or GB (decimal).
    static func parseCustom(_ text: String, unit: CustomUnit) -> SplitSize? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let amount = Double(trimmed), amount.isFinite, amount > 0 else { return nil }
        let bytes = Int64((amount * Double(unit.bytes)).rounded())
        return custom(bytes)
    }

    enum CustomUnit: String, CaseIterable, Identifiable, Sendable {
        case megabyte, gigabyte
        var id: Self { self }
        var bytes: Int64 {
            switch self {
            case .megabyte: 1_000_000
            case .gigabyte: 1_000_000_000
            }
        }
        var symbol: String {
            switch self {
            case .megabyte: "MB"
            case .gigabyte: "GB"
            }
        }
    }

    var phrase: String {
        switch rawValue {
        case 0: String(localized: "as one file")
        case 100_000_000: String(localized: "in 100 MB parts")
        case 500_000_000: String(localized: "in 500 MB parts")
        case 700_000_000: String(localized: "in 700 MB parts")
        case 1_000_000_000: String(localized: "in 1 GB parts")
        case 4_000_000_000: String(localized: "in 4 GB parts")
        default:
            String(localized: "in \(Self.formatBytes(rawValue)) parts")
        }
    }

    /// Compact decimal label for custom sizes ("250 MB", "1.5 GB").
    static func formatBytes(_ bytes: Int64) -> String {
        if bytes >= 1_000_000_000 {
            let gb = Double(bytes) / 1_000_000_000
            if gb == floor(gb) { return String(format: "%.0f GB", gb) }
            return String(format: "%g GB", (gb * 100).rounded() / 100)
        }
        let mb = Double(bytes) / 1_000_000
        if mb == floor(mb) { return String(format: "%.0f MB", mb) }
        return String(format: "%g MB", (mb * 100).rounded() / 100)
    }
}

nonisolated extension PackFormat {
    var displayName: String {
        switch self {
        case .zip: "ZIP"
        case .sevenZip: "7Z"
        case .tar: "TAR"
        case .tarGz: "TAR.GZ"
        case .tarBz2: "TAR.BZ2"
        case .tarXz: "TAR.XZ"
        case .tarZst: "TAR.ZST"
        case .dmg: "DMG"
        }
    }
}

nonisolated extension CompressionLevel {
    var title: String {
        switch self {
        case .store: String(localized: "Store")
        case .fastest: String(localized: "Fastest")
        case .fast: String(localized: "Fast")
        case .balanced: String(localized: "Balanced")
        case .maximum: String(localized: "Maximum")
        case .smallest: String(localized: "Smallest")
        }
    }

    var detail: String {
        switch self {
        case .store: String(localized: "No compression — quickest, largest.")
        case .fastest: String(localized: "Light compression, very quick.")
        case .fast: String(localized: "Good compression, quick.")
        case .balanced: String(localized: "Smaller files at a good speed.")
        case .maximum: String(localized: "Smaller still, noticeably slower.")
        case .smallest: String(localized: "Smallest files, slowest.")
        }
    }

    /// Packed size relative to Balanced, for estimates.
    var sizeFactor: Double {
        switch self {
        case .store: 1
        case .fastest: 1.1
        case .fast: 1.04
        case .balanced: 1
        case .maximum: 0.97
        case .smallest: 0.95
        }
    }
}

nonisolated struct PackOptions: Equatable, Sendable {
    var audience: Audience = .windows
    var format: PackFormat = .zip
    var usesPassword = false
    var split: SplitSize = .none
    var level: CompressionLevel = .balanced
    var verify = false
    /// DMG only (#77). HFS+ hybrid by default; APFS when the system allows.
    var diskImageFilesystem: DiskImageFilesystem = .hfsPlus
    /// DMG only (#77). Adds an Applications → /Applications shortcut.
    var diskImageApplicationsLink = false
    /// DMG only (#85). Writes Finder layout into staging without mounting.
    var diskImageFinderChrome = false

    /// Per-job Mac helper-file policy (#152). `nil` follows the audience default.
    var includeMacHelperFiles: Bool? = nil
    /// Per-job AppleDouble metadata for ZIP (#152). `nil` follows the audience default.
    var keepsMacMetadata: Bool? = nil
    /// 7Z + password: encrypt the file list (`-mhe`). Default on; ignored for other formats.
    var encryptFilenames = true
    /// Per-job compression thread cap (#152). `nil` uses Settings › PackCPUCores.
    var threads: Int? = nil

    /// Effective helper-drop policy for this job.
    var dropsMacHelperFiles: Bool {
        if let includeMacHelperFiles { return !includeMacHelperFiles }
        return audience.dropsMacHelperFiles
    }

    /// Effective ZIP AppleDouble policy for this job (only meaningful for ZIP).
    var effectiveKeepsMacMetadata: Bool {
        let wants = keepsMacMetadata ?? audience.keepsMacMetadata
        return wants && format == .zip
    }

    /// Effective thread count for CreateRequest (`nil` = all cores / engine default).
    /// Pass `PackPreferences.threads` (or a test double) as `global` — that preference is MainActor-isolated.
    func effectiveThreads(global: Int?) -> Int? {
        guard let threads else { return global }
        let cap = max(1, ProcessInfo.processInfo.activeProcessorCount)
        return min(max(1, threads), cap)
    }

    /// Restores purpose-driven defaults for the current audience/format without clearing format itself.
    /// Reads remembered Pack/Settings defaults on the main actor.
    @MainActor
    mutating func resetToPurposeDefaults() {
        includeMacHelperFiles = nil
        keepsMacMetadata = nil
        encryptFilenames = true
        threads = nil
        level = PackPreferences.level(for: audience)
        verify = PackPreferences.verify
        split = format.supportsSplit ? SettingsKeys.splitSize() : .none
        diskImageFilesystem = .hfsPlus
        diskImageApplicationsLink = false
        diskImageFinderChrome = false
    }

    /// Keeps format and password consistent when the audience changes.
    mutating func setAudience(_ newValue: Audience) {
        audience = newValue
        if !newValue.formats.contains(format) { format = newValue.formats[0] }
        reconcileCapabilities()
    }

    mutating func setFormat(_ newValue: PackFormat) {
        format = newValue
        reconcileCapabilities()
    }

    /// Clears options the current format cannot honour, without silently turning encryption off.
    mutating func reconcileCapabilities() {
        if !format.supportsPassword { usesPassword = false }
        if !format.supportsSplit { split = .none }
        if format != .dmg {
            diskImageFilesystem = .hfsPlus
            diskImageApplicationsLink = false
            diskImageFinderChrome = false
        }
        if format != .zip { keepsMacMetadata = nil }
        // encryptFilenames is only applied for password-protected 7Z; keep the preference for when
        // people switch back so we never silently downgrade encryption.
    }
}

nonisolated struct PackReport: Equatable, Sendable {
    /// An item whose own name changes. `path` is where it sits in the original tree.
    struct Rename: Equatable, Identifiable, Sendable {
        let path: String
        let from: String
        /// What Stow would choose; `to` differs when people edited it (or it was numbered).
        let suggested: String
        let to: String
        var id: String { path }
    }

    enum Tone: Sendable { case fine, info, caution }
    struct Note: Equatable, Sendable {
        let tone: Tone
        let title: String
        let detail: String
    }

    /// Everything that goes in, under its archive path.
    var included: [PackFile]
    /// Mac helper files left out.
    var excluded: [PackFile]
    /// Links the audience can't recreate.
    var leftOutLinks: [PackFile]
    var renames: [Rename]
    var estimatedSize: Int64
    var parts: Int
    var notes: [Note]

    var fileCount: Int { included.count { !$0.isFolder } }
    /// File data to hand over, for progress.
    var totalBytes: Int64 { included.reduce(0) { $0 + ($1.isFolder || $1.isLink ? 0 : $1.size) } }

    /// What to stream to the engine.
    var items: [TreeStream.Item] {
        included.compactMap { file in file.source.map { TreeStream.Item(source: $0, path: file.path) } }
    }
}

nonisolated enum Compatibility {
    private static let reservedWindowsNames: Set<String> = {
        var names: Set<String> = ["CON", "PRN", "AUX", "NUL"]
        for n in 1...9 { names.insert("COM\(n)"); names.insert("LPT\(n)") }
        return names
    }()

    private static let invalidWindowsCharacters = CharacterSet(charactersIn: "<>:\"\\|?*/")
        .union(CharacterSet(charactersIn: Unicode.Scalar(UInt8(0))...Unicode.Scalar(UInt8(0x1F))))

    /// Finder metadata and AppleDouble files that mean nothing off a Mac.
    static func isMacHelperFile(_ path: String) -> Bool {
        MacHelperFiles.matches(path)
    }

    /// A single path component made safe for Windows, or the same string if it already is.
    static func windowsSafeComponent(_ component: String) -> String {
        var name = component.precomposedStringWithCanonicalMapping
        name = String(name.unicodeScalars.map { invalidWindowsCharacters.contains($0) ? "-" : Character($0) })

        while let last = name.last, last == "." || last == " " { name.removeLast() }
        if name.isEmpty { name = "_" }

        let stem = name.split(separator: ".", maxSplits: 1).first.map(String.init) ?? name
        if reservedWindowsNames.contains(stem.uppercased()) { name = "_" + name }
        return name
    }

    static func windowsSafePath(_ path: String) -> String {
        path.split(separator: "/", omittingEmptySubsequences: false)
            .map { windowsSafeComponent(String($0)) }
            .joined(separator: "/")
    }

    /// How one name looks for `audience`.
    static func component(_ name: String, for audience: Audience) -> String {
        if audience.normalizesNames { return windowsSafeComponent(name) }
        let composed = audience.composesNames ? name.precomposedStringWithCanonicalMapping : name
        let clean = composed.replacingOccurrences(of: "/", with: "-")
        return clean.isEmpty ? "_" : clean
    }

    /// The archive's own file name (without extension).
    static func archiveName(_ name: String, for audience: Audience) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "Archive" }
        return component(trimmed, for: audience).replacingOccurrences(of: ":", with: "-")
    }

    /// "Report.pdf" → "Report 2.pdf"; folders and extensionless names just get the number.
    static func numbered(_ name: String, _ attempt: Int) -> String {
        guard attempt > 1 else { return name }
        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        return ext.isEmpty || stem.isEmpty ? "\(name) \(attempt)" : "\(stem) \(attempt).\(ext)"
    }

    /// `overrides`: names people typed, by original path.
    static func report(for files: [PackFile], options: PackOptions, password: String = "",
                       overrides: [String: String] = [:]) -> PackReport {
        let audience = options.audience
        var excluded: [PackFile] = []
        var leftOutLinks: [PackFile] = []
        var kept: [PackFile] = []

        for file in files {
            if options.dropsMacHelperFiles, isUnderHelperFile(file.path) {
                if !file.isFolder { excluded.append(file) }
            } else if file.isLink, !audience.keepsLinks {
                leftOutLinks.append(file)
            } else {
                kept.append(file)
            }
        }

        // Parents before children, so a folder's new name is settled before anything inside it.
        var mapped: [String: String] = [:]
        var owners: [String: String] = [:]
        var renames: [PackReport.Rename] = []
        func key(_ path: String) -> String { audience.hasCaseInsensitiveNames ? path.lowercased() : path }
        func output(for original: String) -> String {
            if let known = mapped[original] { return known }
            let parent = (original as NSString).deletingLastPathComponent
            let prefix = parent.isEmpty ? "" : output(for: parent) + "/"
            let name = (original as NSString).lastPathComponent
            let suggested = component(name, for: audience)
            let typed = overrides[original].map { component($0.trimmingCharacters(in: .whitespaces), for: audience) }
            let wanted = typed.flatMap { $0 == "_" ? nil : $0 } ?? suggested
            var candidate = wanted
            var attempt = 1
            while let owner = owners[key(prefix + candidate)], owner != original {
                attempt += 1
                candidate = numbered(wanted, attempt)
            }
            owners[key(prefix + candidate)] = original
            mapped[original] = prefix + candidate
            if candidate.precomposedStringWithCanonicalMapping != name.precomposedStringWithCanonicalMapping {
                renames.append(.init(path: original, from: name, suggested: suggested, to: candidate))
            }
            return prefix + candidate
        }

        let included = kept.sorted { $0.path < $1.path }.map { file in
            var entry = file
            entry.path = output(for: file.path)
            return entry
        }

        let raw = included.reduce(Int64(0)) { total, file in
            guard !file.isFolder, !file.isLink else { return total }
            let ratio = options.format.isCompressed && options.level != .store
                ? EntryKind.infer(fromName: file.path).typicalCompressionRatio * options.level.sizeFactor
                : 1
            return total + Int64(Double(file.size) * min(1, ratio))
        }
        let factor: Double = switch options.format {
        case .sevenZip: 0.9
        case .tarXz: 0.92
        case .tarBz2: 0.96
        case .tarZst: 0.98
        default: 1.0
        }
        let estimated = Int64(Double(raw) * (options.level == .store ? 1 : factor))
        let parts = options.split == .none ? 1 : max(1, Int((estimated + options.split.rawValue - 1) / options.split.rawValue))

        return PackReport(
            included: included,
            excluded: excluded,
            leftOutLinks: leftOutLinks,
            renames: renames,
            estimatedSize: estimated,
            parts: parts,
            notes: notes(for: options, password: password)
        )
    }

    /// The file itself, or a folder around it, is Mac-only (`__MACOSX/…`, `.Trashes/…`).
    private static func isUnderHelperFile(_ path: String) -> Bool {
        var prefix = ""
        for component in path.split(separator: "/") {
            prefix = prefix.isEmpty ? String(component) : prefix + "/" + component
            if isMacHelperFile(prefix) { return true }
        }
        return false
    }

    /// ZIP's AES passwords are bytes; apps disagree on how to encode anything beyond ASCII.
    static func passwordIsPortable(_ password: String) -> Bool {
        password.unicodeScalars.allSatisfy { $0.isASCII && $0.value >= 0x20 }
    }

    private static func notes(for options: PackOptions, password: String) -> [PackReport.Note] {
        var notes: [PackReport.Note] = []
        switch (options.audience, options.format) {
        case (.windows, .zip) where options.usesPassword:
            notes.append(.init(
                tone: .caution,
                title: String(localized: "File Explorer may not open it"),
                detail: String(localized: "Windows’ built-in ZIP support can’t always read AES-encrypted ZIPs. Suggest 7-Zip to the recipient.")
            ))
        case (.windows, .sevenZip):
            notes.append(.init(
                tone: .info,
                title: String(localized: "Recent Windows 11 opens 7Z"),
                detail: String(localized: "Older versions need 7-Zip. Choose ZIP if you’re not sure.")
            ))
        case (.mac, .dmg):
            notes.append(.init(
                tone: .info,
                title: String(localized: "Opens like a disk on any Mac"),
                detail: String(localized: "Double-clicking it shows the files in Finder; permissions and links stay. Windows and Linux need an extra app to open it.")
            ))
            if options.diskImageFilesystem == .apfs {
                notes.append(.init(
                    tone: .info,
                    title: String(localized: "APFS when the system allows"),
                    detail: String(localized: "Falls back to HFS+ if making an APFS image isn’t possible here (for example in the App Sandbox).")
                ))
            }
            if options.diskImageFinderChrome {
                notes.append(.init(
                    tone: .info,
                    title: String(localized: "Finder window layout"),
                    detail: String(localized: "Adds icon positions, a solid window background, and a volume icon when an app icon is available, without mounting. Stow hides these extras when browsing.")
                ))
            }
            if options.diskImageApplicationsLink {
                notes.append(.init(
                    tone: .fine,
                    title: String(localized: "Includes an Applications shortcut"),
                    detail: String(localized: "People can drag apps onto it in Finder. Stow hides the shortcut when browsing and offers install into /Applications.")
                ))
            }
        case (.mac, .zip):
            notes.append(.init(
                tone: .fine,
                title: String(localized: "Keeps everything a Mac cares about"),
                detail: String(localized: "Finder tags, extended attributes, permissions and links stay intact.")
            ))
        case (.mac, _):
            notes.append(.init(
                tone: .info,
                title: String(localized: "Keeps permissions and links"),
                detail: String(localized: "Finder tags and other extended attributes only travel in a ZIP.")
            ))
        case (.linux, _):
            notes.append(.init(
                tone: .fine,
                title: String(localized: "Keeps permissions and symlinks"),
                detail: String(localized: "Executable bits and links survive, so scripts still run after extracting.")
            ))
        default:
            break
        }
        if options.format == .tarZst {
            notes.append(.init(
                tone: .info,
                title: String(localized: "Needs a recent tar to open"),
                detail: String(localized: "Current Linux and macOS open TAR.ZST with tar. Older systems and Windows need zstd or 7-Zip.")
            ))
        }
        if options.usesPassword {
            if options.format == .zip, !passwordIsPortable(password) {
                notes.append(.init(
                    tone: .caution,
                    title: String(localized: "Use plain letters and numbers for a ZIP password"),
                    detail: String(localized: "Apps disagree on accented and non-Latin characters in ZIP passwords. Choose 7Z to keep this one.")
                ))
            }
            if options.format == .sevenZip {
                if options.encryptFilenames {
                    notes.append(.init(
                        tone: .fine,
                        title: String(localized: "Contents and file names are encrypted"),
                        detail: String(localized: "Without the password, nobody can see what’s inside.")
                    ))
                } else {
                    notes.append(.init(
                        tone: .info,
                        title: String(localized: "Contents are encrypted; file names stay visible"),
                        detail: String(localized: "Anyone can see the list of files. Turn on Encrypt File Names to hide them.")
                    ))
                }
            } else {
                notes.append(.init(
                    tone: .fine,
                    title: String(localized: "Contents are encrypted with AES-256"),
                    detail: String(localized: "File names stay visible. Choose 7Z to hide them too.")
                ))
            }
        }
        return notes
    }
}
