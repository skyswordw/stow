import CryptoKit
import Darwin
import Foundation
import Synchronization

/// Captured when editing begins, then passed back to `save(identity:)`.
nonisolated struct FileIdentity: Equatable, @unchecked Sendable {
    private var resourceIdentifier: NSObject
    private var size: Int
    private var modified: Date?
    private var edgeHash: Data

    init(of url: URL) throws(EngineError) {
        do {
            let values = try url.resourceValues(forKeys: [.fileResourceIdentifierKey, .fileSizeKey, .contentModificationDateKey])
            guard let identifier = values.fileResourceIdentifier as? NSObject, let size = values.fileSize else {
                throw EngineError(.failed)
            }
            // Opaque resource identifiers compare by Foundation value equality. Never mutate them.
            resourceIdentifier = identifier
            self.size = size
            modified = values.contentModificationDate
            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
            var hash = SHA256()
            hash.update(data: try file.read(upToCount: 65_536) ?? Data())
            try file.seek(toOffset: UInt64(max(0, size - 65_536)))
            hash.update(data: try file.read(upToCount: 65_536) ?? Data())
            edgeHash = Data(hash.finalize())
        } catch { throw EngineError(error) }
    }
}

enum ArchiveSaver {
    /// Internal fault injection, available to @testable imports in every build configuration.
    enum Faults: Sendable {
        case none
        /// Hands the engine a descriptor it can't write to, so the transfer itself fails.
        case failWrite
        case failBeforeSwap
        case cancelDuringEngine
        case cancelDuringTransfer
    }

    /// Supply the identity captured when the archive was opened. Omitting it captures a baseline
    /// immediately, useful for callers performing a single edit without an editing session.
    static func save(archive url: URL, operations: [EditOperation], items: [TreeStream.Item],
                     password: String? = nil, encryptNewItems: Bool = true, faults: Faults = .none,
                     identity: FileIdentity? = nil,
                     progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws(EngineError) -> ArchiveListing {
        do {
            let baseline: FileIdentity
            if let identity { baseline = identity }
            else { baseline = try FileIdentity(of: url) }
            return try await coordinated(url) { coordinatedURL in
                try await saveCoordinated(coordinatedURL, identity: baseline, operations: operations, items: items,
                                          password: password, encryptNewItems: encryptNewItems, faults: faults, progress: progress)
            }
        } catch { throw error is CancellationError || Task.isCancelled ? EngineError(.cancelled) : EngineError(error) }
    }

    private static func saveCoordinated(_ url: URL, identity: FileIdentity, operations: [EditOperation],
                                        items: [TreeStream.Item], password: String?, encryptNewItems: Bool,
                                        faults: Faults, progress: @escaping @Sendable (Double) -> Void) async throws -> ArchiveListing {
        func checkIdentity() throws {
            guard (try? FileIdentity(of: url)) == identity else { throw EngineError(.changedOnDisk) }
        }
        try checkIdentity()
        try Task.checkCancellation()
        let manager = FileManager.default
        let engine = ArchiveEngine.shared
        let listing = try await engine.list(url, password: password)
        guard let format = EditableFormat(listingType: listing.type, fileName: url.lastPathComponent) else {
            throw EngineError(.failed, String(localized: "This archive format cannot be edited."))
        }
        _ = try EditPlan.steps(for: operations, listing: listing, format: format)
        let directory: URL
        do {
            directory = try manager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: url, create: true)
        } catch {
            // TODO #10/#9: folder access and a sibling temporary file for SMB / other volumes.
            throw EngineError(.failed, String(localized: "A replacement folder on the archive’s volume is unavailable. Save a copy instead."))
        }
        defer { try? manager.removeItem(at: directory) }
        var originalInfo = stat(), stagingInfo = stat()
        guard stat(url.path, &originalInfo) == 0, stat(directory.path, &stagingInfo) == 0,
              originalInfo.st_dev == stagingInfo.st_dev else {
            // TODO #10/#9: same-directory fallback with folder access.
            throw EngineError(.failed, String(localized: "A replacement folder on the archive’s volume is unavailable. Save a copy instead."))
        }
        let temporary = directory.appending(path: url.lastPathComponent + ".stow-saving")
        var fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
        if case .failWrite = faults, fd >= 0 {
            close(fd)
            fd = open(temporary.path, O_RDONLY | O_CLOEXEC)
        }
        guard fd >= 0 else { throw EngineError(.failed, String(localized: "Couldn’t create the replacement file.")) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        let id = UUID().uuidString
        defer { engine.discard(operation: id) }
        let request = EditRequest(operationID: id, format: format, operations: operations,
                                  password: password, encryptNewItems: encryptNewItems)
        let editing = Mutex<Task<EditReport, any Error>?>(nil)
        let editTask = Task {
            try await engine.edit(url, items: items, request: request, onSent: { _ in }, onProgress: { fraction in
                progress(fraction * 0.8)
                if case .cancelDuringEngine = faults, fraction > 0 { editing.withLock { $0 }?.cancel() }
            })
        }
        editing.withLock { $0 = editTask }
        let report = try await withTaskCancellationHandler { try await editTask.value } onCancel: { editTask.cancel() }
        if case .cancelDuringEngine = faults { throw EngineError(.cancelled) }
        try Task.checkCancellation()
        let transferring = Mutex<Task<Void, any Error>?>(nil)
        let transfer = Task {
            try await engine.sendFile(operation: id, to: handle) { fraction in
                progress(0.8 + fraction * 0.1)
                if case .cancelDuringTransfer = faults { transferring.withLock { $0 }?.cancel() }
            }
        }
        transferring.withLock { $0 = transfer }
        try await withTaskCancellationHandler { try await transfer.value } onCancel: { transfer.cancel() }
        if case .cancelDuringTransfer = faults { throw EngineError(.cancelled) }
        try handle.close()
        try Task.checkCancellation()
        let size = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard size.map(Int64.init) == report.size, report.verified else {
            throw EngineError(.failed, String(localized: "The replacement archive is incomplete. The original was kept."))
        }
        let received = try await engine.list(temporary, password: password)
        guard received.entries == report.listing.entries else {
            throw EngineError(.failed, String(localized: "The replacement archive is incomplete. The original was kept."))
        }
        progress(0.95)
        try Task.checkCancellation()
        try checkIdentity()
        if case .failBeforeSwap = faults { throw EngineError(.failed, String(localized: "Couldn’t replace the archive. The original was kept.")) }
        do {
            _ = try manager.replaceItemAt(url, withItemAt: temporary, backupItemName: nil, options: [])
        } catch {
            try checkIdentity()
            throw EngineError(.failed, String(localized: "Couldn’t replace the archive. The original was kept."))
        }
        progress(1)
        return report.listing
    }

    /// The coordinator's accessor must remain alive across engine awaits. Block only a dedicated
    /// utility queue; the main actor and cooperative executor remain free to service XPC replies.
    private static func coordinated(_ url: URL, operation: @escaping @MainActor @Sendable (URL) async throws -> ArchiveListing)
        async throws -> ArchiveListing {
        let active = Mutex<(cancelled: Bool, task: Task<ArchiveListing, any Error>?)>((false, nil))
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ArchiveListing, any Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    var coordinationError: NSError?
                    let result = Mutex<Result<ArchiveListing, any Error>?>(nil)
                    NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinatedURL in
                        let task = Task { @MainActor in try await operation(coordinatedURL) }
                        active.withLock { state in
                            state.task = task
                            if state.cancelled { task.cancel() }
                        }
                        let completed = DispatchSemaphore(value: 0)
                        let outcome = Mutex<Result<ArchiveListing, any Error>?>(nil)
                        Task {
                            let value = await task.result
                            outcome.withLock { $0 = value }
                            completed.signal()
                        }
                        completed.wait()
                        let value = outcome.withLock { $0 }
                        result.withLock { $0 = value }
                    }
                    if let value = result.withLock({ $0 }) { continuation.resume(with: value) }
                    else { continuation.resume(throwing: coordinationError ?? EngineError(.failed).nsError) }
                }
            }
        } onCancel: { active.withLock { state in
            state.cancelled = true
            state.task?.cancel()
        } }
    }
}
