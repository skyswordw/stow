import Foundation
import Synchronization

/// Compressed tarballs (`.tar.gz`, `.tgz`, `.tar.xz`, `.tar.bz2`, `.tar.zst`, …) browse as the tar
/// inside, not as one compressed stream. 7-Zip can't open a tar through a gzip or xz stream (it
/// isn't seekable), so two `7zz` run as a pipeline: one decompresses to standard output, the other
/// reads the tar from standard input. Nothing is written to disk on the way.
nonisolated extension SevenZip {
    private static let tarSuffixes = [".tar.gz", ".tgz", ".tar.xz", ".txz", ".tar.bz2", ".tbz", ".tbz2", ".tb2",
                                      ".tar.zst", ".tzst", ".tar.lz", ".tar.lzma", ".tlz", ".tar.z", ".taz"]

    /// Decided by name, the same way for listing and extracting, so what's shown is what extracts.
    static func isTarball(name: String) -> Bool {
        let lower = name.lowercased()
        return tarSuffixes.contains { lower.hasSuffix($0) }
    }

    /// The tar's entries; nil when the stream doesn't hold a tar after all.
    func tarballEntries(path: String, descriptor: Int32?) async throws(EngineError) -> [ListedEntry]? {
        let result = try await pipeline(path: path, descriptor: descriptor, consumer: ["l", "-slt", "-sccUTF-8", "-si", "-ttar"])
        guard result.status == 0, let listing = Self.parseListing(result.output) else { return nil }
        return listing.entries
    }

    /// Extracts from the tar inside, like `extract` (paths empty means everything).
    func extractTarball(path: String, descriptor: Int32?, into directory: URL, paths: [String],
                        progress: @escaping @Sendable (Double) -> Void) async throws(EngineError) -> [RemovedLink] {
        var arguments = ["x", "-y", "-aou", "-bso0", "-sccUTF-8", "-si", "-ttar", "-o" + directory.path]
        var listFile: URL?
        if !paths.isEmpty {
            let file = FileManager.default.temporaryDirectory.appending(path: "stow-\(UUID().uuidString).txt")
            do {
                try paths.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
            } catch {
                throw EngineError(.failed, error.localizedDescription)
            }
            listFile = file
            arguments += ["-spd", "-scsUTF-8", "@" + file.path]
        }
        defer { if let listFile { try? FileManager.default.removeItem(at: listFile) } }

        let parser = ProgressParser()
        let result = try await pipeline(path: path, descriptor: descriptor, consumer: arguments) { chunk in
            if let fraction = parser.consume(chunk) { progress(fraction) }
        }
        let refused = Self.refusedLinks(in: result.errors)
        for link in refused {
            let placeholder = directory.appending(path: link.path)
            if (try? placeholder.resourceValues(forKeys: [.fileSizeKey]).fileSize) == 0 {
                try? FileManager.default.removeItem(at: placeholder)
            }
        }
        let otherErrors = result.errors.split(whereSeparator: \.isNewline)
            .filter { $0.hasPrefix("ERROR:") && !$0.contains("Dangerous link path was ignored") }
        if result.status != 0, !(result.status == 2 && otherErrors.isEmpty && !refused.isEmpty) {
            try Self.check(result)
        }
        return refused
    }

    /// `7zz x -so <archive> | 7zz <consumer>`. Returns the consumer's result; a producer that
    /// failed first (a damaged stream) is reported instead. `onProducerProgress` gets the
    /// decompressor's `-bsp2` output — the only progress there is, since the tar's size is unknown.
    private func pipeline(path: String, descriptor: Int32?, consumer: [String],
                          onProducerProgress: (@Sendable (Data) -> Void)? = nil) async throws(EngineError) -> RunResult {
        var stream: [Int32] = [-1, -1], output: [Int32] = [-1, -1], errors: [Int32] = [-1, -1], progress: [Int32] = [-1, -1]
        guard pipe(&stream) == 0, pipe(&output) == 0, pipe(&errors) == 0, pipe(&progress) == 0 else {
            throw EngineError(.failed, String(cString: strerror(errno)))
        }
        let devNull = open("/dev/null", O_RDWR)
        let spare = descriptor.map { fcntl($0, F_DUPFD_CLOEXEC, 10) } ?? -1
        let producer = spawn(["x", "-so", "-bd", "-bsp2", path], stdin: devNull, stdout: stream[1], stderr: progress[1], fd3: spare)
        let reader = spawn(consumer, stdin: stream[0], stdout: output[1], stderr: errors[1], fd3: -1)
        for fd in [stream[0], stream[1], output[1], errors[1], progress[1], spare, devNull] where fd >= 0 { close(fd) }
        let outputHandle = FileHandle(fileDescriptor: output[0], closeOnDealloc: true)
        let errorsHandle = FileHandle(fileDescriptor: errors[0], closeOnDealloc: true)
        let progressHandle = FileHandle(fileDescriptor: progress[0], closeOnDealloc: true)
        guard let producer, let reader else {
            [producer, reader].compactMap(\.self).forEach { kill($0, SIGTERM) }
            throw EngineError(.engineMissing)
        }

        let processes = Mutex([producer, reader])
        async let out = Self.readAll(outputHandle)
        async let err = Self.readAll(errorsHandle)
        async let producerErrors = Self.readAll(progressHandle, onChunk: onProducerProgress)
        let statuses = await withTaskCancellationHandler {
            async let first = Self.exitStatus(producer)
            async let second = Self.exitStatus(reader)
            return await (first, second)
        } onCancel: {
            processes.withLock { $0.forEach { kill($0, SIGTERM) } }
        }
        let (consumerOutput, consumerErrors, decompressorErrors) = await (out, err, producerErrors)
        if Task.isCancelled { throw EngineError(.cancelled) }
        let decompressor = RunResult(status: statuses.0, output: "", errors: String(decoding: decompressorErrors, as: UTF8.self))
        // A broken stream ends the tar early: say what was wrong with the stream.
        if statuses.0 != 0, statuses.1 != 0 { try Self.check(decompressor) }
        return RunResult(status: statuses.1, output: String(decoding: consumerOutput, as: UTF8.self),
                         errors: String(decoding: consumerErrors, as: UTF8.self))
    }

    private func spawn(_ arguments: [String], stdin: Int32, stdout: Int32, stderr: Int32, fd3: Int32) -> pid_t? {
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, stdin, 0)
        posix_spawn_file_actions_adddup2(&actions, stdout, 1)
        posix_spawn_file_actions_adddup2(&actions, stderr, 2)
        if fd3 >= 0 { posix_spawn_file_actions_adddup2(&actions, fd3, 3) }
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT))
        let argv = ([executable.path] + arguments).map { strdup($0) } + [nil]
        let environment = ProcessInfo.processInfo.environment.map { strdup("\($0)=\($1)") } + [nil]
        defer { (argv + environment).forEach { free($0) } }
        var pid: pid_t = 0
        return posix_spawn(&pid, executable.path, &actions, &attributes, argv, environment) == 0 ? pid : nil
    }

    /// Blocking reads off the cooperative pool.
    private static func readAll(_ handle: FileHandle, onChunk: (@Sendable (Data) -> Void)? = nil) async -> Data {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var collected = Data()
                while true {
                    let chunk = handle.availableData
                    if chunk.isEmpty { break }
                    collected.append(chunk)
                    onChunk?(chunk)
                }
                continuation.resume(returning: collected)
            }
        }
    }

    private static func exitStatus(_ pid: pid_t) async -> Int32 {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                var status: Int32 = 0
                while waitpid(pid, &status, 0) == -1, errno == EINTR {}
                continuation.resume(returning: status & 0x7f == 0 ? (status >> 8) & 0xff : -1)
            }
        }
    }
}
