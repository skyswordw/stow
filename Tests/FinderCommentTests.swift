import Foundation
import Testing
@testable import Stow

/// Finder comments (and tags) come back after Stow's own extraction, whichever format carried them.
/// Each archive is made the way a Mac makes it: Finder's Compress (`ditto`) for ZIP, the system
/// `tar` (which writes `._name` entries beside each file) for TARs, and `__MACOSX` companions for 7Z.
@Suite("Finder comments on every format", .enabled(if: SevenZip.bundled() != nil, "7zz isn't bundled — run scripts/fetch-7zip.sh"))
@MainActor
struct FinderCommentTests {
    static let commentName = "com.apple.metadata:kMDItemFinderComment"
    static let tagName = "com.apple.metadata:_kMDItemUserTags"

    enum Source: String, CaseIterable, CustomTestStringConvertible, Sendable {
        case zip, sevenZip, tar, tarGz, tarBz2, tarXz, tarZst
        var testDescription: String { rawValue }
        var fileName: String {
            switch self {
            case .zip: "Docs.zip"
            case .sevenZip: "Docs.7z"
            case .tar: "Docs.tar"
            case .tarGz: "Docs.tar.gz"
            case .tarBz2: "Docs.tar.bz2"
            case .tarXz: "Docs.tar.xz"
            case .tarZst: "Docs.tar.zst"
            }
        }
    }

    /// Finder keeps a comment as a binary property list holding the string.
    static func comment(_ text: String) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: text, format: .binary, options: 0)
    }

    private func set(_ name: String, _ value: Data, on url: URL) throws {
        let status = value.withUnsafeBytes { setxattr(url.path, name, $0.baseAddress, value.count, 0, 0) }
        try #require(status == 0, "setxattr \(name)")
    }

    private func attribute(_ name: String, of url: URL) -> Data? {
        let length = getxattr(url.path, name, nil, 0, 0, 0)
        guard length > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: length)
        return getxattr(url.path, name, &buffer, length, 0, 0) == length ? Data(buffer) : nil
    }

    private func run(_ tool: URL, _ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = tool
        process.arguments = arguments
        process.currentDirectoryURL = directory
        // The system tar only writes `._` entries when this isn't set.
        process.environment = ProcessInfo.processInfo.environment.filter { $0.key != "COPYFILE_DISABLE" }
        try process.run()
        process.waitUntilExit()
        try #require(process.terminationStatus == 0, "\(tool.lastPathComponent) \(arguments.joined(separator: " "))")
    }

    /// `Source/Docs/{a.txt (comment + tag), b.txt, Inner/ (comment) {c.txt}}`. The commented folder
    /// is a nested one: Finder's Compress (like `ditto --keepParent`) never stores the details of
    /// the folder it was asked to compress, only of what's inside.
    private func makeArchive(_ source: Source, in folder: TemporaryFolder) throws -> URL {
        let parent = folder.url.appending(path: "Source", directoryHint: .isDirectory)
        let docs = parent.appending(path: "Docs", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        let file = docs.appending(path: "a.txt")
        try Data("commented".utf8).write(to: file)
        try Data("plain".utf8).write(to: docs.appending(path: "b.txt"))
        try set(Self.commentName, try Self.comment("From the Mac — 来自 Mac"), on: file)
        try set(Self.tagName, try PropertyListSerialization.data(fromPropertyList: ["Orange\n7"], format: .binary, options: 0), on: file)
        let inner = docs.appending(path: "Inner", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: false)
        try Data("inner".utf8).write(to: inner.appending(path: "c.txt"))
        try set(Self.commentName, try Self.comment("The folder"), on: inner)

        let archive = folder.url.appending(path: source.fileName)
        let tar = URL(filePath: "/usr/bin/tar")
        switch source {
        case .zip:
            try run(URL(filePath: "/usr/bin/ditto"), ["-c", "-k", "--sequesterRsrc", "--keepParent", docs.path, archive.path], in: parent)
        case .tar: try run(tar, ["-cf", archive.path, "Docs"], in: parent)
        case .tarGz: try run(tar, ["-czf", archive.path, "Docs"], in: parent)
        case .tarBz2: try run(tar, ["-cjf", archive.path, "Docs"], in: parent)
        case .tarXz: try run(tar, ["-cJf", archive.path, "Docs"], in: parent)
        case .tarZst:
            let plain = folder.url.appending(path: "Docs.tar")
            try run(tar, ["-cf", plain.path, "Docs"], in: parent)
            try Zstd.compressNow(plain, into: archive, level: 3, volumeSize: nil)
            try FileManager.default.removeItem(at: plain)
        case .sevenZip:
            // Packed on a Mac by a tool that sequesters, as Stow's ZIP packing does. Named
            // explicitly: sandboxed directory listings can hide `._` names.
            try MacMetadata.sequester(in: parent)
            let sevenZip = try #require(SevenZip.bundled())
            try run(sevenZip.executable, ["a", "-t7z", "-bso0", "-bsp0", archive.path,
                                          "Docs", "__MACOSX/Docs/._a.txt", "__MACOSX/Docs/._Inner"], in: parent)
        }
        return archive
    }

    private func open(_ url: URL) async throws -> Archive {
        let archive = Archive(listing: try await ArchiveEngine.shared.list(url), url: url)
        try #require(!archive.appleDoublePaths.isEmpty, "no AppleDouble companions listed in \(url.lastPathComponent)")
        return archive
    }

    @Test(arguments: Source.allCases)
    func extractAllBringsCommentsBack(source: Source) async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let archive = try await open(try makeArchive(source, in: folder))
        let fileComment = try Self.comment("From the Mac — 来自 Mac"), folderComment = try Self.comment("The folder")
        #expect(archive.files.map(\.name).sorted() == ["a.txt", "b.txt", "c.txt"])
        let out = folder.url.appending(path: "Out", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        let result = try await Extraction.run(archive, selection: nil, to: out) { _ in }

        let docs = out.appending(path: "Docs", directoryHint: .isDirectory)
        #expect(attribute(Self.commentName, of: docs.appending(path: "a.txt")) == fileComment)
        #expect(attribute(Self.tagName, of: docs.appending(path: "a.txt")) != nil)
        #expect(attribute(Self.commentName, of: docs.appending(path: "Inner")) == folderComment)
        #expect(attribute(Self.commentName, of: docs.appending(path: "b.txt")) == nil)
        #expect(result.restoredMetadata.files == 2)
        #expect(TemporaryFolder.contents(of: out) == ["Docs", "Docs/Inner", "Docs/Inner/c.txt", "Docs/a.txt", "Docs/b.txt"])
    }

    @Test(arguments: Source.allCases)
    func extractingTheFolderBringsItsFilesCommentsBack(source: Source) async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let archive = try await open(try makeArchive(source, in: folder))
        let fileComment = try Self.comment("From the Mac — 来自 Mac"), folderComment = try Self.comment("The folder")
        let docs = try #require(archive.entry(at: "Docs"))
        let out = folder.url.appending(path: "Out", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        let result = try await Extraction.run(archive, selection: [docs], to: out) { _ in }

        let placed = try #require(result.placed.first)
        #expect(placed.lastPathComponent == "Docs")
        #expect(attribute(Self.commentName, of: placed.appending(path: "a.txt")) == fileComment)
        #expect(attribute(Self.commentName, of: placed.appending(path: "Inner")) == folderComment)
        #expect(!TemporaryFolder.contents(of: out).contains { $0.contains("._") || $0.contains("__MACOSX") })
    }

    @Test func oneFileFromATarballBringsItsComment() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let archive = try await open(try makeArchive(.tarGz, in: folder))
        let fileComment = try Self.comment("From the Mac — 来自 Mac")
        let entry = try #require(archive.entry(at: "Docs/a.txt"))

        let result = try await Extraction.run(archive, selection: [entry], to: folder.url) { _ in }

        #expect(result.placed.map(\.lastPathComponent) == ["a.txt"])
        #expect(attribute(Self.commentName, of: result.placed[0]) == fileComment)
    }

    @Test func selectedFoldersBringNestedCompanions() {
        let available: Set<String> = ["__MACOSX/._Docs", "__MACOSX/Docs/._a.txt", "__MACOSX/Docs/Deep/._c.txt",
                                      "__MACOSX/Docsy/._x.txt", "Docs/._b.txt"]
        #expect(Extraction.appleDoubles(for: ["Docs/"], in: available)
                == ["__MACOSX/._Docs", "__MACOSX/Docs/._a.txt", "__MACOSX/Docs/Deep/._c.txt"])
        // A file and its folder both selected: each companion once.
        #expect(Extraction.appleDoubles(for: ["Docs", "Docs/a.txt"], in: available)
                == ["__MACOSX/._Docs", "__MACOSX/Docs/._a.txt", "__MACOSX/Docs/Deep/._c.txt"])
    }
}
