import Foundation
import Synchronization

/// Stow's side of the connection to `StowEngine.xpc`. Every archive is parsed over there, in its
/// own sandbox; this side only sends URLs and reads back plain values.
final class ArchiveEngine {
    static let shared = ArchiveEngine()

    private var connection: NSXPCConnection?
    private var isVerified = false
    private let progress = ProgressRouter()

    func list(_ archive: URL, password: String? = nil) async throws(EngineError) -> ArchiveListing {
        let request = try encode(ListRequest(password: password))
        let handle = try Self.open(archive)
        defer { try? handle.close() }
        let reply = try await call { proxy, reply in
            proxy.listArchive(handle, named: archive.lastPathComponent, request: request, reply: reply)
        }
        return try decode(ArchiveListing.self, from: reply)
    }

    /// An extraction waiting inside the engine: `receive` it, then `discard` it.
    struct Output: Sendable {
        let operationID: String
        let report: ExtractReport
    }

    /// Extracts (and audits) inside the engine. Cancelling the task stops 7-Zip.
    func extract(_ archive: URL, paths: [String], password: String? = nil, excludeMacHelperFiles: Bool = true,
                 restoreMacMetadata: Bool = false, onProgress: @escaping @Sendable (Double) -> Void) async throws(EngineError) -> Output {
        let id = UUID().uuidString
        let request = try encode(ExtractRequest(operationID: id, paths: paths, password: password,
                                                 excludeMacHelperFiles: excludeMacHelperFiles,
                                                 restoreMacMetadata: restoreMacMetadata))
        let handle = try Self.open(archive)
        defer { try? handle.close() }
        progress.register(id, onProgress)
        defer { progress.remove(id) }

        let connection = XPCConnection(try await verifiedConnection())
        let name = archive.lastPathComponent
        let file = SendableHandle(handle)
        let reply: Data
        do {
            reply = try await withTaskCancellationHandler {
                try await Self.call(on: connection) { proxy, once in
                    proxy.extract(file.handle, named: name, request: request) { data, error in
                        Self.resume(once, data, error)
                    }
                }
            } onCancel: {
                connection.proxy?.cancel(operation: id)
            }
        } catch {
            throw EngineError(error)
        }
        return Output(operationID: id, report: try decode(ExtractReport.self, from: reply))
    }

    /// Streams the extracted files into `folder` (which must exist).
    func receive(_ output: Output, into folder: URL) async throws(EngineError) {
        let pipe = Pipe()
        let reading = SendableHandle(pipe.fileHandleForReading)
        let received = Task { try await Self.read(reading, into: folder) }
        let writing = SendableHandle(pipe.fileHandleForWriting)
        let connection = XPCConnection(try await verifiedConnection())
        do {
            let _: Bool = try await Self.call(on: connection) { (proxy, once: ResumeOnce<Bool>) in
                proxy.send(operation: output.operationID, to: writing.handle) { error in
                    if let error { once.resume(throwing: EngineError(error)) } else { once.resume(returning: true) }
                }
            }
        } catch {
            try? writing.handle.close()
            received.cancel()
            _ = await received.result
            throw EngineError(error)
        }
        // The engine closed its copy; closing ours lets the reader see the end.
        try? writing.handle.close()
        do {
            try await received.value
        } catch {
            throw EngineError(error)
        }
    }

    /// Blocking reads from the pipe, off the main actor.
    @concurrent
    private nonisolated static func read(_ pipe: SendableHandle, into folder: URL) async throws {
        defer { try? pipe.handle.close() }
        try TreeStream.read(from: pipe.handle.fileDescriptor, into: folder)
    }

    func discard(_ output: Output) {
        connection.map(XPCConnection.init)?.proxy?.discard(operation: output.operationID)
    }

    private static func open(_ archive: URL) throws(EngineError) -> FileHandle {
        do {
            return try FileHandle(forReadingFrom: archive)
        } catch {
            throw EngineError(.failed, error.localizedDescription)
        }
    }

    private nonisolated static func resume(_ once: ResumeOnce<Data>, _ data: Data?, _ error: NSError?) {
        if let data {
            once.resume(returning: data)
        } else {
            once.resume(throwing: error.map(EngineError.init) ?? EngineError(.failed))
        }
    }

    // MARK: - Connection

    private func verifiedConnection() async throws(EngineError) -> NSXPCConnection {
        let connection = connect()
        guard !isVerified else { return connection }
        let version: Int
        do {
            version = try await withCheckedThrowingContinuation { continuation in
                let once = ResumeOnce(continuation)
                let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                    once.resume(throwing: EngineError(.engineMissing, error.localizedDescription))
                } as? EngineXPCProtocol
                proxy?.handshake(clientVersion: EngineContract.version) { once.resume(returning: $0) }
            }
        } catch {
            throw EngineError(error)
        }
        guard version == EngineContract.version else { throw EngineError(.incompatibleVersion) }
        isVerified = true
        return connection
    }

    private func connect() -> NSXPCConnection {
        if let connection { return connection }
        let connection = NSXPCConnection(serviceName: EngineContract.serviceName)
        connection.remoteObjectInterface = NSXPCInterface(with: EngineXPCProtocol.self)
        connection.exportedInterface = NSXPCInterface(with: EngineClientXPCProtocol.self)
        connection.exportedObject = progress
        // Interrupted: the engine crashed or was killed; launchd relaunches it on the next message.
        connection.interruptionHandler = { [weak self] in
            Task { @MainActor in self?.isVerified = false }
        }
        connection.invalidationHandler = { [weak self] in
            Task { @MainActor in
                self?.connection = nil
                self?.isVerified = false
            }
        }
        connection.resume()
        self.connection = connection
        return connection
    }

    private func call(_ send: @escaping (EngineXPCProtocol, @escaping @Sendable (Data?, NSError?) -> Void) -> Void)
        async throws(EngineError) -> Data {
        let connection = XPCConnection(try await verifiedConnection())
        do {
            return try await Self.call(on: connection) { proxy, once in
                send(proxy) { data, error in Self.resume(once, data, error) }
            }
        } catch {
            throw EngineError(error)
        }
    }

    private nonisolated static func call<T: Sendable>(on connection: XPCConnection,
                                                     _ send: (EngineXPCProtocol, ResumeOnce<T>) -> Void)
        async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let once = ResumeOnce(continuation)
            let proxy = connection.base.remoteObjectProxyWithErrorHandler { _ in
                once.resume(throwing: EngineError(.connectionLost))
            }
            guard let proxy = proxy as? EngineXPCProtocol else {
                once.resume(throwing: EngineError(.engineMissing))
                return
            }
            send(proxy, once)
        }
    }

    private func encode(_ value: some Encodable) throws(EngineError) -> Data {
        do { return try JSONEncoder.engine.encode(value) } catch { throw EngineError(.failed, error.localizedDescription) }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws(EngineError) -> T {
        do { return try JSONDecoder.engine.decode(type, from: data) } catch { throw EngineError(.incompatibleVersion) }
    }
}

/// NSXPCConnection is thread-safe but not annotated Sendable.
private nonisolated struct XPCConnection: @unchecked Sendable {
    let base: NSXPCConnection
    init(_ base: NSXPCConnection) { self.base = base }

    var proxy: EngineXPCProtocol? { base.remoteObjectProxy as? EngineXPCProtocol }
}

/// File handles are safe to pass between threads; the Objective-C type isn't annotated.
private nonisolated struct SendableHandle: @unchecked Sendable {
    let handle: FileHandle
    init(_ handle: FileHandle) { self.handle = handle }
}

/// Receives the engine's progress callbacks (on an XPC queue) and forwards them per operation.
private nonisolated final class ProgressRouter: NSObject, EngineClientXPCProtocol, Sendable {
    private let handlers = Mutex<[String: @Sendable (Double) -> Void]>([:])

    func register(_ id: String, _ handler: @escaping @Sendable (Double) -> Void) {
        handlers.withLock { $0[id] = handler }
    }

    func remove(_ id: String) {
        _ = handlers.withLock { $0.removeValue(forKey: id) }
    }

    func operation(_ id: String, didProgress fraction: Double) {
        handlers.withLock { $0[id] }?(fraction)
    }
}

/// XPC can report a connection error after (or instead of) a reply; resume exactly once.
private nonisolated final class ResumeOnce<T: Sendable>: Sendable {
    private let continuation: Mutex<CheckedContinuation<T, any Error>?>

    init(_ continuation: CheckedContinuation<T, any Error>) {
        self.continuation = Mutex(continuation)
    }

    func resume(returning value: T) {
        continuation.withLock { $0.take() }?.resume(returning: value)
    }

    func resume(throwing error: any Error) {
        continuation.withLock { $0.take() }?.resume(throwing: error)
    }
}
