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
        try await list(archive, password: password, onChunk: { _ in })
    }

    func list(_ archive: URL, password: String? = nil,
              onChunk: @escaping @Sendable ([ListedEntry]) -> Void) async throws(EngineError) -> ArchiveListing {
        if Task.isCancelled { throw EngineError(.cancelled) }
        let id = UUID().uuidString
        let request = try encode(ListRequest(operationID: id, password: password))
        let handle = try await Self.open(archive)
        defer { try? handle.close() }
        progress.registerList(id, onChunk)
        defer { progress.removeList(id) }
        let connection = XPCConnection(try await verifiedConnection())
        let file = SendableHandle(handle)
        let name = SplitArchive.baseName(archive.lastPathComponent) ?? archive.lastPathComponent
        do {
            let reply = try await withTaskCancellationHandler {
                try await Self.call(on: connection) { proxy, once in
                    proxy.listArchive(file.handle, named: name, request: request) { data, error in
                        Self.resume(once, data, error)
                    }
                    // The request must precede cancel even when already cancelled at entry.
                    if Task.isCancelled { proxy.cancel(operation: id) }
                }
            } onCancel: { connection.proxy?.cancel(operation: id) }
            if Task.isCancelled { throw EngineError(.cancelled) }
            return try decode(ArchiveListing.self, from: reply)
        } catch { throw SplitArchive.recover(EngineError(error), name: archive.lastPathComponent) }
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
        let handle = try await Self.open(archive)
        defer { try? handle.close() }
        progress.register(id, onProgress)
        defer { progress.remove(id) }

        let connection = XPCConnection(try await verifiedConnection())
        let name = SplitArchive.baseName(archive.lastPathComponent) ?? archive.lastPathComponent
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
            throw SplitArchive.recover(EngineError(error), name: archive.lastPathComponent)
        }
        return Output(operationID: id, report: try decode(ExtractReport.self, from: reply))
    }

    /// A finished archive waiting inside the engine: `receive` it, then `discard` it.
    struct Creation: Sendable {
        let operationID: String
        let report: CreateReport
    }

    /// Streams `items` to the engine and has it pack them. `onSent` reports bytes of file data handed
    /// over; `onProgress` the engine's compression progress. Cancelling the task stops both.
    func create(_ items: [TreeStream.Item], attributes: Bool, request: CreateRequest,
                onSent: @escaping @Sendable (Int64) -> Void,
                onProgress: @escaping @Sendable (Double) -> Void) async throws(EngineError) -> Creation {
        let id = request.operationID
        let payload = try encode(request)
        progress.register(id, onProgress)
        defer { progress.remove(id) }
        let connection = XPCConnection(try await verifiedConnection())

        let pipe = Pipe()
        // If the engine goes away mid-stream, writes fail with EPIPE instead of killing Stow.
        _ = fcntl(pipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        let reading = SendableHandle(pipe.fileHandleForReading)
        let writing = SendableHandle(pipe.fileHandleForWriting)
        let sending = Task { try await Self.write(items, to: writing, attributes: attributes, onSent: onSent) }

        let reply: Result<Data, EngineError>
        do {
            reply = .success(try await withTaskCancellationHandler {
                try await Self.call(on: connection) { proxy, once in
                    proxy.create(from: reading.handle, request: payload) { data, error in
                        Self.resume(once, data, error)
                    }
                }
            } onCancel: {
                sending.cancel()
                connection.proxy?.cancel(operation: id)
            })
        } catch {
            reply = .failure(EngineError(error))
        }
        // With no reader left, a writer still blocked in the pipe wakes up with EPIPE.
        try? reading.handle.close()
        let sent = await sending.result

        switch reply {
        case .success(let data):
            return Creation(operationID: id, report: try decode(CreateReport.self, from: data))
        case .failure(let error):
            // A file Stow couldn't read explains more than the engine's view of a cut-off stream.
            if error.failure != .cancelled, case .failure(let sendError) = sent,
               EngineError(sendError).failure != .cancelled {
                throw EngineError(sendError)
            }
            throw error
        }
    }

    func edit(_ archive: URL, items: [TreeStream.Item], request: EditRequest,
                onSent: @escaping @Sendable (Int64) -> Void,
                onProgress: @escaping @Sendable (Double) -> Void) async throws(EngineError) -> EditReport {
        let handle = try await Self.open(archive)
        defer { try? handle.close() }
        let file = SendableHandle(handle)
        let name = SplitArchive.baseName(archive.lastPathComponent) ?? archive.lastPathComponent
        let id = request.operationID
        let payload = try encode(request)
        progress.register(id, onProgress)
        defer { progress.remove(id) }
        let connection = XPCConnection(try await verifiedConnection())

        let pipe = Pipe()
        // If the engine goes away mid-stream, writes fail with EPIPE instead of killing Stow.
        _ = fcntl(pipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        let reading = SendableHandle(pipe.fileHandleForReading)
        let writing = SendableHandle(pipe.fileHandleForWriting)
        let sending = Task { try await Self.write(items, to: writing, attributes: false, onSent: onSent) }

        let reply: Result<Data, EngineError>
        do {
            reply = .success(try await withTaskCancellationHandler {
                try await Self.call(on: connection) { proxy, once in
                    proxy.edit(file.handle, named: name, tree: reading.handle, request: payload) { data, error in
                        Self.resume(once, data, error)
                    }
                }
            } onCancel: {
                sending.cancel()
                connection.proxy?.cancel(operation: id)
            })
        } catch {
            reply = .failure(EngineError(error))
        }
        // With no reader left, a writer still blocked in the pipe wakes up with EPIPE.
        try? reading.handle.close()
        let sent = await sending.result

        switch reply {
        case .success(let data):
            if Task.isCancelled {
                discard(operation: id)
                throw EngineError(.cancelled)
            }
            if case .failure(let error) = sent {
                discard(operation: id)
                throw EngineError(error)
            }
            return try decode(EditReport.self, from: data)
        case .failure(let error):
            // A file Stow couldn't read explains more than the engine's view of a cut-off stream.
            if error.failure != .cancelled, case .failure(let sendError) = sent,
               EngineError(sendError).failure != .cancelled {
                throw EngineError(sendError)
            }
            throw error
        }
    }

    func sendFile(operation id: String, to handle: FileHandle,
                  onProgress: @escaping @Sendable (Double) -> Void = { _ in }) async throws(EngineError) {
        progress.register(id, onProgress)
        defer { progress.remove(id) }
        let connection = XPCConnection(try await verifiedConnection())
        let destination = SendableHandle(handle)
        do {
            let _: Bool = try await withTaskCancellationHandler {
                try await Self.call(on: connection) { (proxy, once: ResumeOnce<Bool>) in
                    proxy.sendFile(operation: id, to: destination.handle) { error in
                        if let error { once.resume(throwing: EngineError(error)) }
                        else { once.resume(returning: true) }
                    }
                }
            } onCancel: { connection.proxy?.cancel(operation: id) }
            if Task.isCancelled { throw EngineError(.cancelled) }
        } catch { throw EngineError(error) }
    }

    func cancel(operation id: String) {
        connection.map(XPCConnection.init)?.proxy?.cancel(operation: id)
    }

    /// Blocking writes into the pipe, off the main actor. Closes it at the end, so the engine sees EOF.
    @concurrent
    private nonisolated static func write(_ items: [TreeStream.Item], to pipe: SendableHandle, attributes: Bool,
                                          onSent: @Sendable (Int64) -> Void) async throws {
        defer { try? pipe.handle.close() }
        try TreeStream.write(items, to: pipe.handle.fileDescriptor, attributes: attributes, onBytes: onSent)
    }

    /// Checks every entry against the archive's checksums without extracting anything.
    func verify(_ archive: URL, password: String? = nil) async throws(EngineError) {
        let id = UUID().uuidString
        let request = try encode(ExtractRequest(operationID: id, password: password, testOnly: true))
        let handle = try await Self.open(archive)
        defer { try? handle.close() }
        do {
            _ = try await call { proxy, reply in
                proxy.extract(handle, named: SplitArchive.baseName(archive.lastPathComponent) ?? archive.lastPathComponent, request: request, reply: reply)
            }
        } catch { throw SplitArchive.recover(EngineError(error), name: archive.lastPathComponent) }
    }

    /// Streams the extracted files into `folder` (which must exist).
    func receive(_ output: Output, into folder: URL) async throws(EngineError) {
        try await receive(operation: output.operationID, into: folder)
    }

    /// Streams an operation's output (extracted files, or a new archive) into `folder`.
    func receive(operation id: String, into folder: URL) async throws(EngineError) {
        let pipe = Pipe()
        let reading = SendableHandle(pipe.fileHandleForReading)
        let received = Task { try await Self.read(reading, into: folder) }
        let writing = SendableHandle(pipe.fileHandleForWriting)
        let connection = XPCConnection(try await verifiedConnection())
        do {
            let _: Bool = try await Self.call(on: connection) { (proxy, once: ResumeOnce<Bool>) in
                proxy.send(operation: id, to: writing.handle) { error in
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
        discard(operation: output.operationID)
    }

    func discard(operation id: String) {
        connection.map(XPCConnection.init)?.proxy?.discard(operation: id)
    }

    private static func open(_ archive: URL) async throws(EngineError) -> FileHandle {
        if SplitArchive.baseName(archive.lastPathComponent) != nil {
            let folder = archive.deletingLastPathComponent()
            #if !STOW_NO_ZSTD
            // FolderAccess lives in the app target only; Quick Look already has the file grant.
            do {
                _ = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            } catch {
                guard await FolderAccess.shared.readableParts(in: folder) else { throw EngineError(.cancelled) }
            }
            #endif
            do {
                let parts = try SplitArchive.parts(for: archive)
                #if !STOW_NO_ZSTD
                if parts.contains(where: { !FileManager.default.isReadableFile(atPath: $0.path) }) {
                    guard await FolderAccess.shared.readableParts(in: folder) else { throw EngineError(.cancelled) }
                }
                #endif
                return try await SplitArchive.open(parts)
            } catch { throw EngineError(error) }
        }
        do { return try FileHandle(forReadingFrom: archive) }
        catch { throw EngineError(.failed, error.localizedDescription) }
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
    private let lists = Mutex<[String: @Sendable ([ListedEntry]) -> Void]>([:])

    func registerList(_ id: String, _ handler: @escaping @Sendable ([ListedEntry]) -> Void) {
        lists.withLock { $0[id] = handler }
    }

    func removeList(_ id: String) { _ = lists.withLock { $0.removeValue(forKey: id) } }

    func operation(_ id: String, didListChunk data: Data) {
        guard let chunk = try? JSONDecoder.engine.decode(ListChunk.self, from: data) else { return }
        lists.withLock { $0[id] }?(chunk.entries)
    }

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
