import Foundation
import Synchronization

/// What 7-Zip reads: a path (tests, tools), or a descriptor Stow opened and sent over XPC.
nonisolated enum ArchiveInput: Sendable {
    case file(URL)
    /// Read as fd 3 through a link named like the archive, so 7-Zip still gets the extension hint.
    case descriptor(FileHandle, name: String)
}

/// Drives the bundled, unmodified 7-Zip console binary (`7zz`, LGPL — see THIRD_PARTY_NOTICES.md).
/// Runs inside the sandboxed engine; the child process inherits that sandbox.
nonisolated struct SevenZip: Sendable {
    let executable: URL
    /// The locale 7-Zip runs under; nil keeps the engine's (UTF-8 for names).
    var locale: String?

    init(executable: URL) {
        self.executable = executable
    }

    /// `7zz` sits next to the engine's executable; from the app (tests) it's inside the engine bundle.
    static func bundled(in bundle: Bundle = .main) -> SevenZip? {
        let candidates = [
            bundle.url(forAuxiliaryExecutable: "7zz"),
            bundle.bundleURL.appending(path: "Contents/XPCServices/StowEngine.xpc/Contents/MacOS/7zz"),
        ]
        return candidates.compactMap(\.self)
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
            .map(SevenZip.init(executable:))
    }

    func list(_ archive: URL, password: String? = nil) async throws(EngineError) -> ArchiveListing {
        try await list(.file(archive), password: password)
    }

    /// `streamed` (the default) parses 7-Zip's output while it lists (#22); false parses it after,
    /// the way Stow did before, for the benchmark in PerformanceTests.
    func list(_ archive: ArchiveInput, password: String? = nil, streamed: Bool = true) async throws(EngineError) -> ArchiveListing {
        let input = try Prepared(archive)
        defer { input.cleanUp() }
        let stream = ListingStream()
        let onOutput: (@Sendable (Data) -> Void)? = streamed ? { chunk in stream.consume(chunk) } : nil
        let result = try await run(["l", "-slt", "-sccUTF-8", input.path], input: input.descriptor, password: password,
                                   onOutput: onOutput)
        try Self.check(result)
        let fast = streamed ? stream.finish() : Self.parseListingFast(result.output)
        guard var listing = fast?.listing ?? Self.parseListing(result.output) else {
            throw EngineError(.notAnArchive)
        }
        if Self.isTarball(name: (input.path as NSString).lastPathComponent),
           let entries = try? await tarballEntries(path: input.path, descriptor: input.descriptor) {
            listing.entries = entries // still "gzip", "xz"…: the format reads as TAR.GZ, TAR.XZ
            return listing
        }
        let legacy = fast?.legacy ?? []
        if !legacy.isEmpty {
            // Under a Latin-1 locale 7-Zip maps each byte of an unflagged name to the character with
            // the same number, so the bytes come back intact. Only for reading: the file system
            // rejects those names, so extraction keeps the UTF-8 locale and Stow renames afterwards.
            var latin1 = self
            latin1.locale = "en_US.ISO8859-1"
            let raw = try await latin1.run(["l", "-slt", "-sccUTF-8", input.path], input: input.descriptor,
                                           password: password)
            if raw.status == 0, let rawListing = Self.parseListing(raw.output),
               rawListing.entries.count == listing.entries.count {
                for index in legacy {
                    listing.entries[index].rawPath = rawListing.entries[index].path.data(using: .isoLatin1)
                }
            }
        }
        return listing
    }

    func extract(_ archive: URL, into directory: URL, paths: [String] = [], password: String? = nil,
                 progress: @escaping @Sendable (Double) -> Void) async throws(EngineError) -> [RemovedLink] {
        try await extract(.file(archive), into: directory, paths: paths, password: password, progress: progress)
    }

    /// Extracts with full paths into `directory`. `paths` empty means everything. Returns the links
    /// 7-Zip refused to create because they pointed outside; it leaves an empty placeholder file for
    /// each, which is removed here.
    func extract(_ archive: ArchiveInput, into directory: URL, paths: [String] = [], password: String? = nil,
                 progress: @escaping @Sendable (Double) -> Void) async throws(EngineError) -> [RemovedLink] {
        if Self.isTarball(name: archive.name) {
            return try await extractTarball(archive, into: directory, paths: paths, progress: progress)
        }

        let input = try Prepared(archive)
        defer { input.cleanUp() }
        // `-sns-`: on macOS 7-Zip would write HFS+/APFS extended attributes as extra files named
        // "file:com.apple.quarantine", which breaks the seal of every signed app in a disk image.
        var arguments = ["x", "-y", "-aou", "-sns-", "-bso0", "-bsp1", "-sccUTF-8", "-o" + directory.path]
        var listFile: URL?
        if !paths.isEmpty {
            // A list file instead of arguments: selections can exceed ARG_MAX. `-spd` makes `*` and
            // `?` in names literal.
            let file = FileManager.default.temporaryDirectory.appending(path: "stow-\(UUID().uuidString).txt")
            do {
                try paths.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
            } catch {
                throw EngineError(.failed, error.localizedDescription)
            }
            listFile = file
            arguments += ["-spd", "-scsUTF-8", input.path, "@" + file.path]
        } else {
            arguments.append(input.path)
        }
        defer { if let listFile { try? FileManager.default.removeItem(at: listFile) } }

        let parser = ProgressParser()
        let result = try await run(arguments, input: input.descriptor, password: password) { chunk in
            if let fraction = parser.consume(chunk) { progress(fraction) }
        }
        let refused = Self.refusedLinks(in: result.errors)
        for link in refused {
            let placeholder = directory.appending(path: link.path)
            if (try? placeholder.resourceValues(forKeys: [.fileSizeKey]).fileSize) == 0 {
                try? FileManager.default.removeItem(at: placeholder)
            }
        }
        // 7-Zip exits 2 when it refused a link; that alone is containment working, not a failure.
        let otherErrors = result.errors.split(whereSeparator: \.isNewline)
            .filter { $0.hasPrefix("ERROR:") && !$0.contains("Dangerous link path was ignored") }
        if result.status != 0, !(result.status == 2 && otherErrors.isEmpty && !refused.isEmpty) {
            try Self.check(result)
        }
        return refused
    }

    /// Reads every entry and checks it against the archive's checksums. Throws when data is damaged.
    /// `type` "dmg" checks a disk image's own block checksums (like `hdiutil verify`) rather than
    /// only the files inside its file system.
    func test(_ archive: ArchiveInput, type: String? = nil, password: String? = nil,
              progress: @escaping @Sendable (Double) -> Void) async throws(EngineError) {
        let input = try Prepared(archive)
        defer { input.cleanUp() }
        let parser = ProgressParser()
        let typeSwitch = type.map { ["-t" + $0] } ?? []
        let result = try await run(["t", "-bso0", "-bsp1", "-sccUTF-8"] + typeSwitch + [input.path], input: input.descriptor,
                                   password: password) { chunk in
            if let fraction = parser.consume(chunk) { progress(fraction) }
        }
        try Self.check(result)
    }

    // MARK: - Output parsing

    /// Parses `7zz l -slt`. Returns nil when the output has no archive section.
    static func parseListing(_ text: String) -> ArchiveListing? {
        var archiveFields: [String: String] = [:]
        var entries: [ListedEntry] = []
        var current: [String: String] = [:]
        var section = 0 // 0: preamble, 1: archive properties ("--"), 2: entries ("----------")

        func flush() {
            // Single-stream formats (xz, gzip, bzip2…) list their one item without a name.
            if section == 2, !current.isEmpty, current["Path"] == nil, let archive = archiveFields["Path"] {
                current["Path"] = innerName(of: archive)
            }
            if section == 2, let entry = entry(from: current) { entries.append(entry) }
            current = [:]
        }

        // Split on the byte: as Characters, "\r\n" is one unit, and names can end in "\r" ("Icon\r",
        // HFS+'s private folder) — those keep it; other lines lose a stray carriage return.
        for raw in text.utf8.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false) {
            let decoded = Substring(decoding: raw, as: UTF8.self)
            let line = decoded.hasSuffix("\r") && !decoded.hasPrefix("Path = ") ? decoded.dropLast() : decoded
            if line == "--" && section == 0 {
                section = 1
                continue
            }
            if line == "----------" && section == 1 {
                section = 2
                continue
            }
            guard section > 0 else { continue }
            if line.isEmpty {
                flush()
                continue
            }
            guard let separator = line.range(of: " = ") ?? line.range(of: " =", options: .anchored.union(.backwards)) else {
                continue
            }
            let key = String(line[..<separator.lowerBound])
            let value = String(line[separator.upperBound...])
            if section == 1 {
                archiveFields[key] = archiveFields[key] ?? value
            } else {
                if key == "Path" { flush() }
                current[key] = value
            }
        }
        flush()

        guard let type = archiveFields["Type"] else { return nil }
        return ArchiveListing(
            type: type,
            physicalSize: archiveFields["Physical Size"].flatMap { Int64($0) },
            entries: entries,
            startOffset: startOffset(archiveFields),
            tailSize: archiveFields["Tail Size"].flatMap { Int64($0) }
        )
    }

    /// Where the archive starts in the file. 7-Zip says "Offset" when it found the archive after
    /// other data, and "Embedded Stub Size" for a ZIP whose offsets already count a stub (SFX).
    static func startOffset(_ fields: [String: String]) -> Int64? {
        let offset = (fields["Offset"].flatMap { Int64($0) } ?? 0) + (fields["Embedded Stub Size"].flatMap { Int64($0) } ?? 0)
        return offset > 0 ? offset : nil
    }

    /// What 7-Zip names a compressed stream's content: "logs.tar.xz" → "logs.tar", "a.tgz" → "a.tar".
    static func innerName(of archive: String) -> String {
        let name = (archive as NSString).lastPathComponent
        let ext = (name as NSString).pathExtension.lowercased()
        let stem = (name as NSString).deletingPathExtension
        if ["tgz", "tbz", "tbz2", "txz", "tzst", "taz"].contains(ext) { return stem + ".tar" }
        return stem.isEmpty ? name : stem
    }

    private static func entry(from fields: [String: String]) -> ListedEntry? {
        guard let path = fields["Path"], !path.isEmpty else { return nil }
        let attributes = fields["Attributes"] ?? ""
        // "D drwxr-xr-x", " lrwxr-xr-x", "A -rw-r--r--": DOS flags, then a Unix mode string.
        // HFS+ and APFS images report the mode on its own ("Mode = lrwxr-xr-x") instead.
        let mode = fields["Mode"] ?? attributes.split(separator: " ").last.map(String.init) ?? ""
        let isFolder = fields["Folder"] == "+" || attributes.hasPrefix("D") || mode.hasPrefix("d")
        let link = fields["Symbolic Link"].flatMap { $0.isEmpty ? nil : $0 }
        return ListedEntry(
            path: path,
            isFolder: isFolder,
            isSymlink: link != nil || (mode.count == 10 && mode.hasPrefix("l")),
            linkTarget: link,
            size: fields["Size"].flatMap { Int64($0) } ?? 0,
            packedSize: fields["Packed Size"].flatMap { Int64($0) },
            modified: fields["Modified"].flatMap(parseDate),
            isEncrypted: fields["Encrypted"] == "+"
        )
    }

    /// "2026-10-20 00:13:47" or "2026-10-20 00:13:47.2028110", local time.
    static func parseDate(_ text: String) -> Date? {
        let parts = text.split(whereSeparator: { $0 == "-" || $0 == " " || $0 == ":" || $0 == "." })
        guard parts.count >= 6 else { return nil }
        let numbers = parts.prefix(6).compactMap { Int($0) }
        guard numbers.count == 6 else { return nil }
        var components = DateComponents(year: numbers[0], month: numbers[1], day: numbers[2],
                                        hour: numbers[3], minute: numbers[4], second: numbers[5])
        if parts.count > 6, let fraction = Double("0." + parts[6]) {
            components.nanosecond = Int(fraction * 1_000_000_000)
        }
        return Calendar(identifier: .gregorian).date(from: components)
    }

    /// "ERROR: Dangerous link path was ignored : Docs/link : ../../../etc/passwd"
    static func refusedLinks(in errors: String) -> [RemovedLink] {
        errors.split(whereSeparator: \.isNewline).compactMap { line in
            guard let range = line.range(of: "Dangerous link path was ignored : ") else { return nil }
            let rest = line[range.upperBound...]
            guard let separator = rest.range(of: " : ") else { return nil }
            return RemovedLink(path: PathContainment.containedPath(for: String(rest[..<separator.lowerBound])),
                               target: String(rest[separator.upperBound...]))
        }
    }

    static func check(_ result: RunResult) throws(EngineError) {
        guard result.status != 0 else { return }
        let all = result.output + "\n" + result.errors
        // Before damage: a wrong password on encrypted 7z contents reads
        // "Data Error in encrypted file. Wrong password? : …".
        if all.contains("Wrong password") { throw EngineError(.wrongPassword) }
        if let damaged = result.errors.split(whereSeparator: \.isNewline).first(where: { $0.contains("Data Error") || $0.contains("CRC Failed") }) {
            throw EngineError(.failed, String(damaged.drop { $0 != ":" }.dropFirst()).trimmingCharacters(in: .whitespaces))
        }
        // With `-bso0` the prompt itself isn't printed; 7-Zip reads EOF from standard input (the
        // only thing it reads there) and stops with "Break signaled". Cancelling never gets here.
        if all.contains("Enter password") || all.contains("Can not open encrypted archive")
            || all.contains("Break signaled") {
            throw EngineError(.passwordRequired)
        }
        if all.contains("Cannot open the file as") || all.contains("Can not open the file as")
            || all.contains("Is not archive") {
            throw EngineError(.notAnArchive)
        }
        let detail = result.errors.split(whereSeparator: \.isNewline)
            .first { $0.hasPrefix("ERROR:") }
            .map { String($0.dropFirst("ERROR:".count)).trimmingCharacters(in: .whitespaces) }
        throw EngineError(.failed, detail.map { String(localized: "7-Zip couldn’t finish: \($0)") })
    }

    // MARK: - Process

    struct RunResult: Sendable {
        var status: Int32
        var output: String
        var errors: String
    }

    /// Runs `7zz` to completion. Cancelling the calling task terminates it. A password, when given,
    /// is answered on standard input rather than put on the command line where `ps` could see it.
    /// `posix_spawn` rather than `Process`, which closes every descriptor but 0–2 in the child.
    /// `directory` is the child's working directory.
    func run(_ arguments: [String], input: Int32?, password: String?, in directory: URL? = nil,
             onOutput: (@Sendable (Data) -> Void)? = nil) async throws(EngineError) -> RunResult {
        var stdinPipe: [Int32] = [-1, -1], stdoutPipe: [Int32] = [-1, -1], stderrPipe: [Int32] = [-1, -1]
        guard pipe(&stdinPipe) == 0, pipe(&stdoutPipe) == 0, pipe(&stderrPipe) == 0 else {
            throw EngineError(.failed, String(cString: strerror(errno)))
        }
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, stdinPipe[0], 0)
        posix_spawn_file_actions_adddup2(&actions, stdoutPipe[1], 1)
        posix_spawn_file_actions_adddup2(&actions, stderrPipe[1], 2)
        // Duplicated above 3 first, so dup2 onto 3 never collides with the source.
        let spare = input.map { fcntl($0, F_DUPFD_CLOEXEC, 10) } ?? -1
        if spare >= 0 { posix_spawn_file_actions_adddup2(&actions, spare, 3) }
        if let directory { posix_spawn_file_actions_addchdir_np(&actions, directory.path) }
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT))

        let argv = ([executable.path] + arguments).map { strdup($0) } + [nil]
        let environment = ProcessInfo.processInfo.environment.merging(locale.map { ["LC_ALL": $0, "LANG": $0] } ?? [:]) { $1 }
            .map { strdup("\($0)=\($1)") } + [nil]
        defer { (argv + environment).forEach { free($0) } }
        var pid: pid_t = 0
        let spawned = posix_spawn(&pid, executable.path, &actions, &attributes, argv, environment)
        for fd in [stdinPipe[0], stdoutPipe[1], stderrPipe[1], spare] where fd >= 0 { close(fd) }
        let toChild = FileHandle(fileDescriptor: stdinPipe[1], closeOnDealloc: true)
        let fromChild = FileHandle(fileDescriptor: stdoutPipe[0], closeOnDealloc: true)
        let errorsFromChild = FileHandle(fileDescriptor: stderrPipe[0], closeOnDealloc: true)
        guard spawned == 0 else {
            throw spawned == ENOENT || spawned == EACCES
                ? EngineError(.engineMissing)
                : EngineError(.failed, String(cString: strerror(spawned)))
        }

        // Without a password, EOF makes 7-Zip give up at its prompt instead of waiting forever.
        if let password { try? toChild.write(contentsOf: Data((password + "\n").utf8)) }
        try? toChild.close()

        let collected = Mutex((output: Data(), errors: Data()))
        let outputDone = drain(fromChild) { chunk in
            collected.withLock { $0.output.append(chunk) }
            onOutput?(chunk)
        }
        let errorsDone = drain(errorsFromChild) { chunk in
            collected.withLock { $0.errors.append(chunk) }
        }

        let child = ChildProcess(pid)
        let status = await withTaskCancellationHandler {
            if Task.isCancelled { child.terminate() }
            let status = await child.exitStatus()
            await outputDone.value
            await errorsDone.value
            return status
        } onCancel: {
            child.terminate()
        }

        if Task.isCancelled { throw EngineError(.cancelled) }
        let (out, err) = collected.withLock { ($0.output, $0.errors) }
        return RunResult(status: status, output: String(decoding: out, as: UTF8.self),
                         errors: String(decoding: err, as: UTF8.self))
    }

    /// Reads a pipe until EOF on GCD's handler queue; the returned task finishes at EOF.
    private func drain(_ handle: FileHandle, _ onChunk: @escaping @Sendable (Data) -> Void) -> Task<Void, Never> {
        let stream = AsyncStream<Data> { continuation in
            handle.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    continuation.finish()
                } else {
                    continuation.yield(chunk)
                }
            }
        }
        return Task {
            for await chunk in stream { onChunk(chunk) }
        }
    }

    /// The archive as a path 7-Zip can open; for a descriptor, a link to `/dev/fd/3`.
    private struct Prepared {
        let path: String
        let descriptor: Int32?
        private let folder: URL?

        init(_ input: ArchiveInput) throws(EngineError) {
            switch input {
            case .file(let url):
                path = url.path
                descriptor = nil
                folder = nil
            case .descriptor(let handle, let name):
                let folder = FileManager.default.temporaryDirectory
                    .appending(path: "stow-in-\(UUID().uuidString)", directoryHint: .isDirectory)
                let safeName = (name as NSString).lastPathComponent
                let link = folder.appending(path: safeName.isEmpty || safeName == ".." ? "archive" : safeName)
                do {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "/dev/fd/3")
                } catch {
                    throw EngineError(.failed, error.localizedDescription)
                }
                path = link.path
                descriptor = handle.fileDescriptor
                self.folder = folder
            }
        }

        func cleanUp() {
            if let folder { try? FileManager.default.removeItem(at: folder) }
        }
    }
}

/// A spawned 7zz: waits for it off the cooperative pool, and stops it at most once while running.
private nonisolated final class ChildProcess: Sendable {
    private let pid: pid_t
    private let running = Mutex(true)

    init(_ pid: pid_t) { self.pid = pid }

    func exitStatus() async -> Int32 {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                var status: Int32 = 0
                while waitpid(self.pid, &status, 0) == -1, errno == EINTR {}
                self.running.withLock { $0 = false }
                // Normal exit → its code; killed by a signal → -1.
                continuation.resume(returning: status & 0x7f == 0 ? (status >> 8) & 0xff : -1)
            }
        }
    }

    func terminate() {
        running.withLock { if $0 { kill(pid, SIGTERM) } }
    }
}

/// `-bsp1` progress is a stream of backspace-erased fragments like "  4% 3 - big.bin".
nonisolated final class ProgressParser: Sendable {
    private let state = Mutex((pending: "", last: -1))

    /// Returns a new fraction when the percentage advanced.
    func consume(_ chunk: Data) -> Double? {
        state.withLock { state in
            state.pending += String(decoding: chunk, as: UTF8.self)
            let fragments = state.pending.split(omittingEmptySubsequences: false) {
                $0 == "\u{8}" || $0 == "\r" || $0 == "\n"
            }
            state.pending = fragments.last.map(String.init) ?? ""
            var latest: Int?
            for fragment in fragments.dropLast() {
                if let percent = Self.percent(in: fragment) { latest = percent }
            }
            guard let latest, latest > state.last else { return nil }
            state.last = latest
            return Double(latest) / 100
        }
    }

    private static func percent(in fragment: Substring) -> Int? {
        let trimmed = fragment.drop { $0 == " " }
        guard let end = trimmed.firstIndex(of: "%") else { return nil }
        return Int(trimmed[..<end]).flatMap { (0...100).contains($0) ? $0 : nil }
    }
}
