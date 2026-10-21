import Foundation

extension SevenZip {
    /// Packs everything inside `input` into `output` (which must exist and be empty). `work` holds the
    /// intermediate TAR of a compressed TAR. Links are stored as links (`-snl`), never followed.
    func create(_ request: CreateRequest, from input: URL, into output: URL, work: URL,
                progress: @escaping @Sendable (Double) -> Void) async throws(EngineError) -> CreateReport {
        if request.keepsMacMetadata, request.format == .zip {
            try MacMetadata.sequester(in: input)
        }
        let name = Self.safeName(request.archiveName)
        let archive = output.appending(path: name + "." + request.format.fileExtension)
        let steps = Self.createSteps(for: request, archive: archive, input: input, work: work)
        let weights = Self.weights(steps: steps.count, verify: request.verify)

        var done = 0.0
        for (index, step) in steps.enumerated() {
            let weight = weights[index]
            let start = done
            if let zstd = step.zstd {
                try await Zstd.compress(zstd.source, into: zstd.archive, level: zstd.level, volumeSize: zstd.volumeSize) { fraction in
                    progress(start + fraction * weight)
                }
                done += weight
                continue
            }
            let parser = ProgressParser()
            let result = try await run(step.arguments, input: nil, password: step.usesPassword ? request.password : nil,
                                       in: step.directory) { chunk in
                if let fraction = parser.consume(chunk) { progress(start + fraction * weight) }
            }
            try Self.checkCreated(result)
            done += weight
        }
        if let intermediate = steps.first?.intermediate { try? FileManager.default.removeItem(at: intermediate) }

        let files = ((try? FileManager.default.contentsOfDirectory(atPath: output.path)) ?? []).sorted()
        guard let first = files.first else { throw EngineError(.failed, String(localized: "7-Zip didn’t write an archive.")) }
        let size = files.reduce(Int64(0)) { total, file in
            total + Int64((try? output.appending(path: file).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        var report = CreateReport(files: files, size: size)

        if request.verify {
            let parser = ProgressParser()
            let start = done
            let result = try await run(["t", "-bso0", "-bsp1", "-sccUTF-8", "--", output.appending(path: first).path],
                                       input: nil, password: request.password) { chunk in
                if let fraction = parser.consume(chunk) { progress(start + fraction * (1 - start)) }
            }
            guard result.status == 0 else {
                throw EngineError(.failed, String(localized: "The new archive didn’t pass its check, so it wasn’t kept."))
            }
            report.verified = true
        }
        progress(1)
        return report
    }

    struct CreateStep: Equatable, Sendable {
        var arguments: [String]
        var directory: URL
        var usesPassword = false
        /// A file this step leaves for the next one.
        var intermediate: URL?
        /// Set when this step is Stow's own zstd compression rather than a `7zz` run.
        var zstd: ZstdStep?
    }

    struct ZstdStep: Equatable, Sendable {
        var source: URL
        var archive: URL
        var level: Int32
        var volumeSize: Int64?
    }

    /// The `7zz` runs that make `archive`: one, or a TAR then its compression.
    static func createSteps(for request: CreateRequest, archive: URL, input: URL, work: URL) -> [CreateStep] {
        var common = ["-bso0", "-bsp1", "-sccUTF-8"]
        if let threads = request.threads, threads > 0 { common.append("-mmt=\(threads)") }
        let volume = request.volumeSize.map { ["-v\($0)b"] } ?? []
        let level = "-mx\(request.level.rawValue)"
        // Run inside the input folder; `*` (7-Zip's own wildcard) picks up every name, dotfiles too.
        func add(_ type: String, _ switches: [String], to target: URL, _ sources: [String]) -> [String] {
            ["a", "-t" + type] + switches + common + ["--", target.path] + sources
        }

        switch request.format {
        case .zip, .sevenZip:
            var switches = [level, "-snl"]
            if request.format == .zip { switches.append("-mcu=on") }
            if request.password != nil {
                switches += request.format == .zip ? ["-mem=AES256", "-p"] : ["-mhe=on", "-p"]
            }
            let type = request.format == .zip ? "zip" : "7z"
            return [CreateStep(arguments: add(type, switches + volume, to: archive, ["*"]), directory: input,
                               usesPassword: request.password != nil)]
        case .tar:
            return [CreateStep(arguments: add("tar", ["-snl"] + volume, to: archive, ["*"]), directory: input)]
        case .tarZst:
            // 7zz writes the TAR; zstd isn't among the formats it can write, so Stow compresses it.
            let tarName = (archive.lastPathComponent as NSString).deletingPathExtension // "Project.tar"
            let tar = work.appending(path: tarName)
            return [
                CreateStep(arguments: add("tar", ["-snl"], to: tar, ["*"]), directory: input, intermediate: tar),
                CreateStep(arguments: [], directory: work,
                           zstd: ZstdStep(source: tar, archive: archive, level: Zstd.level(for: request.level),
                                          volumeSize: request.volumeSize)),
            ]
        case .tarGz, .tarBz2, .tarXz:
            let tarName = (archive.lastPathComponent as NSString).deletingPathExtension // "Project.tar"
            let tar = work.appending(path: tarName)
            let type = switch request.format {
            case .tarGz: "gzip"
            case .tarBz2: "bzip2"
            default: "xz"
            }
            return [
                CreateStep(arguments: add("tar", ["-snl"], to: tar, ["*"]), directory: input, intermediate: tar),
                CreateStep(arguments: add(type, [level] + volume, to: archive, [tar.path]), directory: work),
            ]
        }
    }

    /// Share of the progress bar per step; a check afterwards takes the last part.
    private static func weights(steps: Int, verify: Bool) -> [Double] {
        let available = verify ? 0.85 : 1.0
        // Writing a TAR is copying; compressing it is the work.
        return steps == 2 ? [available * 0.25, available * 0.75] : [available]
    }

    /// "Project" stays; anything that could leave the output folder becomes "Archive".
    static func safeName(_ name: String) -> String {
        let last = (name as NSString).lastPathComponent
        return last.isEmpty || last == "." || last == ".." || name.contains("/") ? "Archive" : last
    }

    /// 7-Zip exits 1 for warnings, e.g. a file it couldn't read. A partial archive isn't a success.
    private static func checkCreated(_ result: RunResult) throws(EngineError) {
        guard result.status != 0 else { return }
        let detail = (result.errors + "\n" + result.output).split(whereSeparator: \.isNewline)
            .first { $0.hasPrefix("ERROR:") || $0.hasPrefix("WARNING:") }
            .map { line in
                line.drop { $0 != ":" }.dropFirst().trimmingCharacters(in: .whitespaces)
            }
        throw EngineError(.failed, detail.map { String(localized: "Couldn’t create the archive: \($0)") }
            ?? String(localized: "Couldn’t create the archive."))
    }
}
