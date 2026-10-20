import Foundation

/// The XPC contract between Stow and its sandboxed archive engine (`StowEngine.xpc`).
///
/// The Objective-C surface stays tiny and stable; requests and replies travel as versioned JSON so
/// fields can be added without touching it. Bump `version` for any change an older peer can't read.
///
/// No file paths cross the boundary, only descriptors. Stow opens the archive and sends a read-only
/// `FileHandle`; the engine extracts into its own container (the only place it can write), audits
/// the result, and streams it back as an Apple Archive over a pipe Stow provides. The engine never
/// touches people's folders, and neither process reaches into the other's container.
nonisolated enum EngineContract {
    static let serviceName = "app.stow.Stow.Engine"
    static let version = 1
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

    /// Writes an extraction's output to `stream` as an uncompressed Apple Archive, closes it, replies.
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
}

nonisolated struct ArchiveListing: Codable, Sendable {
    var version = EngineContract.version
    /// 7-Zip's format name: "zip", "7z", "Rar5", "gzip", …
    var type: String
    var physicalSize: Int64?
    var entries: [ListedEntry]
}

nonisolated struct ExtractRequest: Codable, Sendable {
    var version = EngineContract.version
    var operationID: String
    /// Raw archive paths to extract (folders include their contents). Empty means everything.
    var paths: [String] = []
    var password: String?
    /// Leaves out `.DS_Store`, `._*` and `__MACOSX` — Checkup tells people they're hidden.
    var excludeMacHelperFiles = true
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
        case .incompatibleVersion: "Stow’s archive engine is out of date. Reinstall Stow."
        case .engineMissing: "Stow’s archive engine is missing. Reinstall Stow."
        case .connectionLost: "Stow’s archive engine stopped unexpectedly."
        case .notAnArchive: "This file isn’t an archive Stow can open."
        case .passwordRequired: "This archive needs a password."
        case .wrongPassword: "The password is incorrect."
        case .cancelled: "Cancelled."
        case .failed: "Something went wrong reading the archive."
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
