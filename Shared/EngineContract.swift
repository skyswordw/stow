import Foundation

/// The XPC contract between Stow and its sandboxed archive engine (`StowEngine.xpc`).
///
/// The Objective-C surface stays tiny and stable; requests and replies travel as versioned JSON so
/// fields can be added without touching it. Bump `version` for any change an older peer can't read.
///
/// No file paths cross the boundary, only descriptors. Stow opens the archive and sends a read-only
/// `FileHandle`; the engine extracts into its own container (the only place it can write), audits
/// the result, and streams it back as an Apple Archive over a pipe Stow provides. Creating works the
/// same way in reverse: Stow streams the files to pack as an Apple Archive, the engine compresses them
/// in its container and streams the finished archive back. The engine never touches people's folders,
/// and neither process reaches into the other's container.
nonisolated enum EngineContract {
    static let serviceName = "app.stow.Stow.Engine"
    /// 2: `create`.
    /// 3: `edit`, `sendFile`.
    static let version = 4
}

@objc(StowEngineProtocol)
nonisolated protocol EngineXPCProtocol {
    /// Replies with the engine's contract version; the client refuses to talk to a mismatch.
    func handshake(clientVersion: Int, reply: @escaping @Sendable (Int) -> Void)

    /// `name` is the archive's file name, a hint for format detection. `request`: JSON `ListRequest`.
    /// Replies with JSON `ArchiveListing`.
    func listArchive(_ archive: FileHandle, named name: String, request: Data,
                     reply: @escaping @Sendable (Data?, NSError?) -> Void)

    /// Extracts inside the engine and audits the result. `request`: JSON `ExtractRequest`. Replies
    /// with JSON `ExtractReport`; progress goes to the connection's `EngineClientXPCProtocol`. The
    /// output stays in the engine until `send` streams it or `discard` drops it.
    func extract(_ archive: FileHandle, named name: String, request: Data,
                 reply: @escaping @Sendable (Data?, NSError?) -> Void)

    /// Reads the files to pack from `tree` (an Apple Archive, as `TreeStream.write(_:to:)` sends it) and
    /// compresses them. `request`: JSON `CreateRequest`. Replies with JSON `CreateReport`; progress goes
    /// to the connection's `EngineClientXPCProtocol`. The archive stays in the engine until `send`
    /// streams it or `discard` drops it.
    func create(from tree: FileHandle, request: Data, reply: @escaping @Sendable (Data?, NSError?) -> Void)

    func edit(_ archive: FileHandle, named name: String, tree: FileHandle?, request: Data,
              reply: @escaping @Sendable (Data?, NSError?) -> Void)

    /// Writes an edited archive's raw bytes to the app's replacement descriptor, then removes it.
    func sendFile(operation: String, to destination: FileHandle, reply: @escaping @Sendable (NSError?) -> Void)

    /// Writes an extraction's (or creation's) output to `stream` as an uncompressed Apple Archive, closes it, replies.
    func send(operation: String, to stream: FileHandle, reply: @escaping @Sendable (NSError?) -> Void)

    /// Deletes an extraction's output.
    func discard(operation: String)

    /// Stops a running extraction; its reply arrives with `EngineFailure.cancelled`.
    func cancel(operation: String)
}

/// Exported by the app on the same connection so the engine can report progress.
@objc(StowEngineClientProtocol)
nonisolated protocol EngineClientXPCProtocol {
    func operation(_ id: String, didProgress fraction: Double)
}

// MARK: - Payloads

nonisolated struct ListRequest: Codable, Sendable {
    var version = EngineContract.version
    var password: String?
}

nonisolated struct ListedEntry: Codable, Hashable, Sendable {
    /// Exactly as stored in the archive — may be hostile (`../../x`, `/etc/x`).
    var path: String
    var isFolder: Bool
    var isSymlink: Bool = false
    var linkTarget: String?
    var size: Int64
    /// Missing for files that share a solid block with an earlier file.
    var packedSize: Int64?
    var modified: Date?
    var isEncrypted: Bool = false
    /// The stored name's bytes, when the archive doesn't say how they're encoded (ZIP entries
    /// without the UTF-8 flag whose names aren't ASCII). `path` is then 7-Zip's lossy reading of
    /// them — still the name to ask for when extracting — and Stow decodes these bytes for display.
    var rawPath: Data?
}

nonisolated struct ArchiveListing: Codable, Sendable {
    var version = EngineContract.version
    /// 7-Zip's format name: "zip", "7z", "Rar5", "gzip", …
    var type: String
    var physicalSize: Int64?
    var entries: [ListedEntry]
    /// Bytes before the archive starts: a self-extracting stub or other prepended data.
    var startOffset: Int64? = nil
    /// Bytes after the archive ends that aren't part of it.
    var tailSize: Int64? = nil
}

nonisolated struct ExtractRequest: Codable, Sendable {
    var version = EngineContract.version
    var operationID: String
    /// Raw archive paths to extract (folders include their contents). Empty means everything.
    var paths: [String] = []
    var password: String?
    /// Leaves out `.DS_Store`, `._*` and `__MACOSX` — Checkup tells people they're hidden.
    var excludeMacHelperFiles = true
    /// Only checks the archive's data against its checksums (`7zz t`); nothing is kept.
    var testOnly = false
    /// Reads Mac AppleDouble companions (`__MACOSX/…/._name`) into `ExtractReport.macMetadata`.
    var restoreMacMetadata = false
}

/// A symbolic link that would have pointed outside the destination. It is not created.
nonisolated struct RemovedLink: Codable, Hashable, Sendable {
    var path: String
    var target: String
}

nonisolated struct ExtractReport: Codable, Sendable {
    var version = EngineContract.version
    var removedLinks: [RemovedLink] = []
    /// Anything that escaped the staging folder some other way and was removed.
    var removedItems: [String] = []
    /// Relative path → extended attributes from the archive's AppleDouble files (Finder tags,
    /// comments, Finder info, resource forks), for Stow to put back. Quarantine never included.
    var macMetadata: [String: [String: Data]] = [:]
}

/// What `create` can write. Compressed TARs are a TAR compressed as a second step. DMG is made by
/// Stow itself with `hdiutil` (`DiskImageCreation`), not by the engine.
nonisolated enum PackFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case zip, sevenZip, tar, tarGz, tarBz2, tarXz, tarZst, dmg

    var id: Self { self }

    var fileExtension: String {
        switch self {
        case .zip: "zip"
        case .sevenZip: "7z"
        case .tar: "tar"
        case .tarGz: "tar.gz"
        case .tarBz2: "tar.bz2"
        case .tarXz: "tar.xz"
        case .tarZst: "tar.zst"
        case .dmg: "dmg"
        }
    }

    /// ZIP and 7Z. DMG AES packing is deferred (#77): MediaKit attach is blocked in the App Sandbox.
    var supportsPassword: Bool { self == .zip || self == .sevenZip }
    var isCompressed: Bool { self != .tar }
    /// A disk image is always one file.
    var supportsSplit: Bool { self != .dmg }
}

/// 7-Zip's `-mx` levels under names people understand.
nonisolated enum CompressionLevel: Int, Codable, CaseIterable, Identifiable, Sendable {
    case store = 0, fastest = 1, fast = 3, balanced = 5, maximum = 7, smallest = 9

    var id: Self { self }
}

/// File system for Pack › DMG (#77). Default keeps the HFS+ hybrid path from #23.
nonisolated enum DiskImageFilesystem: String, Codable, CaseIterable, Identifiable, Sendable {
    case hfsPlus
    case apfs

    var id: Self { self }

    var title: String {
        switch self {
        case .hfsPlus: "HFS+"
        case .apfs: "APFS"
        }
    }

    var detail: String {
        switch self {
        case .hfsPlus:
            String(localized: "Works on every Mac. Made without mounting, so it works in the sandbox.")
        case .apfs:
            String(localized: "Modern Macs. Falls back to HFS+ if the system can’t make an APFS image here.")
        }
    }
}

nonisolated struct CreateRequest: Codable, Sendable {
    var version = EngineContract.version
    var operationID: String
    /// The archive's name without extension, e.g. "Project". Stow names the file it places itself.
    var archiveName: String
    var format: PackFormat
    var level: CompressionLevel = .balanced
    /// ZIP: AES-256. 7Z: AES-256 with file names encrypted too. DMG ignores this (password packing deferred).
    var password: String?
    /// Bytes per volume; nil for one file.
    var volumeSize: Int64?
    /// Adds `__MACOSX/…/._name` AppleDouble files carrying extended attributes (ZIP only).
    var keepsMacMetadata = false
    /// Tests the finished archive before replying.
    var verify = false
    /// Compression threads; nil lets 7-Zip use every core.
    var threads: Int?
    /// DMG only (#77). Default is the HFS+ hybrid path from #23.
    var diskImageFilesystem: DiskImageFilesystem = .hfsPlus
    /// DMG only (#77). Adds `Applications → /Applications` for drag-to-install.
    var diskImageApplicationsLink = false
}

nonisolated struct CreateReport: Codable, Sendable {
    var version = EngineContract.version
    /// The archive's file names, in order — several for split volumes.
    var files: [String]
    var size: Int64
    var verified = false
}

// MARK: - Errors

nonisolated enum EngineFailure: Int, Sendable {
    case incompatibleVersion = 1
    case engineMissing
    case connectionLost
    case notAnArchive
    case passwordRequired
    case wrongPassword
    case cancelled
    case failed
    case changedOnDisk
}

nonisolated struct EngineError: LocalizedError, Sendable, Equatable {
    static let domain = "app.stow.engine"

    let failure: EngineFailure
    let message: String

    init(_ failure: EngineFailure, _ message: String? = nil) {
        self.failure = failure
        self.message = message ?? Self.defaultMessage(for: failure)
    }

    init(_ error: any Error) {
        if let error = error as? EngineError {
            self = error
            return
        }
        let error = error as NSError
        if error.domain == Self.domain, let failure = EngineFailure(rawValue: error.code) {
            self.init(failure, error.localizedDescription)
        } else if error.domain == NSCocoaErrorDomain, error.code == NSUserCancelledError {
            self.init(.cancelled)
        } else {
            self.init(.failed, error.localizedDescription)
        }
    }

    var errorDescription: String? { message }

    var nsError: NSError {
        NSError(domain: Self.domain, code: failure.rawValue,
                userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func defaultMessage(for failure: EngineFailure) -> String {
        switch failure {
        case .incompatibleVersion: String(localized: "Stow’s archive engine is out of date. Reinstall Stow.")
        case .engineMissing: String(localized: "Stow’s archive engine is missing. Reinstall Stow.")
        case .connectionLost: String(localized: "Stow’s archive engine stopped unexpectedly.")
        case .notAnArchive: String(localized: "This file isn’t an archive Stow can open.")
        case .passwordRequired: String(localized: "This archive needs a password.")
        case .wrongPassword: String(localized: "The password is incorrect.")
        case .cancelled: String(localized: "Cancelled.")
        case .changedOnDisk: String(localized: "The archive changed on disk. Reload it or save a copy.")
        case .failed: String(localized: "Something went wrong reading the archive.")
        }
    }
}

extension JSONEncoder {
    nonisolated static var engine: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }
}

extension JSONDecoder {
    nonisolated static var engine: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
