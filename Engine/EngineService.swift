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
        for item in items where [outputPrefix, packPrefix, packInputPrefix, "edit-"].contains(where: item.lastPathComponent.hasPrefix) {
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

    func edit(_ archive: FileHandle, named name: String, tree: FileHandle?, request payload: Data,
              reply: @escaping @Sendable (Data?, NSError?) -> Void) {
        let request: EditRequest
        do { request = try Self.decode(EditRequest.self, from: payload) }
        catch {
            try? tree?.close()
            reply(nil, EngineError(error).nsError)
            return
        }
        let archive = SendableHandle(archive)
        let tree = tree.map(SendableHandle.init)
        let id = request.operationID
        let output = FileManager.default.temporaryDirectory.appending(path: "edit-" + UUID().uuidString)
        let client = client
        running.withLock { running in
            running[id] = Task {
                do {
                    let manager = FileManager.default
                    let input = output.appending(path: "input")
                    let staged = output.appending(path: "tree")
                    for folder in [input, staged] {
                        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
                    }
                    outputs.withLock { $0[id] = output }
                    let work = output.appending(path: "work." + request.format.fileExtension)
                    try await Self.copy(archive, to: work)
                    if let tree { try await Self.receive(tree, into: input) }
                    let sevenZip = try Self.sevenZip()
                    var encryptedHeaders = false
                    let listing: ArchiveListing
                    do { listing = try await sevenZip.list(work) }
                    catch let error where EngineError(error).failure == .passwordRequired {
                        guard request.password != nil else { throw error }
                        encryptedHeaders = true
                        listing = try await sevenZip.list(work, password: request.password)
                    }
                    guard EditableFormat(listingType: listing.type, fileName: name) == request.format else {
                        throw EngineError(.failed, String(localized: "This archive format cannot be edited."))
                    }
                    if listing.entries.contains(where: \.isEncrypted), request.password == nil {
                        throw EngineError(.passwordRequired)
                    }
                    // Validate passwords before deletion: deleting every encrypted entry must not
                    // make an incorrect password appear to work at the final verification step.
                    if encryptedHeaders || listing.entries.contains(where: \.isEncrypted) {
                        try await sevenZip.test(.file(work), password: request.password) { _ in }
                    }
                    var sourceEntries: [ListedEntry] = []
                    if let walker = manager.enumerator(at: input, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]) {
                        for case let url as URL in walker {
                            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
                            let path = String(url.path.dropFirst(input.path.count + 1))
                            sourceEntries.append(ListedEntry(path: path, isFolder: values.isDirectory == true && values.isSymbolicLink != true,
                                                            isSymlink: values.isSymbolicLink == true, size: Int64(values.fileSize ?? 0)))
                        }
                    }
                    let steps = try EditPlan.steps(for: request.operations, listing: listing, format: request.format, sources: sourceEntries)
                    for source in steps.flatMap(\.sources) {
                        let from = input.appending(path: source.item)
                        let to = staged.appending(path: source.path)
                        if source.requiresRegularFile {
                            var info = stat()
                            guard lstat(from.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
                                throw EngineError(.failed, String(localized: "Only an existing regular file can be replaced."))
                            }
                        }
                        let resolved = PathContainment.resolvedPath(from.path)
                        guard PathContainment.isInside(resolved, root: input.path) else {
                            throw EngineError(.failed, String(localized: "A staged item points outside the staging tree."))
                        }
                        try manager.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
                        let values = try from.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                        if values.isDirectory == true, values.isSymbolicLink != true {
                            try manager.createDirectory(at: to, withIntermediateDirectories: true)
                        } else {
                            try manager.copyItem(at: from, to: to)
                        }
                    }
                    let audit = try PathContainment.audit(staging: staged)
                    guard audit.removedItems.isEmpty, audit.removedLinks.isEmpty else {
                        throw EngineError(.failed, String(localized: "A staged item points outside the staging tree."))
                    }
                    let count = steps.count
                    for (index, step) in steps.enumerated() {
                        try Task.checkCancellation()
                        if step.arguments.first == "t", !request.verify { continue }
                        var arguments = step.arguments
                        if arguments.first == "a", request.encryptNewItems, request.password != nil,
                           request.format != .tar {
                            arguments.insert(contentsOf: request.format == .zip ? ["-p", "-mem=AES256"] :
                                (encryptedHeaders ? ["-p", "-mhe=on"] : ["-p"]), at: 1)
                        }
                        let parser = ProgressParser()
                        // Adding to a 7z with encrypted headers reads the password twice: once to open the archive, once
                        // for the new items' `-p`. Answer both; an unread second line is harmless.
                        let answer = arguments.first == "a" && encryptedHeaders
                            ? request.password.map { $0 + "\n" + $0 } : request.password
                        let result = try await sevenZip.run(arguments, input: nil, password: answer, in: staged) { chunk in
                            if let fraction = parser.consume(chunk) { client.progress(id, (Double(index) + fraction) / Double(count)) }
                        }
                        do { try SevenZip.check(result) }
                        catch {
                            if step.arguments.first == "t", EngineError(error).failure == .failed {
                                throw EngineError(.failed, String(localized: "The edited archive didn’t pass its check. The original was kept."))
                            }
                            throw error
                        }
                        client.progress(id, Double(index + 1) / Double(count))
                    }
                    try Task.checkCancellation()
                    let updated = try await sevenZip.list(work, password: request.password)
                    let size = try work.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    let data = try JSONEncoder.engine.encode(EditReport(size: Int64(size), verified: request.verify, listing: updated))
                    _ = self.running.withLock { $0.removeValue(forKey: id) }
                    reply(data, nil)
                } catch {
                    try? tree?.handle.close()
                    self.discard(operation: id)
                    _ = self.running.withLock { $0.removeValue(forKey: id) }
                    reply(nil, (Task.isCancelled ? EngineError(.cancelled) : EngineError(error)).nsError)
                }
            }
        }
    }

    /// Copies into the engine's container; cancellation is checked between bounded reads.
    @concurrent
    private static func copy(_ source: SendableHandle, to url: URL) async throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw EngineError(.failed) }
        let destination = try FileHandle(forWritingTo: url)
        defer { try? destination.close() }
        while let bytes = try source.handle.read(upToCount: 64 * 1024), !bytes.isEmpty {
            try Task.checkCancellation()
            try destination.write(contentsOf: bytes)
        }
    }

    func sendFile(operation: String, to destination: FileHandle, reply: @escaping @Sendable (NSError?) -> Void) {
        let destination = SendableHandle(destination)
        guard let output = outputs.withLock({ $0[operation] }), output.lastPathComponent.hasPrefix("edit-") else {
            try? destination.handle.close()
            reply(EngineError(.failed).nsError)
            return
        }
        running.withLock { running in
            running[operation] = Task {
                do {
                    let work = try FileManager.default.contentsOfDirectory(at: output, includingPropertiesForKeys: nil)
                        .first { ["work.zip", "work.7z", "work.tar"].contains($0.lastPathComponent) }
                    guard let work else { throw EngineError(.failed) }
                    let size = try work.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    try await Self.transfer(work, to: destination) { bytes in
                        self.client.progress(operation, min(1, Double(bytes) / Double(max(1, size))))
                    }
                    try Task.checkCancellation()
                    try destination.handle.close()
                    self.discard(operation: operation)
                    _ = self.running.withLock { $0.removeValue(forKey: operation) }
                    reply(nil)
                } catch {
                    try? destination.handle.close()
                    self.discard(operation: operation)
                    _ = self.running.withLock { $0.removeValue(forKey: operation) }
                    reply((Task.isCancelled ? EngineError(.cancelled) : EngineError(error)).nsError)
                }
            }
        }
    }

    @concurrent
    private static func transfer(_ work: URL, to destination: SendableHandle,
                                 progress: @escaping @Sendable (Int64) -> Void) async throws {
        let source = try FileHandle(forReadingFrom: work)
        defer { try? source.close() }
        var sent: Int64 = 0
        while let bytes = try source.read(upToCount: 64 * 1024), !bytes.isEmpty {
            try Task.checkCancellation()
            try destination.handle.write(contentsOf: bytes)
            sent += Int64(bytes.count)
            progress(sent)
        }
        try destination.handle.synchronize()
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
            reply(EngineError(.failed, String(localized: "That extraction is no longer available.")).nsError)
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
        if let task = running.withLock({ $0[operation] }) { task.cancel() }
        else { discard(operation: operation) }
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
