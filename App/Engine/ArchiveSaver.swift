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
        try await writeEdited(url, destination: url, replaceOriginal: true, identity: identity,
                              operations: operations, items: items, password: password,
                              encryptNewItems: encryptNewItems, faults: faults, progress: progress)
    }

    private static func writeEdited(_ url: URL, destination: URL, replaceOriginal: Bool, identity: FileIdentity?,
                                    operations: [EditOperation], items: [TreeStream.Item], password: String?,
                                    encryptNewItems: Bool, faults: Faults,
                                    progress: @escaping @Sendable (Double) -> Void) async throws -> ArchiveListing {
        func checkIdentity() throws {
            guard let identity else { return }
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
        let sources = items.compactMap { item -> ListedEntry? in
            guard let values = try? item.source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]) else { return nil }
            return ListedEntry(path: item.path, isFolder: values.isDirectory == true && values.isSymbolicLink != true,
                               isSymlink: values.isSymbolicLink == true, size: Int64(values.fileSize ?? 0))
        }
        _ = try EditPlan.steps(for: operations, listing: listing, format: format, sources: sources)
        let staging = try Self.makeStaging(for: replaceOriginal ? url : destination)
        defer { staging.cleanup() }
        let temporary = staging.file
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
        let editing = TaskSlot<EditReport>()
        let editTask = Task {
            try await engine.edit(url, items: items, request: request, onSent: { _ in }, onProgress: { fraction in
                progress(fraction * 0.8)
                if case .cancelDuringEngine = faults, fraction > 0 { editing.cancel() }
            })
        }
        editing.set(editTask)
        let report = try await withTaskCancellationHandler { try await editTask.value } onCancel: { editTask.cancel() }
        if case .cancelDuringEngine = faults { throw EngineError(.cancelled) }
        try Task.checkCancellation()
        let transferring = TaskSlot<Void>()
        let transfer = Task {
            try await engine.sendFile(operation: id, to: handle) { fraction in
                progress(0.8 + fraction * 0.1)
                if case .cancelDuringTransfer = faults { transferring.cancel() }
            }
        }
        transferring.set(transfer)
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
        if replaceOriginal {
            do {
                _ = try manager.replaceItemAt(url, withItemAt: temporary, backupItemName: nil, options: [])
            } catch {
                try checkIdentity()
                throw EngineError(.failed, String(localized: "Couldn’t replace the archive. The original was kept."))
            }
        } else {
            if FileManager.default.fileExists(atPath: destination.path) {
                throw EngineError(.failed, String(localized: "An item named “\(destination.lastPathComponent)” already exists."))
            }
            do {
                try manager.moveItem(at: temporary, to: destination)
            } catch {
                throw EngineError(.failed, String(localized: "Couldn’t save a copy of the archive."))
            }
        }
        progress(1)
        return report.listing
    }

    /// Writes the edited archive to `destination` without touching the original. Used for
    /// "Save a Copy" when the original changed on disk or lives on a volume Stow can't replace in place.
    /// Pass `ignoreIdentity: true` after an external change so the current on-disk bytes are the base.
    static func saveCopy(from archive: URL, to destination: URL, operations: [EditOperation], items: [TreeStream.Item],
                         password: String? = nil, encryptNewItems: Bool = true, faults: Faults = .none,
                         identity: FileIdentity? = nil, ignoreIdentity: Bool = false,
                         progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws(EngineError) -> ArchiveListing {
        do {
            let baseline: FileIdentity?
            if ignoreIdentity { baseline = nil }
            else if let identity { baseline = identity }
            else { baseline = try FileIdentity(of: archive) }
            return try await coordinated(archive) { coordinatedURL in
                try await writeEdited(coordinatedURL, destination: destination, replaceOriginal: false,
                                      identity: baseline, operations: operations, items: items,
                                      password: password, encryptNewItems: encryptNewItems, faults: faults, progress: progress)
            }
        } catch { throw error is CancellationError || Task.isCancelled ? EngineError(.cancelled) : EngineError(error) }
    }

    /// Renames the archive file on disk. Parent-folder write access must already be granted
    /// (see `FolderAccess`). Keeps the same volume; used for File › Rename Archive… including SMB/NAS.
    static func renameArchive(at url: URL, to newName: String) throws(EngineError) -> URL {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/"), trimmed != ".", trimmed != ".." else {
            throw EngineError(.failed, String(localized: "Enter a name without a slash."))
        }
        let destination = url.deletingLastPathComponent().appending(path: trimmed)
        guard destination.standardizedFileURL != url.standardizedFileURL else { return url }
        if FileManager.default.fileExists(atPath: destination.path) {
            throw EngineError(.failed, String(localized: "An item named “\(trimmed)” already exists."))
        }
        var coordinationError: NSError?
        var moveError: (any Error)?
        var moved: URL?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forMoving,
                                       writingItemAt: destination, options: .forReplacing,
                                       error: &coordinationError) { from, to in
            do {
                try FileManager.default.moveItem(at: from, to: to)
                moved = to
            } catch {
                moveError = error
            }
        }
        if let moved { return moved }
        if let moveError { throw EngineError(moveError) }
        throw EngineError(coordinationError ?? EngineError(.failed).nsError)
    }

    /// Same-volume staging: prefer the system replacement directory; on SMB/FAT and other volumes
    /// where that lands elsewhere, stage a sibling next to the archive (caller must have write access).
    nonisolated static func makeStaging(for url: URL) throws(EngineError) -> (file: URL, cleanup: @Sendable () -> Void) {
        let manager = FileManager.default
        if let directory = try? manager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: url, create: true) {
            var originalInfo = stat(), stagingInfo = stat()
            if stat(url.path, &originalInfo) == 0, stat(directory.path, &stagingInfo) == 0,
               originalInfo.st_dev == stagingInfo.st_dev {
                let temporary = directory.appending(path: url.lastPathComponent + ".stow-saving")
                return (temporary, { try? FileManager.default.removeItem(at: directory) })
            }
            try? manager.removeItem(at: directory)
        }
        let parent = url.deletingLastPathComponent()
        let probe = parent.appending(path: ".stow-access-\(UUID().uuidString)")
        guard mkdir(probe.path, 0o700) == 0 else {
            throw EngineError(.failed, String(localized: "A replacement folder on the archive’s volume is unavailable. Save a copy instead."))
        }
        rmdir(probe.path)
        let temporary = parent.appending(path: ".\(url.lastPathComponent).stow-saving-\(UUID().uuidString)")
        return (temporary, { try? FileManager.default.removeItem(at: temporary) })
    }

    /// Whether `url`'s parent is on a volume where `itemReplacementDirectory` is same-device.
    nonisolated static func needsSiblingStaging(for url: URL) -> Bool {
        let manager = FileManager.default
        guard let directory = try? manager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: url, create: true) else {
            return true
        }
        defer { try? manager.removeItem(at: directory) }
        var originalInfo = stat(), stagingInfo = stat()
        guard stat(url.path, &originalInfo) == 0, stat(directory.path, &stagingInfo) == 0 else { return true }
        return originalInfo.st_dev != stagingInfo.st_dev
    }

    /// The coordinator's accessor must remain alive across engine awaits. Block only a dedicated
    /// utility queue; the main actor and cooperative executor remain free to service XPC replies.
    private static func coordinated(_ url: URL, operation: @escaping @MainActor @Sendable (URL) async throws -> ArchiveListing)
        async throws -> ArchiveListing {
        let state = CoordinationState()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ArchiveListing, any Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    var coordinationError: NSError?
                    var outcome: Result<ArchiveListing, any Error>?
                    NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinatedURL in
                        let task = Task { @MainActor in try await operation(coordinatedURL) }
                        state.start(task)
                        let completed = DispatchSemaphore(value: 0)
                        let box = ResultBox()
                        Task {
                            box.set(await task.result)
                            completed.signal()
                        }
                        completed.wait()
                        outcome = box.get()
                    }
                    if let outcome { continuation.resume(with: outcome) }
                    else { continuation.resume(throwing: coordinationError ?? EngineError(.failed).nsError) }
                }
            }
        } onCancel: { state.cancel() }
    }

    private nonisolated final class CoordinationState: Sendable {
        private let lock = Mutex<(cancelled: Bool, task: Task<ArchiveListing, any Error>?)>((false, nil))
        func start(_ task: Task<ArchiveListing, any Error>) {
            let cancelled = lock.withLock { state in
                state.task = task
                return state.cancelled
            }
            if cancelled { task.cancel() }
        }
        func cancel() {
            lock.withLock { state in
                state.cancelled = true
                return state.task
            }?.cancel()
        }
    }

    private nonisolated final class ResultBox: Sendable {
        private let lock = Mutex<Result<ArchiveListing, any Error>?>(nil)
        func set(_ value: Result<ArchiveListing, any Error>) { lock.withLock { $0 = value } }
        func get() -> Result<ArchiveListing, any Error>? { lock.withLock { $0 } }
    }

    /// Lets a progress callback cancel the task it reports for (fault injection).
    private nonisolated final class TaskSlot<Success: Sendable>: Sendable {
        private let lock = Mutex<Task<Success, any Error>?>(nil)
        func set(_ task: Task<Success, any Error>) { lock.withLock { $0 = task } }
        func cancel() { lock.withLock { $0 }?.cancel() }
    }
}
