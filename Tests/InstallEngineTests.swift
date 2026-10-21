import Foundation
import Synchronization
import Testing
@testable import Stow

/// Installs and conflict-aware extraction end to end, through the sandboxed engine.
@Suite("Installing", .enabled(if: SevenZip.bundled() != nil, "7zz isn't bundled — run scripts/fetch-7zip.sh"))
@MainActor
struct InstallEngineTests {
    let sevenZip = SevenZip.bundled()!

    /// A minimal app bundle with a real Mach-O, signed ad hoc.
    func makeApp(named name: String, version: String, in folder: URL) throws -> URL {
        let app = folder.appending(path: "\(name).app", directoryHint: .isDirectory)
        let macOS = app.appending(path: "Contents/MacOS", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(filePath: "/usr/bin/true"), to: macOS.appending(path: name))
        let info: [String: Any] = ["CFBundleExecutable": name, "CFBundleIdentifier": "app.stow.tests.\(name)",
                                   "CFBundlePackageType": "APPL", "CFBundleShortVersionString": version]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: app.appending(path: "Contents/Info.plist"))
        try run("/usr/bin/codesign", ["--force", "--sign", "-", app.path])
        return app
    }

    func zip(_ items: [URL], to archive: URL) throws {
        try run(sevenZip.executable.path, ["a", "-tzip", "-bso0", "-bsp0", archive.path] + items.map(\.path))
    }

    func run(_ tool: String, _ arguments: [String]) throws {
        let process = try Process.run(URL(filePath: tool), arguments: arguments)
        process.waitUntilExit()
        try #require(process.terminationStatus == 0, "\(tool) \(arguments.joined(separator: " "))")
    }

    @Test func installsAnAppFromAZipThenReplacesIt() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let build = folder.url.appending(path: "Build", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
        let applications = folder.url.appending(path: "Applications", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)

        let first = folder.url.appending(path: "Tool-1.zip")
        try zip([try makeApp(named: "Tool", version: "1.0", in: build)], to: first)
        let archive1 = Archive(listing: try await ArchiveEngine.shared.list(first), url: first)
        let entry1 = try #require(archive1.entry(at: "Tool.app"))
        #expect(NextStep.suggestions(for: [entry1]).first == .moveToApplications)

        let questions = Questions()
        let installed = try await Installer.installApp(entry1, from: archive1, into: applications, removeQuarantine: false,
                                                       ask: questions.answer(.proceed), onProgress: { _ in })
        #expect(installed.verdict == .adHoc)
        #expect(!installed.replaced)
        #expect(questions.asked == ["signature adHoc"])
        // The seal survived engine → pipe → staging → rename.
        #expect(CodeSignature.assess(applications.appending(path: "Tool.app")) == .adHoc)
        #expect(Installer.version(of: applications.appending(path: "Tool.app")) == "1.0")

        try FileManager.default.removeItem(at: build.appending(path: "Tool.app"))
        let second = folder.url.appending(path: "Tool-2.zip")
        try zip([try makeApp(named: "Tool", version: "2.0", in: build)], to: second)
        let archive2 = Archive(listing: try await ArchiveEngine.shared.list(second), url: second)
        let replaced = try await Installer.installApp(try #require(archive2.entry(at: "Tool.app")), from: archive2,
                                                      into: applications, removeQuarantine: false,
                                                      ask: questions.answer(.proceed), onProgress: { _ in })
        #expect(replaced.replaced)
        #expect(questions.asked.last == "replace 1.0 → 2.0")
        #expect(Installer.version(of: applications.appending(path: "Tool.app")) == "2.0")
        #expect(TemporaryFolder.contents(of: applications).filter { !$0.contains("/") } == ["Tool.app"])

        // Declining the signature warning installs nothing.
        await #expect(throws: EngineError(.cancelled)) {
            _ = try await Installer.installApp(try #require(archive1.entry(at: "Tool.app")), from: archive1,
                                               into: applications, removeQuarantine: false,
                                               ask: questions.answer(.cancel), onProgress: { _ in })
        }
        #expect(Installer.version(of: applications.appending(path: "Tool.app")) == "2.0")
    }

    @Test func installsFontsAndSkipsOnesAlreadyThere() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let source = try #require(["/System/Library/Fonts/Supplemental/Arial.ttf", "/System/Library/Fonts/Supplemental/Georgia.ttf"]
            .map { URL(filePath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }.first)
        let work = folder.url.appending(path: "Work", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let font = work.appending(path: "Sample.ttf")
        try FileManager.default.copyItem(at: source, to: font)
        let web = work.appending(path: "Sample.woff2")
        try Data("wOF2".utf8).write(to: web)
        let archive = folder.url.appending(path: "Fonts.zip")
        try zip([font, web], to: archive)
        let fonts = folder.url.appending(path: "Fonts", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: fonts, withIntermediateDirectories: true)

        let opened = Archive(listing: try await ArchiveEngine.shared.list(archive), url: archive)
        let questions = Questions()
        let first = try await Installer.installFonts(opened.files, from: opened, into: fonts,
                                                     ask: questions.answer(.proceed), onProgress: { _ in })
        #expect(first.installed.map(\.lastPathComponent) == ["Sample.ttf"])
        #expect(first.unusable == ["Sample.woff2"])
        #expect(questions.asked.isEmpty)

        let second = try await Installer.installFonts(opened.files, from: opened, into: fonts,
                                                      ask: questions.answer(.alternate), onProgress: { _ in })
        #expect(questions.asked == ["fonts Sample.ttf"])
        #expect(second.installed.isEmpty && second.skipped == ["Sample.ttf"])
        #expect(TemporaryFolder.contents(of: fonts) == ["Sample.ttf"])
    }

    @Test func extractAllIntoANamedFolderWithEachConflictChoice() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let zip = folder.url.appending(path: "Handoff.zip")
        try ZipFixture(entries: [.file("README.md", "new readme"), .file("Docs/a.txt", "new a"),
                                 .file("Docs/.gitignore", "*.log"), .file("Docs/Thumbs.db", "x"),
                                 .file("__MACOSX/Docs/._a.txt", "x")]).write(to: zip)
        let out = folder.url.appending(path: "Out", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: out.appending(path: "Handoff/Docs"), withIntermediateDirectories: true)
        try Data("old readme".utf8).write(to: out.appending(path: "Handoff/README.md"))
        try Data("mine".utf8).write(to: out.appending(path: "Handoff/Mine.txt"))
        let archive = Archive(listing: try await ArchiveEngine.shared.list(zip), url: zip)

        func extract(_ resolve: @escaping Placement.Resolver, skipSystemFiles: Bool = true) async throws -> Extraction.Result {
            try await Extraction.run(archive, selection: nil, to: out,
                                     options: .init(allFolder: .always, skipSystemFiles: skipSystemFiles, resolve: resolve)) { _ in }
        }
        func read(_ path: String) -> String? {
            (try? Data(contentsOf: out.appending(path: path))).map { String(decoding: $0, as: UTF8.self) }
        }

        // Merge + Keep Both: the old README stays, the new one is numbered.
        let kept = try await extract { $0.canMerge ? .merge : .keepBoth }
        #expect(kept.placed.map(\.lastPathComponent) == ["Handoff"])
        #expect(read("Handoff/README.md") == "old readme" && read("Handoff/README 2.md") == "new readme")
        #expect(read("Handoff/Mine.txt") == "mine")
        #expect(read("Handoff/Docs/.gitignore") == "*.log")
        #expect(read("Handoff/Docs/Thumbs.db") == nil)

        // Merge + Skip: nothing changes for files already there.
        let skipped = try await extract { $0.canMerge ? .merge : .skip }
        #expect(skipped.placement.skipped == 3) // README.md, Docs/a.txt, Docs/.gitignore
        #expect(read("Handoff/README.md") == "old readme")

        // Merge + Replace.
        try Data("edited".utf8).write(to: out.appending(path: "Handoff/Docs/a.txt"))
        let replaced = try await extract { $0.canMerge ? .merge : .replace }
        #expect(replaced.placement.replaced == 3)
        #expect(read("Handoff/README.md") == "new readme" && read("Handoff/Docs/a.txt") == "new a")

        // Keep Both for the folder: a second, numbered folder.
        let both = try await extract { _ in .keepBoth }
        #expect(both.placed.map(\.lastPathComponent) == ["Handoff 2"])

        // System files can be kept when asked.
        let raw = try await extract({ _ in .keepBoth }, skipSystemFiles: false)
        #expect(read("\(raw.placed[0].lastPathComponent)/Docs/Thumbs.db") == "x")
    }

    @Test func extractAllAlwaysWrapsASingleFile() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let zip = folder.url.appending(path: "Notes.zip")
        try ZipFixture(entries: [.file("notes.txt", "hi")]).write(to: zip)
        let archive = Archive(listing: try await ArchiveEngine.shared.list(zip), url: zip)

        let automatic = try await Extraction.run(archive, selection: nil, to: folder.url) { _ in }
        #expect(automatic.placed.map(\.lastPathComponent) == ["notes.txt"])
        let always = try await Extraction.run(archive, selection: nil, to: folder.url,
                                              options: .init(allFolder: .always)) { _ in }
        #expect(always.placed.map(\.lastPathComponent) == ["Notes"])
        #expect(TemporaryFolder.contents(of: always.placed[0]) == ["notes.txt"])
    }

    static func fixture(_ name: String) throws -> URL {
        let folder = try #require(Bundle(for: FixtureLocator.self).url(forResource: "Fixtures", withExtension: nil))
        return folder.appending(path: name)
    }

    @Test(arguments: ["Fixture-HFS.dmg", "Fixture-APFS.dmg"])
    func diskImageAppKeepsItsSealAndLeavesTheLayoutBehind(fixture: String) async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let image = folder.url.appending(path: fixture)
        try FileManager.default.copyItem(at: try Self.fixture(fixture), to: image)

        let archive = Archive(listing: try await ArchiveEngine.shared.list(image), url: image)
        #expect(archive.format == .dmg)
        #expect(archive.dropTargets.map(\.folder) == ["/Applications"])
        #expect(archive.children(of: archive.volumeRoot).map(\.name) == ["Fixture Tool.app"], "\(archive.children(of: archive.volumeRoot).map(\.name.debugDescription))")
        #expect(archive.checkup.contains { $0.title == "Installer layout hidden" })
        let model = BrowserModel(archive: archive)
        #expect(model.folder == archive.volumeRoot)
        #expect(model.selectedEntries.map(\.name) == ["Fixture Tool.app"])
        let app = try #require(model.selectedEntries.first)
        #expect(NextStep.suggestions(for: model.selectedEntries, dropTargets: archive.dropTargets).first == .moveToApplications)

        let applications = folder.url.appending(path: "Applications", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
        let outcome = try await Installer.installApp(app, from: archive, into: applications,
                                                     removeQuarantine: false, ask: { _ in .proceed }, onProgress: { _ in })
        #expect(outcome.verdict == .adHoc)
        #expect(CodeSignature.assess(outcome.app) == .adHoc)
        #expect(TemporaryFolder.contents(of: outcome.app).allSatisfy { !$0.contains(":com.apple") })

        let out = folder.url.appending(path: "Out", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let all = try await Extraction.run(archive, selection: nil, to: out) { _ in }
        #expect(all.report.removedLinks.isEmpty)
        let names = TemporaryFolder.contents(of: out).filter { !$0.contains(".app/") }
        #expect(!names.contains { $0.contains(".background") || $0.hasSuffix("Applications") || $0.contains("VolumeIcon") })
        #expect(names.contains { $0.hasSuffix("Fixture Tool.app") })
    }

    @Test func damagedDiskImagesAreCaught() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let good = folder.url.appending(path: "Good.dmg")
        try FileManager.default.copyItem(at: try Self.fixture("Fixture-HFS.dmg"), to: good)
        try await ArchiveEngine.shared.verify(good)

        // Flip bytes inside the compressed data, past the header and before the trailing plist.
        var bytes = try Data(contentsOf: good)
        for index in stride(from: 2_000, to: 6_000, by: 7) { bytes[index] ^= 0x5A }
        let bad = folder.url.appending(path: "Bad.dmg")
        try bytes.write(to: bad)
        await #expect(throws: EngineError.self) { try await ArchiveEngine.shared.verify(bad) }
        #expect(Checkup.diskImageFinding(damaged: "CRC").severity == .caution)
    }

    @Test func encryptedDiskImagesAreExplained() throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let image = folder.url.appending(path: "Locked.dmg")
        try (Data("encrcdsa".utf8) + Data(count: 64)).write(to: image)
        #expect(DiskImageCheck.isEncrypted(image))
        #expect(DiskImageCheck.explain(EngineError(.notAnArchive), for: image).message.contains("encrypted"))
        let plain = folder.url.appending(path: "Plain.dmg")
        try Data(count: 64).write(to: plain)
        #expect(!DiskImageCheck.isEncrypted(plain))
    }
}

private final class FixtureLocator {}

/// Records what an install asked and answers with a fixed choice.
private final class Questions {
    var asked: [String] = []

    func answer(_ answer: Installer.Answer) -> Installer.Ask {
        { [self] question in
            switch question {
            case .signature(_, let verdict): asked.append("signature \(verdict)")
            case .replaceApp(_, let old, let new): asked.append("replace \(old ?? "?") → \(new ?? "?")")
            case .replaceFonts(let names): asked.append("fonts \(names.joined(separator: ","))")
            }
            return answer
        }
    }
}

/// Finder tags and other details a Mac packs as AppleDouble come back on extract.
@Suite("Mac details", .enabled(if: SevenZip.bundled() != nil, "7zz isn't bundled — run scripts/fetch-7zip.sh"))
@MainActor
struct AppleDoubleTests {
    static let tagName = "com.apple.metadata:_kMDItemUserTags"
    static let commentName = "com.apple.metadata:kMDItemComment"

    /// A ZIP made the way Finder's Compress makes it: `ditto -c -k --sequesterRsrc`.
    func makeMacZip(in folder: TemporaryFolder) throws -> URL {
        let source = folder.url.appending(path: "Source/Docs", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let file = source.appending(path: "a.txt")
        try Data("tagged".utf8).write(to: file)
        try Data("plain".utf8).write(to: source.appending(path: "b.txt"))
        let tags = try PropertyListSerialization.data(fromPropertyList: ["Orange\n7"], format: .binary, options: 0)
        try set(Self.tagName, tags, on: file)
        try set(Self.commentName, Data("From the Mac".utf8), on: file)
        let zip = folder.url.appending(path: "Docs.zip")
        let ditto = try Process.run(URL(filePath: "/usr/bin/ditto"),
                                    arguments: ["-c", "-k", "--sequesterRsrc", "--keepParent", source.path, zip.path])
        ditto.waitUntilExit()
        try #require(ditto.terminationStatus == 0)
        return zip
    }

    func set(_ name: String, _ value: Data, on url: URL) throws {
        let status = value.withUnsafeBytes { setxattr(url.path, name, $0.baseAddress, value.count, 0, 0) }
        try #require(status == 0, "setxattr \(name)")
    }

    func attribute(_ name: String, of url: URL) -> Data? {
        let length = getxattr(url.path, name, nil, 0, 0, 0)
        guard length > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: length)
        return getxattr(url.path, name, &buffer, length, 0, 0) == length ? Data(buffer) : nil
    }

    @Test func extractAllPutsFinderDetailsBack() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let zip = try makeMacZip(in: folder)
        let archive = Archive(listing: try await ArchiveEngine.shared.list(zip), url: zip)
        #expect(!archive.appleDoublePaths.isEmpty)
        #expect(archive.files.map(\.name).sorted() == ["a.txt", "b.txt"])
        let out = folder.url.appending(path: "Out", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        let result = try await Extraction.run(archive, selection: nil, to: out) { _ in }

        let file = out.appending(path: "Docs/a.txt")
        #expect(attribute(Self.tagName, of: file) != nil)
        #expect(attribute(Self.commentName, of: file) == Data("From the Mac".utf8))
        #expect(result.restoredMetadata.files == 1)
        #expect(result.findings.contains { $0.title == "Mac details restored" })
        #expect(TemporaryFolder.contents(of: out) == ["Docs", "Docs/a.txt", "Docs/b.txt"])
    }

    @Test func selectedFilesBringTheirDetailsToo() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let zip = try makeMacZip(in: folder)
        let archive = Archive(listing: try await ArchiveEngine.shared.list(zip), url: zip)
        let entry = try #require(archive.entry(at: "Docs/a.txt"))

        let result = try await Extraction.run(archive, selection: [entry], to: folder.url) { _ in }

        #expect(result.placed.map(\.lastPathComponent) == ["a.txt"])
        #expect(attribute(Self.commentName, of: result.placed[0]) == Data("From the Mac".utf8))
    }

    @Test func keepingSystemFilesStillRestoresDetails() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let zip = try makeMacZip(in: folder)
        let archive = Archive(listing: try await ArchiveEngine.shared.list(zip), url: zip)
        let out = folder.url.appending(path: "Out", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        _ = try await Extraction.run(archive, selection: nil, to: out, options: .init(skipSystemFiles: false)) { _ in }

        // The empty __MACOSX folder stays too, so both land in a folder named after the archive.
        let file = try #require(TemporaryFolder.contents(of: out).first { $0.hasSuffix("Docs/a.txt") })
        #expect(attribute(Self.commentName, of: out.appending(path: file)) == Data("From the Mac".utf8))
        #expect(!TemporaryFolder.contents(of: out).contains { $0.hasSuffix("._a.txt") })
    }

    @Test func quarantineAndProvenanceAreNeverRestored() {
        #expect(AppleDouble.skipped.contains("com.apple.quarantine"))
        #expect(AppleDouble.skipped.contains("com.apple.provenance"))
        #expect(AppleDouble.attributes(in: Data("not apple double".utf8)) == nil)
        #expect(Extraction.appleDoubles(for: ["Docs/a.txt", "top.txt"],
                                         in: ["__MACOSX/Docs/._a.txt", "._top.txt", "__MACOSX/._other"])
                == ["__MACOSX/Docs/._a.txt", "._top.txt"])
    }
}
