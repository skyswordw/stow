import Foundation
import Synchronization

/// Serves one connection from Stow. Every byte of archive data is parsed here (by `7zz`, a child
/// process that inherits this sandbox), never in the app. Archives arrive as open descriptors; the
/// only place this process can write is its own container, so extractions land there until they're
/// streamed to Stow.
final class EngineService: NSObject, EngineXPCProtocol, Sendable {
    private let client: ClientProxy
    private let running = Mutex<[String: Task<Void, Never>]>([:])
    private let outputs = Mutex<[String: URL]>([:])

    init(connection: NSXPCConnection) {
        client = ClientProxy(connection.remoteObjectProxy as? EngineClientXPCProtocol)
    }

    /// Output left behind by a previous run that crashed or was killed.
    static func removeStaleOutputs() {
        let temporary = FileManager.default.temporaryDirectory
        let items = (try? FileManager.default.contentsOfDirectory(at: temporary, includingPropertiesForKeys: nil)) ?? []
        for item in items where [outputPrefix, packPrefix, packInputPrefix].contains(where: item.lastPathComponent.hasPrefix) {
            remove(item)
        }
    }

    /// Removes every output this connection still holds (the app went away).
    func invalidate() {
        let urls = outputs.withLock { outputs in
            defer { outputs.removeAll() }
            return Array(outputs.values)
        }
        running.withLock { $0.values.forEach { $0.cancel() } }
        urls.forEach { Self.remove($0) }
    }

    func handshake(clientVersion: Int, reply: @escaping @Sendable (Int) -> Void) {
        reply(EngineContract.version)
    }

    func listArchive(_ archive: FileHandle, named name: String, request: Data,
                     reply: @escaping @Sendable (Data?, NSError?) -> Void) {
        let archive = SendableHandle(archive)
        Task {
            do {
                let request = try Self.decode(ListRequest.self, from: request)
                let listing = try await Self.sevenZip().list(.descriptor(archive.handle, name: name),
                                                             password: request.password)
                reply(try JSONEncoder.engine.encode(listing), nil)
            } catch {
                reply(nil, EngineError(error).nsError)
            }
        }
    }

    func extract(_ archive: FileHandle, named name: String, request payload: Data,
                 reply: @escaping @Sendable (Data?, NSError?) -> Void) {
        let request: ExtractRequest
        do {
            request = try Self.decode(ExtractRequest.self, from: payload)
        } catch {
            reply(nil, EngineError(error).nsError)
            return
        }
        let archive = SendableHandle(archive)
        let id = request.operationID
        let output = FileManager.default.temporaryDirectory
            .appending(path: Self.outputPrefix + UUID().uuidString, directoryHint: .isDirectory)
        let client = client
        running.withLock { running in
            running[id] = Task {
                defer { _ = self.running.withLock { $0.removeValue(forKey: id) } }
                do {
                    if request.testOnly {
                        let type = name.lowercased().hasSuffix(".dmg") ? "dmg" : nil
                        try await Self.sevenZip().test(.descriptor(archive.handle, name: name), type: type,
                                                       password: request.password) {
                            client.progress(id, $0)
                        }
                        reply(try JSONEncoder.engine.encode(ExtractReport()), nil)
                        return
                    }
                    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
                    outputs.withLock { $0[id] = output }
                    let refused = try await Self.sevenZip().extract(
                        .descriptor(archive.handle, name: name), into: output, paths: request.paths,
                        password: request.password
                    ) { fraction in
                        client.progress(id, fraction)
                    }
                    try Task.checkCancellation()
                    let metadata = request.restoreMacMetadata ? AppleDouble.collect(in: output) : [:]
                    if request.excludeMacHelperFiles { MacHelperFiles.remove(in: output) }
                    let audit = try PathContainment.audit(staging: output)
                    let report = ExtractReport(removedLinks: refused + audit.removedLinks,
                                               removedItems: audit.removedItems, macMetadata: metadata)
                    reply(try JSONEncoder.engine.encode(report), nil)
                } catch {
                    self.discard(operation: id)
                    let error = error is CancellationError ? EngineError(.cancelled) : EngineError(error)
                    reply(nil, error.nsError)
                }
            }
        }
    }

    func create(from tree: FileHandle, request payload: Data, reply: @escaping @Sendable (Data?, NSError?) -> Void) {
        let request: CreateRequest
        do {
            request = try Self.decode(CreateRequest.self, from: payload)
        } catch {
            try? tree.close()
            reply(nil, EngineError(error).nsError)
            return
        }
        let tree = SendableHandle(tree)
        let id = request.operationID
        let temporary = FileManager.default.temporaryDirectory
        let output = temporary.appending(path: Self.packPrefix + UUID().uuidString, directoryHint: .isDirectory)
        let scratch = temporary.appending(path: Self.packInputPrefix + UUID().uuidString, directoryHint: .isDirectory)
        let input = scratch.appending(path: "Files", directoryHint: .isDirectory)
        let work = scratch.appending(path: "Work", directoryHint: .isDirectory)
        let client = client
        running.withLock { running in
            running[id] = Task {
                defer {
                    _ = self.running.withLock { $0.removeValue(forKey: id) }
                    Self.remove(scratch)
                }
                do {
                    for folder in [output, input, work] {
                        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    }
                    outputs.withLock { $0[id] = output }
                    try await Self.receive(tree, into: input)
                    try Task.checkCancellation()
                    let report = try await Self.sevenZip().create(request, from: input, into: output, work: work) {
                        client.progress(id, $0)
                    }
                    try Task.checkCancellation()
                    reply(try JSONEncoder.engine.encode(report), nil)
                } catch {
                    self.discard(operation: id)
                    let error = error is CancellationError || Task.isCancelled ? EngineError(.cancelled) : EngineError(error)
                    reply(nil, error.nsError)
                }
            }
        }
    }

    /// Blocking reads from Stow's pipe until it closes its end; off the cooperative pool.
    private static func receive(_ tree: SendableHandle, into folder: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                defer { try? tree.handle.close() }
                do {
                    try TreeStream.read(from: tree.handle.fileDescriptor, into: folder, flags: [.ignoreOperationNotPermitted])
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func send(operation: String, to stream: FileHandle, reply: @escaping @Sendable (NSError?) -> Void) {
        guard let output = outputs.withLock({ $0[operation] }) else {
            try? stream.close()
            reply(EngineError(.failed, "That extraction is no longer available.").nsError)
            return
        }
        let stream = SendableHandle(stream)
        // Blocking writes into a pipe: keep them off the cooperative pool.
        DispatchQueue.global(qos: .userInitiated).async {
            defer { try? stream.handle.close() }
            do {
                try TreeStream.write(output, to: stream.handle.fileDescriptor)
                reply(nil)
            } catch {
                reply(EngineError(error).nsError)
            }
        }
    }

    func discard(operation: String) {
        if let output = outputs.withLock({ $0.removeValue(forKey: operation) }) {
            Self.remove(output)
        }
    }

    func cancel(operation: String) {
        running.withLock { $0[operation] }?.cancel()
    }

    // MARK: -

    private static let outputPrefix = "Extract-"
    private static let packPrefix = "Pack-"
    private static let packInputPrefix = "PackIn-"

    /// Packed folders can arrive read-only (mode 555); make them writable so they can be emptied.
    private static func remove(_ url: URL) {
        let fileManager = FileManager.default
        if let walker = fileManager.enumerator(atPath: url.path) {
            for case let path as String in walker {
                let full = url.appending(path: path).path
                var info = stat()
                if lstat(full, &info) == 0, info.st_mode & S_IFMT == S_IFDIR { chmod(full, info.st_mode | 0o700) }
            }
        }
        try? fileManager.removeItem(at: url)
    }

    private static func sevenZip() throws(EngineError) -> SevenZip {
        guard let sevenZip = SevenZip.bundled() else { throw EngineError(.engineMissing) }
        return sevenZip
    }

    private struct Versioned: Decodable { var version: Int }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        guard let versioned = try? JSONDecoder.engine.decode(Versioned.self, from: data),
              versioned.version == EngineContract.version else {
            throw EngineError(.incompatibleVersion)
        }
        return try JSONDecoder.engine.decode(type, from: data)
    }
}

/// File handles are safe to pass between threads; the Objective-C type isn't annotated.
private struct SendableHandle: @unchecked Sendable {
    let handle: FileHandle
    init(_ handle: FileHandle) { self.handle = handle }
}

/// Remote proxies are thread-safe; the protocol type just isn't marked Sendable.
private final class ClientProxy: @unchecked Sendable {
    private let proxy: EngineClientXPCProtocol?

    init(_ proxy: EngineClientXPCProtocol?) { self.proxy = proxy }

    func progress(_ id: String, _ fraction: Double) {
        proxy?.operation(id, didProgress: fraction)
    }
}
