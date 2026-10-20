import Foundation

nonisolated struct PackFile: Hashable, Sendable {
    var path: String
    var size: Int64
}

nonisolated enum Audience: String, CaseIterable, Identifiable, Sendable {
    case windows, mac, linux, web
    var id: Self { self }

    var phrase: String {
        switch self {
        case .windows: "Windows PCs"
        case .mac: "Macs"
        case .linux: "Linux & servers"
        case .web: "uploading to the web"
        }
    }

    var formats: [ArchiveFormat] {
        switch self {
        case .windows, .mac: [.zip, .sevenZip]
        case .linux: [.tarXz, .tarGz, .zip, .sevenZip]
        case .web: [.zip]
        }
    }

    var dropsMacHelperFiles: Bool { self != .mac }
    var normalizesNames: Bool { self == .windows || self == .web }
}

nonisolated enum SplitSize: Int64, CaseIterable, Identifiable, Sendable {
    case none = 0
    case mb100 = 100_000_000
    case mb700 = 700_000_000
    case fat32 = 4_000_000_000

    var id: Self { self }

    var phrase: String {
        switch self {
        case .none: "as one file"
        case .mb100: "in 100 MB parts"
        case .mb700: "in 700 MB parts"
        case .fat32: "in 4 GB parts"
        }
    }
}

nonisolated struct PackOptions: Equatable, Sendable {
    var audience: Audience = .windows
    var format: ArchiveFormat = .zip
    var usesPassword = false
    var split: SplitSize = .none

    /// Keeps format and password consistent when the audience changes.
    mutating func setAudience(_ newValue: Audience) {
        audience = newValue
        if !newValue.formats.contains(format) { format = newValue.formats[0] }
        if !format.supportsPassword { usesPassword = false }
    }

    mutating func setFormat(_ newValue: ArchiveFormat) {
        format = newValue
        if !newValue.supportsPassword { usesPassword = false }
    }
}

nonisolated struct PackReport: Equatable, Sendable {
    struct Rename: Equatable, Sendable { let from: String; let to: String }

    enum Tone: Sendable { case fine, info, caution }
    struct Note: Equatable, Sendable {
        let tone: Tone
        let title: String
        let detail: String
    }

    var included: [PackFile]
    var excluded: [PackFile]
    var renames: [Rename]
    var estimatedSize: Int64
    var parts: Int
    var notes: [Note]
}

nonisolated enum Compatibility {
    private static let reservedWindowsNames: Set<String> = {
        var names: Set<String> = ["CON", "PRN", "AUX", "NUL"]
        for n in 1...9 { names.insert("COM\(n)"); names.insert("LPT\(n)") }
        return names
    }()

    private static let invalidWindowsCharacters = CharacterSet(charactersIn: "<>:\"\\|?*")
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

    static func report(for files: [PackFile], options: PackOptions) -> PackReport {
        var included: [PackFile] = []
        var excluded: [PackFile] = []
        var renames: [PackReport.Rename] = []

        for file in files {
            if options.audience.dropsMacHelperFiles && isMacHelperFile(file.path) {
                excluded.append(file)
                continue
            }
            var output = file
            if options.audience.normalizesNames {
                let safe = windowsSafePath(file.path)
                // NFC-only changes are invisible to people; report only renames they'd notice.
                if safe != file.path.precomposedStringWithCanonicalMapping {
                    renames.append(.init(from: file.path, to: safe))
                }
                output.path = safe
            }
            included.append(output)
        }

        let raw = included.reduce(Int64(0)) { total, file in
            total + Int64(Double(file.size) * EntryKind.infer(fromName: file.path).typicalCompressionRatio)
        }
        let factor: Double = switch options.format {
        case .sevenZip: 0.9
        case .tarXz: 0.92
        default: 1.0
        }
        let estimated = Int64(Double(raw) * factor)
        let parts = options.split == .none ? 1 : max(1, Int((estimated + options.split.rawValue - 1) / options.split.rawValue))

        return PackReport(
            included: included,
            excluded: excluded,
            renames: renames,
            estimatedSize: estimated,
            parts: parts,
            notes: notes(for: options)
        )
    }

    private static func notes(for options: PackOptions) -> [PackReport.Note] {
        var notes: [PackReport.Note] = []
        switch (options.audience, options.format) {
        case (.windows, .zip) where options.usesPassword:
            notes.append(.init(
                tone: .caution,
                title: "File Explorer may not open it",
                detail: "Windows’ built-in ZIP support can’t always read AES-encrypted ZIPs. Suggest 7-Zip to the recipient."
            ))
        case (.windows, .sevenZip):
            notes.append(.init(
                tone: .info,
                title: "Recent Windows 11 opens 7Z",
                detail: "Older versions need 7-Zip. Choose ZIP if you’re not sure."
            ))
        case (.mac, _):
            notes.append(.init(
                tone: .fine,
                title: "Keeps everything a Mac cares about",
                detail: "Finder tags, extended attributes and permissions stay intact."
            ))
        case (.linux, _):
            notes.append(.init(
                tone: .fine,
                title: "Keeps permissions and symlinks",
                detail: "Executable bits and links survive, so scripts still run after extracting."
            ))
        default:
            break
        }
        if options.usesPassword {
            notes.append(.init(
                tone: .fine,
                title: options.format == .sevenZip ? "Contents and file names are encrypted" : "Contents are encrypted with AES-256",
                detail: options.format == .sevenZip
                    ? "Without the password, nobody can see what’s inside."
                    : "File names stay visible. Choose 7Z to hide them too."
            ))
        }
        return notes
    }
}
