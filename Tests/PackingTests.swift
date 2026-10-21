import Foundation
import Synchronization
import Testing
@testable import Stow

/// A folder to pack: text, a script, a link, a Finder file, a name Windows rejects, and a tag.
private struct SourceTree {
    let folder: TemporaryFolder
    var project: URL { folder.url.appending(path: "Project", directoryHint: .isDirectory) }

    init() throws {
        folder = try TemporaryFolder()
        let fileManager = FileManager.default
        let project = folder.url.appending(path: "Project", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: project.appending(path: "Docs"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: project.appending(path: "Empty"), withIntermediateDirectories: true)
        try Data(String(repeating: "Read me. ", count: 400).utf8).write(to: project.appending(path: "README.md"))
        try Data("a".utf8).write(to: project.appending(path: "Docs/a.txt"))
        try Data("#!/bin/sh\necho hi\n".utf8).write(to: project.appending(path: "run.sh"))
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: project.appending(path: "run.sh").path)
        try Data("final".utf8).write(to: project.appending(path: "Q3: Final?.txt"))
        try Data([0, 0, 0, 1]).write(to: project.appending(path: ".DS_Store"))
        try fileManager.createSymbolicLink(atPath: project.appending(path: "link").path, withDestinationPath: "README.md")
        let tag = Array("bplist00-tag".utf8)
        setxattr(project.appending(path: "README.md").path, "com.apple.metadata:_kMDItemUserTags", tag, tag.count, 0, 0)
    }

    func cleanUp() { folder.cleanUp() }
}

@MainActor
private func pack(_ tree: SourceTree, audience: Audience, format: PackFormat, password: String? = nil,
                  volumeSize: Int64? = nil, verify: Bool = false, overrides: [String: String] = [:],
                  conflict: ArchiveCreation.Conflict = .keepBoth,
                  into destination: URL) async throws -> (ArchiveCreation.Result, PackReport) {
    let request = PackRequest.collect([tree.project])
    var options = PackOptions()
    options.setAudience(audience)
    options.setFormat(format)
    options.usesPassword = password != nil
    let report = Compatibility.report(for: request.files, options: options, password: password ?? "", overrides: overrides)
    let metadata = audience.keepsMacMetadata && format == .zip
    let create = CreateRequest(operationID: UUID().uuidString, archiveName: "Project", format: format,
                               password: password, volumeSize: volumeSize, keepsMacMetadata: metadata, verify: verify)
    let result = try await ArchiveCreation.run(report.items, totalBytes: report.totalBytes, attributes: metadata,
                                               request: create, named: "Project", in: destination,
                                               conflict: conflict) { _ in }
    return (result, report)
}

@Suite("Packing", .enabled(if: SevenZip.bundled() != nil, "7zz isn't bundled — run scripts/fetch-7zip.sh"))
@MainActor
struct PackingTests {
    @Test(arguments: PackFormat.allCases)
    func roundTripsThroughEveryFormat(format: PackFormat) async throws {
        let tree = try SourceTree()
        defer { tree.cleanUp() }
        let out = tree.folder.url.appending(path: "Out", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: false)

        let (result, _) = try await pack(tree, audience: .linux, format: format, verify: true, into: out)

        #expect(result.placed.map(\.lastPathComponent) == ["Project." + format.fileExtension])
        #expect(result.report.verified)
        // Compressed TARs list as the TAR inside, like every other archive.
        let archiveURL = result.placed[0]
        let listing = try await ArchiveEngine.shared.list(archiveURL)
        let paths = Set(listing.entries.map(\.path))
        #expect(paths.isSuperset(of: ["Project", "Project/README.md", "Project/Docs/a.txt", "Project/Empty",
                                      "Project/run.sh", "Project/link", "Project/Q3: Final?.txt"]))
        #expect(!paths.contains("Project/.DS_Store"))
        #expect(listing.entries.first { $0.path == "Project/link" }?.isSymlink == true)

        let archive = Archive(listing: listing, url: archiveURL)
        let extracted = try await Extraction.run(archive, selection: nil, to: out) { _ in }
        let root = try #require(extracted.placed.first)
        #expect(try String(contentsOf: root.appending(path: "Docs/a.txt"), encoding: .utf8) == "a")
        let mode = try FileManager.default.attributesOfItem(atPath: root.appending(path: "run.sh").path)[.posixPermissions] as? Int
        #expect(mode == 0o755)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: root.appending(path: "link").path) == "README.md")
    }

    @Test(arguments: [PackFormat.zip, .sevenZip])
    func encryptedArchivesNeedTheRightPassword(format: PackFormat) async throws {
        let tree = try SourceTree()
        defer { tree.cleanUp() }
        let out = tree.folder.url.appending(path: "Out", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: false)
        let (result, _) = try await pack(tree, audience: .windows, format: format, password: "correct horse", into: out)
        let archive = result.placed[0]
        let sevenZip = try #require(SevenZip.bundled())

        if format == .sevenZip {
            // File names are encrypted too: nothing to list without the password.
            await #expect(throws: EngineError(.passwordRequired)) { try await sevenZip.list(archive) }
        } else {
            let listing = try await sevenZip.list(archive)
            #expect(listing.entries.first { $0.path == "Project/README.md" }?.isEncrypted == true)
        }
        let wrong = out.appending(path: "wrong", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: wrong, withIntermediateDirectories: false)
        await #expect(throws: EngineError(.wrongPassword)) {
            _ = try await sevenZip.extract(archive, into: wrong, password: "battery staple") { _ in }
        }
        let right = out.appending(path: "right", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: right, withIntermediateDirectories: false)
        _ = try await sevenZip.extract(archive, into: right, password: "correct horse") { _ in }
        #expect(try String(contentsOf: right.appending(path: "Project/Docs/a.txt"), encoding: .utf8) == "a")
    }

    @Test func splitsIntoVolumes() async throws {
        let tree = try SourceTree()
        defer { tree.cleanUp() }
        var noise = [UInt8](repeating: 0, count: 300_000)
        for index in noise.indices { noise[index] = UInt8.random(in: 0...255) }
        try Data(noise).write(to: tree.project.appending(path: "noise.bin"))
        let out = tree.folder.url.appending(path: "Out", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: false)

        let (result, _) = try await pack(tree, audience: .windows, format: .sevenZip, volumeSize: 100_000,
                                         verify: true, into: out)

        #expect(result.placed.map(\.lastPathComponent) == ["Project.7z.001", "Project.7z.002", "Project.7z.003", "Project.7z.004"])
        #expect(result.report.verified)
        let sevenZip = try #require(SevenZip.bundled())
        let back = out.appending(path: "back", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: back, withIntermediateDirectories: false)
        _ = try await sevenZip.extract(result.placed[0], into: back) { _ in }
        #expect(try Data(contentsOf: back.appending(path: "Project/noise.bin")) == Data(noise))
    }

    @Test func windowsGetsSafeNamesAndNoMacFiles() async throws {
        let tree = try SourceTree()
        defer { tree.cleanUp() }
        let out = tree.folder.url.appending(path: "Out", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: false)

        let (result, report) = try await pack(tree, audience: .windows, format: .zip,
                                              overrides: ["Project/Docs": "Documents"], into: out)

        #expect(report.renames.map(\.to).sorted() == ["Documents", "Q3- Final-.txt"])
        #expect(report.excluded.map(\.path) == ["Project/.DS_Store"])
        #expect(report.leftOutLinks.map(\.path) == ["Project/link"])
        let listing = try await ArchiveEngine.shared.list(result.placed[0])
        let paths = Set(listing.entries.map(\.path))
        #expect(paths.contains("Project/Q3- Final-.txt"))
        #expect(paths.contains("Project/Documents/a.txt"))
        #expect(!paths.contains { $0.contains(".DS_Store") || $0.contains("__MACOSX") || $0.hasSuffix("link") })
    }

    @Test func macKeepsTagsAsAppleDouble() async throws {
        let tree = try SourceTree()
        defer { tree.cleanUp() }
        let out = tree.folder.url.appending(path: "Out", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: false)

        let (result, report) = try await pack(tree, audience: .mac, format: .zip, into: out)

        #expect(report.renames.isEmpty && report.excluded.isEmpty && report.leftOutLinks.isEmpty)
        let sevenZip = try #require(SevenZip.bundled())
        let back = out.appending(path: "back", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: back, withIntermediateDirectories: false)
        _ = try await sevenZip.extract(result.placed[0], into: back) { _ in }
        let double = try Data(contentsOf: back.appending(path: "__MACOSX/Project/._README.md"))
        #expect(double.prefix(4) == Data([0x00, 0x05, 0x16, 0x07]))
        #expect(double.range(of: Data("_kMDItemUserTags".utf8)) != nil)
        #expect(double.range(of: Data("com.apple.provenance".utf8)) == nil)
        #expect(FileManager.default.fileExists(atPath: back.appending(path: "Project/.DS_Store").path))
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellingLeavesNothingBehind() async throws {
        let tree = try SourceTree()
        defer { tree.cleanUp() }
        var bytes = [UInt8](repeating: 0, count: 64 << 20)
        for index in stride(from: 0, to: bytes.count, by: 8) { bytes[index] = UInt8.random(in: 0...255) }
        try Data(bytes).write(to: tree.project.appending(path: "noise.bin"))
        let out = tree.folder.url.appending(path: "Out", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: false)
        let report = Compatibility.report(for: PackRequest.collect([tree.project]).files, options: PackOptions())
        let request = CreateRequest(operationID: UUID().uuidString, archiveName: "Project", format: .sevenZip, level: .smallest)

        let started = Mutex(false)
        let task = Task {
            try await ArchiveCreation.run(report.items, totalBytes: report.totalBytes, attributes: false,
                                          request: request, named: "Project", in: out) { fraction in
                if fraction > 0.25 { started.withLock { $0 = true } } // past handing over, compressing
            }
        }
        let deadline = ContinuousClock.now + .seconds(30)
        while !started.withLock({ $0 }), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        try #require(started.withLock { $0 }, "compression never started")
        task.cancel()

        await #expect(throws: EngineError(.cancelled)) { try await task.value }
        #expect(TemporaryFolder.contents(of: out).isEmpty)
    }

    @Test func existingNamesAreKeptOrReplaced() async throws {
        let tree = try SourceTree()
        defer { tree.cleanUp() }
        let out = tree.folder.url.appending(path: "Out", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: false)
        try Data("old".utf8).write(to: out.appending(path: "Project.tar.gz"))

        #expect(ArchiveCreation.existing(named: "Project", format: .tarGz, in: out).count == 1)
        let (both, _) = try await pack(tree, audience: .linux, format: .tarGz, into: out)
        #expect(both.placed.map(\.lastPathComponent) == ["Project 2.tar.gz"])

        let (replaced, _) = try await pack(tree, audience: .linux, format: .tarGz, conflict: .replace, into: out)
        #expect(replaced.placed.map(\.lastPathComponent) == ["Project.tar.gz"])
        #expect(try Data(contentsOf: replaced.placed[0]) != Data("old".utf8))
        #expect(TemporaryFolder.contents(of: out) == ["Project 2.tar.gz", "Project.tar.gz"])
    }
}

@Suite("Pack plan")
struct PackPlanTests {
    private let request = CreateRequest(operationID: "x", archiveName: "P", format: .zip)
    private let input = URL(filePath: "/in")
    private let work = URL(filePath: "/work")

    @Test func zipWithPasswordUsesAESAndUTF8Names() {
        var request = request
        request.password = "pw"
        request.level = .smallest
        request.volumeSize = 100_000_000
        request.threads = 2
        let steps = SevenZip.createSteps(for: request, archive: URL(filePath: "/out/P.zip"), input: input, work: work)
        #expect(steps.count == 1)
        let arguments = steps[0].arguments
        for flag in ["-tzip", "-mx9", "-snl", "-mcu=on", "-mem=AES256", "-p", "-v100000000b", "-mmt=2"] {
            #expect(arguments.contains(flag), "\(flag)")
        }
        #expect(arguments.suffix(3) == ["--", "/out/P.zip", "*"])
        #expect(steps[0].usesPassword && steps[0].directory == input)
    }

    @Test func sevenZipEncryptsNames() {
        var request = request
        request.format = .sevenZip
        request.password = "pw"
        let arguments = SevenZip.createSteps(for: request, archive: URL(filePath: "/out/P.7z"), input: input, work: work)[0].arguments
        #expect(arguments.contains("-mhe=on") && arguments.contains("-t7z") && !arguments.contains("-mem=AES256"))
    }

    @Test func compressedTarIsTwoSteps() {
        var request = request
        request.format = .tarBz2
        request.volumeSize = 1000
        let steps = SevenZip.createSteps(for: request, archive: URL(filePath: "/out/P.tar.bz2"), input: input, work: work)
        #expect(steps.map { $0.arguments[1] } == ["-ttar", "-tbzip2"])
        #expect(steps[0].intermediate == URL(filePath: "/work/P.tar"))
        #expect(!steps[0].arguments.contains("-v1000b") && steps[1].arguments.contains("-v1000b"))
        #expect(steps[1].arguments.last == "/work/P.tar")
    }

    @Test func namesThatWouldClashAreNumbered() {
        let files = [PackFile(path: "A", size: 0, isFolder: true),
                     PackFile(path: "A/x:y.txt", size: 1), PackFile(path: "A/x-y.txt", size: 1),
                     PackFile(path: "A/Readme", size: 1), PackFile(path: "A/README", size: 1)]
        let report = Compatibility.report(for: files, options: PackOptions())
        #expect(Set(report.included.map(\.path)) == ["A", "A/x-y.txt", "A/x-y 2.txt", "A/README", "A/Readme 2"])
        var linux = PackOptions()
        linux.setAudience(.linux)
        // Linux tells README from Readme; only the composed form changes.
        #expect(Set(Compatibility.report(for: files, options: linux).included.map(\.path))
            == ["A", "A/x:y.txt", "A/x-y.txt", "A/Readme", "A/README"])
    }

    @Test func editedNamesAreMadeSafeToo() {
        let files = [PackFile(path: "a:b.txt", size: 1)]
        let report = Compatibility.report(for: files, options: PackOptions(), overrides: ["a:b.txt": "my*name.txt"])
        #expect(report.included.map(\.path) == ["my-name.txt"])
        #expect(report.renames.first?.suggested == "a-b.txt")
    }

    @Test func linuxComposesNamesAndKeepsLinks() {
        var options = PackOptions()
        options.setAudience(.linux)
        let files = [PackFile(path: "Cafe\u{301}.txt", size: 1), PackFile(path: "link", size: 0, isLink: true)]
        let report = Compatibility.report(for: files, options: options)
        #expect(report.included.map(\.path).contains("Café.txt"))
        #expect(report.included.map(\.path).contains("link"))
        #expect(report.renames.isEmpty) // composing alone isn't a rename people would notice
    }

    @Test func zipPasswordsOutsideASCIIAreFlagged() {
        var options = PackOptions()
        options.usesPassword = true
        let titles = { (password: String) in
            Compatibility.report(for: [], options: options, password: password).notes.map(\.title)
        }
        #expect(titles("密码").contains("Use plain letters and numbers for a ZIP password"))
        #expect(!titles("plain-ascii").contains("Use plain letters and numbers for a ZIP password"))
        options.setFormat(.sevenZip)
        #expect(!Compatibility.report(for: [], options: options, password: "密码").notes.map(\.title)
            .contains("Use plain letters and numbers for a ZIP password"))
    }

    @Test func requestNamesFollowWhatWasChosen() throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let a = folder.url.appending(path: "a", directoryHint: .isDirectory)
        let b = folder.url.appending(path: "b", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: b, withIntermediateDirectories: false)
        try Data("1".utf8).write(to: a.appending(path: "Report.pdf"))
        try Data("2".utf8).write(to: b.appending(path: "Report.pdf"))

        let one = PackRequest.collect([a.appending(path: "Report.pdf")])
        #expect(one.suggestedName == "Report")
        let two = PackRequest.collect([a.appending(path: "Report.pdf"), b.appending(path: "Report.pdf")])
        #expect(two.roots == ["Report.pdf", "Report 2.pdf"])
        #expect(two.suggestedName == "Archive")
        let folderRequest = PackRequest.collect([a])
        #expect(folderRequest.suggestedName == "a")
        #expect(folderRequest.files.map(\.path) == ["a", "a/Report.pdf"])
    }
}
