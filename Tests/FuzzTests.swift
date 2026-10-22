import Foundation
import Synchronization
import Testing
@testable import Stow

/// Fuzzing malformed archives (#37): seed archives in every family Stow opens most (ZIP, 7Z, TAR and
/// its compressed forms, RAR 4 and 5, DMG) are truncated, bit-flipped, header- and trailer-corrupted,
/// given absurd length fields and spliced, then fed to the bundled 7zz directly (crash and hang
/// detection) and to the sandboxed engine (clean errors, the connection survives, extraction stays
/// inside its folder). Deterministic: the same seed and iteration count always produce the same
/// mutants. Normal CI runs `FuzzConfig.default`; `.github/workflows/fuzz.yml` runs longer with
/// `STOW_FUZZ_ITERATIONS`, `STOW_FUZZ_SEED` and `STOW_FUZZ_MINUTES` (passed as `TEST_RUNNER_…`).
/// Failing inputs are kept in the test host's temporary folder under `StowFuzzFindings/`.
@Suite("Fuzzing malformed archives", .serialized)
struct FuzzTests {
    // MARK: - The mutator

    @Test func mutatorIsDeterministicAndAlwaysChangesTheInput() {
        let seed = Data((0 ..< 4096).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) })
        for index in 0 ..< 60 {
            let first = Mutator.mutant(of: seed, name: "seed.zip", index: index, seed: 1)
            let again = Mutator.mutant(of: seed, name: "seed.zip", index: index, seed: 1)
            #expect(first.data == again.data && first.label == again.label)
            #expect(first.data != seed, "\(first.label) left the input unchanged")
            if case .truncate = Mutator.Kind(index: index) { #expect(first.data.count < seed.count) }
        }
        let other = (0 ..< 60).map { Mutator.mutant(of: seed, name: "seed.zip", index: $0, seed: 2).data }
        let base = (0 ..< 60).map { Mutator.mutant(of: seed, name: "seed.zip", index: $0, seed: 1).data }
        #expect(other != base, "a different run seed must give different mutants")
        #expect(Mutator.mutant(of: Data([1]), name: "tiny", index: 0, seed: 1).data.isEmpty)
    }

    // MARK: - Seeds

    @Test func everySeedOpens() async throws {
        let corpus = try await Corpus.make()
        defer { corpus.folder.cleanUp() }
        #expect(corpus.seeds.count >= 12)
        var families = Set<String>()
        for seed in corpus.seeds {
            let listing = try await ArchiveEngine.shared.list(seed)
            #expect(!listing.entries.isEmpty, "\(seed.lastPathComponent) listed nothing")
            families.insert(Corpus.family(of: seed))
        }
        #expect(families.isSuperset(of: ["zip", "7z", "tar", "rar", "dmg"]))
    }

    // MARK: - 7-Zip itself

    @Test(.timeLimit(.minutes(60)))
    func sevenZipNeverCrashesOrHangsOnMutants() async throws {
        let corpus = try await Corpus.make()
        defer { corpus.folder.cleanUp() }
        let sevenZip = try #require(SevenZip.bundled()).executable
        let config = FuzzConfig.current
        var findings: [String] = []
        var runs = 0
        for (input, label) in corpus.cases(config) {
            if config.isOverBudget { break }
            for arguments in [["l", "-slt"], ["t"]] {
                let outcome = await Self.run(sevenZip, arguments + ["-pfuzz", "-y", "-bso0", "-bse0", "-bsp0", input.path],
                                             seconds: config.secondsPerRun)
                runs += 1
                switch outcome {
                case .exited: break
                case .signal(let signal):
                    findings.append("7zz \(arguments[0]) crashed with signal \(signal) on \(label)")
                    Findings.keep(input, label)
                case .hung:
                    findings.append("7zz \(arguments[0]) ran past \(Int(config.secondsPerRun)) s on \(label)")
                    Findings.keep(input, label)
                }
            }
        }
        print("Fuzz: 7zz ran \(runs) times over \(corpus.seeds.count) seeds, \(findings.count) findings")
        #expect(runs > 0)
        #expect(findings.isEmpty, "\(findings.joined(separator: "\n"))")
    }

    // MARK: - The engine

    @Test(.timeLimit(.minutes(60)))
    func engineFailsCleanlyOnMutants() async throws {
        let corpus = try await Corpus.make()
        defer { corpus.folder.cleanUp() }
        let config = FuzzConfig.current
        var findings: [String] = []
        var listed = 0, refused = 0
        for (input, label) in corpus.cases(config) {
            if config.isOverBudget { break }
            let result = await Self.listing(input, seconds: config.secondsPerRun)
            switch result {
            case nil:
                findings.append("engine listing ran past \(Int(config.secondsPerRun)) s on \(label)")
                Findings.keep(input, label)
            case .success(let listing)?:
                listed += 1
                // Stow's own model of the listing (tree, names, Checkup) must cope as well.
                _ = Archive(listing: listing, url: input).checkup
            case .failure(let error)?:
                refused += 1
                if !Self.cleanFailures.contains(error.failure) {
                    findings.append("engine failed with \(error.failure) (\(error.message)) on \(label)")
                    Findings.keep(input, label)
                }
            }
        }
        // Whatever happened above, the engine still answers.
        let healthy = try #require(corpus.seeds.first)
        let after = try await ArchiveEngine.shared.list(healthy)
        #expect(!after.entries.isEmpty)
        print("Fuzz: engine listed \(listed) mutants and refused \(refused), \(findings.count) findings")
        #expect(listed + refused > 0)
        #expect(findings.isEmpty, "\(findings.joined(separator: "\n"))")
    }

    @Test(.timeLimit(.minutes(60)))
    func extractingMutantsStaysInsideTheFolder() async throws {
        let corpus = try await Corpus.make()
        defer { corpus.folder.cleanUp() }
        let config = FuzzConfig.current
        var findings: [String] = []
        var extracted = 0, attempted = 0
        for (input, label) in corpus.cases(config) {
            if config.isOverBudget || attempted >= config.maxExtractions { break }
            guard case .success(let listing)? = await Self.listing(input, seconds: config.secondsPerRun) else { continue }
            attempted += 1
            let jail = corpus.folder.url.appending(path: "Jail-\(attempted)", directoryHint: .isDirectory)
            let out = jail.appending(path: "Out", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            let archive = Archive(listing: listing, url: input)
            let result = await Self.withDeadline(config.secondsPerRun * 2) { @MainActor () -> EngineError? in
                do { _ = try await Extraction.run(archive, selection: nil, to: out) { _ in }; return nil } catch { return EngineError(error) }
            }
            switch result {
            case nil:
                findings.append("extraction ran past \(Int(config.secondsPerRun * 2)) s on \(label)")
                Findings.keep(input, label)
            case let error??:
                if !Self.cleanFailures.contains(error.failure) {
                    findings.append("extraction failed with \(error.failure) (\(error.message)) on \(label)")
                    Findings.keep(input, label)
                }
                // A failed extraction leaves the folder as it was: no half-written staging folder.
                let leftovers = TemporaryFolder.contents(of: out).filter { $0.hasPrefix(".stow-staging-") && !$0.contains("/") }
                if !leftovers.isEmpty {
                    findings.append("failed extraction of \(label) left \(leftovers.joined(separator: ", ")) behind")
                    Findings.keep(input, label)
                }
            case .some(nil):
                extracted += 1
            }
            let escapes = Containment.problems(jail: jail, out: out)
            if !escapes.isEmpty {
                findings.append("extraction of \(label) escaped: \(escapes.joined(separator: ", "))")
                Findings.keep(input, label)
            }
            try? FileManager.default.removeItem(at: jail)
        }
        print("Fuzz: extracted \(extracted) of \(attempted) listable mutants, \(findings.count) findings")
        #expect(attempted > 0)
        #expect(findings.isEmpty, "\(findings.joined(separator: "\n"))")
    }

    /// Malformed RARs from libarchive's regression suite (each once crashed or hung a RAR reader).
    @Test(.timeLimit(.minutes(10)))
    func knownBadRARsFailCleanly() async throws {
        let corpus = try await Corpus.make()
        defer { corpus.folder.cleanUp() }
        let sevenZip = try #require(SevenZip.bundled()).executable
        let config = FuzzConfig.current
        #expect(corpus.knownBad.count >= 8)
        var findings: [String] = []
        for input in corpus.knownBad {
            let name = input.lastPathComponent
            for arguments in [["l", "-slt"], ["t"]] {
                let outcome = await Self.run(sevenZip, arguments + ["-pfuzz", "-y", "-bso0", "-bse0", "-bsp0", input.path],
                                             seconds: config.secondsPerRun)
                if case .exited = outcome { continue }
                findings.append("7zz \(arguments[0]) \(outcome) on \(name)")
            }
            let result = await Self.withDeadline(config.secondsPerRun) { @MainActor () -> EngineError? in
                do { _ = try await ArchiveEngine.shared.list(input); return nil } catch { return EngineError(error) }
            }
            switch result {
            case nil: findings.append("engine listing hung on \(name)")
            case let error??: if !Self.cleanFailures.contains(error.failure) { findings.append("engine \(error.failure) on \(name)") }
            case .some(nil): break
            }
        }
        #expect(findings.isEmpty, "\(findings.joined(separator: "\n"))")
    }

    // MARK: - Helpers

    /// Ways an engine call may fail on a malformed archive. `.connectionLost` (the engine crashed),
    /// `.engineMissing`, `.incompatibleVersion` and `.cancelled` never may.
    static let cleanFailures: Set<EngineFailure> = [.notAnArchive, .failed, .passwordRequired, .wrongPassword]

    enum Outcome: CustomStringConvertible {
        case exited(Int32)
        case signal(Int32)
        case hung
        var description: String {
            switch self {
            case .exited(let status): "exited \(status)"
            case .signal(let signal): "crashed (signal \(signal))"
            case .hung: "hung"
            }
        }
    }

    /// Runs a tool with no input or output, killing it after `seconds`.
    static func run(_ tool: URL, _ arguments: [String], seconds: Double) async -> Outcome {
        let process = Process()
        process.executableURL = tool
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return .exited(-1) }
        let deadline = ContinuousClock.now + .milliseconds(Int(seconds * 1000))
        while process.isRunning, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(2))
        }
        if process.isRunning {
            process.terminate()
            try? await Task.sleep(for: .milliseconds(200))
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            return .hung
        }
        return process.terminationReason == .uncaughtSignal ? .signal(process.terminationStatus) : .exited(process.terminationStatus)
    }

    /// The engine's listing (or its error), or nil if it took longer than `seconds`.
    static func listing(_ input: URL, seconds: Double) async -> Result<ArchiveListing, EngineError>? {
        await withDeadline(seconds) { @MainActor () -> Result<ArchiveListing, EngineError> in
            do { return .success(try await ArchiveEngine.shared.list(input)) } catch { return .failure(EngineError(error)) }
        }
    }

    /// The operation's value, or nil if it took longer than `seconds` (it is then left to finish on
    /// its own: engine listings can't be cancelled midway).
    static func withDeadline<T: Sendable>(_ seconds: Double, _ operation: @escaping @Sendable () async -> T) async -> T? {
        let slot = Slot<T>()
        let task = Task { slot.set(await operation()) }
        let deadline = ContinuousClock.now + .milliseconds(Int(seconds * 1000))
        while ContinuousClock.now < deadline {
            if let value = slot.value { return value }
            try? await Task.sleep(for: .milliseconds(2))
        }
        task.cancel()
        return slot.value
    }
}

private nonisolated final class Slot<T: Sendable>: Sendable {
    private let storage = Mutex<T?>(nil)
    var value: T? { storage.withLock { $0 } }
    func set(_ value: T) { storage.withLock { $0 = value } }
}

// MARK: - Configuration

nonisolated struct FuzzConfig: Sendable {
    /// Mutants per seed.
    var iterations: Int
    var seed: UInt64
    var secondsPerRun: Double
    /// Extractions per run (each is a full engine round trip, the slowest step).
    var maxExtractions: Int
    var deadline: ContinuousClock.Instant?

    /// Normal CI: about 15 mutants of each of ~14 seeds, every mutation kind twice over.
    static let `default` = FuzzConfig(iterations: 15, seed: 0x5704_F022, secondsPerRun: 20, maxExtractions: 60, deadline: nil)

    static var current: FuzzConfig {
        let environment = ProcessInfo.processInfo.environment
        var config = FuzzConfig.default
        if let value = environment["STOW_FUZZ_ITERATIONS"].flatMap(Int.init), value > 0 {
            config.iterations = value
            config.maxExtractions = max(config.maxExtractions, value * 4)
        }
        if let text = environment["STOW_FUZZ_SEED"], let value = UInt64(text) ?? UInt64(text.replacingOccurrences(of: "0x", with: ""), radix: 16) {
            config.seed = value
        }
        if let minutes = environment["STOW_FUZZ_MINUTES"].flatMap(Double.init), minutes > 0 {
            // Shared by the three mutant tests, which run one after another.
            config.deadline = ContinuousClock.now + .seconds(Int(minutes * 60 / 3))
        }
        return config
    }

    var isOverBudget: Bool { deadline.map { ContinuousClock.now >= $0 } ?? false }
}

// MARK: - Mutations

nonisolated enum Mutator {
    nonisolated enum Kind: CaseIterable, Equatable {
        case truncate, flipBits, corruptHeader, corruptTrailer, lengthBomb, splice, zeroRun

        init(index: Int) { self = Self.allCases[index % Self.allCases.count] }
    }

    /// The `index`-th mutant of `data`. `name` keeps seeds apart; `seed` picks the run.
    static func mutant(of data: Data, name: String, index: Int, seed: UInt64) -> (data: Data, label: String) {
        var random = SplitMix64(seed: seed ^ fnv1a(name) ^ UInt64(index) &* 0x9E37_79B9_7F4A_7C15)
        var bytes = [UInt8](data)
        let kind = Kind(index: index)
        guard bytes.count > 1 else { return (Data(), "\(name)#\(index) emptied") }
        let detail: String
        switch kind {
        case .truncate:
            let length = Int.random(in: 0 ..< bytes.count, using: &random)
            bytes.removeSubrange(length...)
            detail = "truncated to \(length) bytes"
        case .flipBits:
            let count = Int.random(in: 1 ... 8, using: &random)
            var offsets: [Int] = []
            for _ in 0 ..< count {
                let offset = Int.random(in: 0 ..< bytes.count, using: &random)
                bytes[offset] ^= 1 << UInt8.random(in: 0 ... 7, using: &random)
                offsets.append(offset)
            }
            detail = "bits flipped at \(offsets.map(String.init).joined(separator: ","))"
        case .corruptHeader, .corruptTrailer:
            let window = min(bytes.count, kind == .corruptHeader ? 64 : 512)
            let start = kind == .corruptHeader ? 0 : bytes.count - window
            let length = min(window, Int.random(in: 1 ... 16, using: &random))
            let offset = start + Int.random(in: 0 ... window - length, using: &random)
            for position in offset ..< offset + length { bytes[position] = UInt8.random(in: 0 ... 255, using: &random) }
            detail = "\(kind == .corruptHeader ? "header" : "trailer") bytes \(offset)..<\(offset + length) randomised"
        case .lengthBomb:
            // Sizes, counts and offsets are 4- or 8-byte fields; make one enormous or negative.
            let width = Bool.random(using: &random) ? 4 : 8
            guard bytes.count >= width else { bytes[0] ^= 0xFF; detail = "first byte inverted"; break }
            let offset = Int.random(in: 0 ... bytes.count - width, using: &random)
            let value: UInt8 = [0xFF, 0x7F, 0x80][Int.random(in: 0 ... 2, using: &random)]
            for position in offset ..< offset + width { bytes[position] = position == offset + width - 1 ? value : 0xFF }
            detail = "\(width)-byte field at \(offset) set huge"
        case .splice:
            let offset = Int.random(in: 0 ..< bytes.count, using: &random)
            let length = min(bytes.count - offset, Int.random(in: 1 ... 64, using: &random))
            if Bool.random(using: &random) {
                bytes.removeSubrange(offset ..< offset + length)
                detail = "\(length) bytes cut at \(offset)"
            } else {
                let chunk = Array(bytes[offset ..< offset + length])
                bytes.insert(contentsOf: chunk, at: offset)
                detail = "\(length) bytes repeated at \(offset)"
            }
        case .zeroRun:
            let offset = Int.random(in: 0 ..< bytes.count, using: &random)
            let length = min(bytes.count - offset, Int.random(in: 1 ... 256, using: &random))
            let before = Array(bytes[offset ..< offset + length])
            for position in offset ..< offset + length { bytes[position] = 0 }
            if before.allSatisfy({ $0 == 0 }) { bytes[offset] = 0xA5 }
            detail = "\(length) bytes zeroed at \(offset)"
        }
        var result = Data(bytes)
        if result == data { result.append(0x5A) } // a mutation that cancelled itself out
        return (result, "\(name)#\(index) (\(detail))")
    }

    static func fnv1a(_ text: String) -> UInt64 {
        text.utf8.reduce(UInt64(0xCBF2_9CE4_8422_2325)) { ($0 ^ UInt64($1)) &* 0x0000_0100_0000_01B3 }
    }
}

nonisolated struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Corpus

struct Corpus {
    let folder: TemporaryFolder
    /// Well-formed archives to mutate.
    let seeds: [URL]
    /// Already-malformed inputs, tested as they are.
    let knownBad: [URL]

    static func family(of url: URL) -> String {
        let name = url.lastPathComponent.lowercased()
        if name.contains(".tar") { return "tar" }
        return url.pathExtension.lowercased()
    }

    /// Writes the mutants of every seed for `config`, one at a time, into the corpus folder.
    func cases(_ config: FuzzConfig) -> some Sequence<(URL, String)> {
        let mutants = folder.url.appending(path: "Mutants", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: mutants, withIntermediateDirectories: true)
        let pairs = (0 ..< config.iterations).flatMap { index in seeds.map { (index, $0) } }
        return pairs.lazy.compactMap { index, seed -> (URL, String)? in
            guard let data = try? Data(contentsOf: seed) else { return nil }
            let mutant = Mutator.mutant(of: data, name: seed.lastPathComponent, index: index, seed: config.seed)
            // Same extension, so Stow picks the same reader the real file would get.
            let url = mutants.appending(path: "m\(index)-\(seed.lastPathComponent)")
            guard (try? mutant.data.write(to: url)) != nil else { return nil }
            return (url, mutant.label)
        }
    }

    static func make() async throws -> Corpus {
        let folder = try TemporaryFolder()
        let sevenZip = try #require(SevenZip.bundled()).executable
        let content = folder.url.appending(path: "Content", directoryHint: .isDirectory)
        let docs = content.appending(path: "Docs", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        try Data(String(repeating: "Stow fuzz seed. ", count: 256).utf8).write(to: docs.appending(path: "readme.txt"))
        var random = SplitMix64(seed: 37)
        try Data((0 ..< 2048).map { _ in UInt8.random(in: 0 ... 255, using: &random) }).write(to: docs.appending(path: "data.bin"))
        try Data().write(to: content.appending(path: "empty.txt"))
        try FileManager.default.createSymbolicLink(atPath: docs.appending(path: "link").path, withDestinationPath: "readme.txt")

        let seeds = folder.url.appending(path: "Seeds", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: seeds, withIntermediateDirectories: true)
        func pack(_ name: String, _ extra: [String] = [], inputs: [String] = ["Docs", "empty.txt"], in directory: URL) throws -> URL {
            let url = seeds.appending(path: name)
            let process = Process()
            process.executableURL = sevenZip
            process.arguments = ["a", "-bso0", "-bse0", "-bsp0", "-snl"] + extra + [url.path] + inputs
            process.currentDirectoryURL = directory
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            try #require(process.terminationStatus == 0, "7zz couldn't make \(name)")
            return url
        }
        var made = [
            try pack("seed.zip", in: content),
            try pack("seed-deflate64.zip", ["-mm=Deflate64"], in: content),
            try pack("seed.7z", in: content),
            try pack("seed-solid-lzma2.7z", ["-ms=on", "-mx=9"], in: content),
            try pack("seed.tar", in: content),
        ]
        for (name, type) in [("seed.tar.gz", "gzip"), ("seed.tar.bz2", "bzip2"), ("seed.tar.xz", "xz")] {
            made.append(try pack(name, ["-t\(type)"], inputs: ["seed.tar"], in: seeds))
        }
        // Entries no archiver would write, so mutations start from containment's edge cases.
        let crafted = seeds.appending(path: "seed-crafted.zip")
        try ZipFixture(entries: [
            .file("../escape.txt", "up"),
            .file("/absolute.txt", "root"),
            .file("Docs/ok.txt", "fine"),
            .symlink("Docs/out", to: "../../../outside"),
            .folder("Docs/Sub"),
        ]).write(to: crafted)
        made.append(crafted)

        let fixtures = try #require(Bundle(for: FuzzFixtureLocator.self).url(forResource: "Fixtures", withExtension: nil))
        let fuzz = fixtures.appending(path: "Fuzz", directoryHint: .isDirectory)
        let shipped = try FileManager.default.contentsOfDirectory(atPath: fuzz.path).sorted()
        for name in shipped where name.hasPrefix("seed-") {
            let copy = seeds.appending(path: name)
            try FileManager.default.copyItem(at: fuzz.appending(path: name), to: copy)
            made.append(copy)
        }
        for name in ["Fixture-HFS.dmg", "Fixture-APFS.dmg"] {
            let copy = seeds.appending(path: "seed-" + name)
            try FileManager.default.copyItem(at: fixtures.appending(path: name), to: copy)
            made.append(copy)
        }
        let bad = folder.url.appending(path: "KnownBad", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: bad, withIntermediateDirectories: true)
        var knownBad: [URL] = []
        for name in shipped where name.hasPrefix("bad-") {
            let copy = bad.appending(path: name)
            try FileManager.default.copyItem(at: fuzz.appending(path: name), to: copy)
            knownBad.append(copy)
        }
        return Corpus(folder: folder, seeds: made, knownBad: knownBad)
    }
}

private final class FuzzFixtureLocator {}

// MARK: - Containment and findings

enum Containment {
    /// What an extraction left outside `out`, or links inside it that lead out, or set-ID bits.
    static func problems(jail: URL, out: URL) -> [String] {
        var problems: [String] = []
        let siblings = (try? FileManager.default.contentsOfDirectory(atPath: jail.path)) ?? []
        for name in siblings where name != out.lastPathComponent { problems.append("left \(name) beside the folder") }
        for relative in TemporaryFolder.contents(of: out) {
            let path = out.appending(path: relative).path
            var info = stat()
            guard lstat(path, &info) == 0 else { continue }
            if info.st_mode & S_IFMT == S_IFLNK {
                let target = (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) ?? ""
                if PathContainment.linkEscapes(linkPath: relative, target: target) {
                    problems.append("\(relative) → \(target)")
                }
            }
            if info.st_mode & 0o6000 != 0 { problems.append("\(relative) is set-ID") }
            if PathContainment.escapes(relative) { problems.append("\(relative) is outside") }
        }
        return problems
    }
}

nonisolated enum Findings {
    /// Keeps a failing input for the workflow to upload (the test host's temporary folder).
    static func keep(_ input: URL, _ label: String) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "StowFuzzFindings", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = String(UUID().uuidString.prefix(8)) + "-" + input.lastPathComponent
        try? FileManager.default.copyItem(at: input, to: folder.appending(path: name))
        try? Data(label.utf8).write(to: folder.appending(path: name + ".txt"))
        print("Fuzz finding kept: \(folder.appending(path: name).path) — \(label)")
    }
}
