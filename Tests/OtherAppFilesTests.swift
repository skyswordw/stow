import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Stow

/// Files from other apps' private storage (WeChat, Mail…): who keeps them, whether Stow may read
/// them, what it says when it may not, and receiving files an app only promises during a drag.
/// A real drag out of WeChat is a manual test (#38).
@Suite("Files from other apps")
@MainActor
struct OtherAppFilesTests {
    @Test func ownerComesFromTheStoragePath() {
        let home = "/Users/me/Library"
        let cases: [(String, String?, String?)] = [
            ("\(home)/Containers/com.tencent.xinWeChat/Data/Library/Application Support/com.tencent.xinWeChat/2.0b4.0.9/x/Message/File/a.zip",
             "com.tencent.xinWeChat", "WeChat"),
            ("\(home)/Group Containers/5A4RE8SF68.com.tencent.xinWeChat/a.zip", "com.tencent.xinWeChat", "WeChat"),
            ("\(home)/Group Containers/group.com.apple.mail/a.zip", "com.apple.mail", "Mail"),
            ("\(home)/Containers/com.apple.mail/Data/Library/Mail Downloads/1/a.zip", "com.apple.mail", "Mail"),
            ("\(home)/Containers/app.stow.Stow/Data/tmp/a.zip", nil, nil),
            ("/Users/me/Downloads/a.zip", nil, nil),
            ("/Users/me/Library/Containers", nil, nil),
        ]
        for (path, bundleID, name) in cases {
            let owner = OtherAppFiles.owner(of: URL(filePath: path))
            #expect(owner?.bundleID == bundleID, "\(path)")
            #expect(owner?.name == name, "\(path)")
        }
        #expect(OtherAppFiles.isTeamID("5A4RE8SF68") && !OtherAppFiles.isTeamID("group") && !OtherAppFiles.isTeamID("abcdefghij"))
    }

    @Test func unknownAppsAreNamedFromTheirIdentifier() {
        #expect(OtherAppFiles.name(for: "com.example.NoSuchAppAnywhere") == "NoSuchAppAnywhere")
        #expect(OtherAppFiles.name(for: "com.tencent.xinWeChat") == "WeChat")
    }

    @Test func unreadableFilesAreRecognised() throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let file = folder.url.appending(path: "a.zip")
        try Data("PK".utf8).write(to: file)
        #expect(OtherAppFiles.canRead(file))
        #expect(OtherAppFiles.canRead(folder.url))
        // A missing file isn't a permission problem: opening it fails the usual way.
        #expect(OtherAppFiles.canRead(folder.url.appending(path: "missing.zip")))
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path) }
        #expect(!OtherAppFiles.canRead(file))
    }

    @Test func theFailureSaysWhereToGetACopy() {
        let wechat = URL(filePath: "/Users/me/Library/Containers/com.tencent.xinWeChat/Data/File/Harbor Handoff.zip")
        let failure = OtherAppFiles.unreadable(wechat)
        #expect(failure.title == "Stow isn’t allowed to read “Harbor Handoff.zip”")
        #expect(failure.advice.contains("WeChat’s own storage") && failure.advice.contains("In WeChat, save it to Downloads"))
        #expect(failure.code.description == "OPN-101")
        #expect(failure.action == .showInFinder)
        #expect(failure.diagnostic.contains("Harbor Handoff.zip"))

        let elsewhere = OtherAppFiles.unreadable(URL(filePath: "/Volumes/Share/a.zip"))
        #expect(elsewhere.advice.contains("from Finder") && !elsewhere.advice.contains("storage"))
    }

    @Test func receivedFilesKeepTheirNames() throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let source = folder.url.appending(path: "promise-1234.zip")
        try Data("PK-data".utf8).write(to: source)
        let parent = folder.url.appending(path: "Received", directoryHint: .isDirectory)

        let first = try OtherAppFiles.keep(source, named: "Harbor Handoff.zip", in: parent)
        let second = try OtherAppFiles.keep(source, named: "Harbor Handoff.zip", in: parent)
        #expect(first.lastPathComponent == "Harbor Handoff.zip" && second.lastPathComponent == "Harbor Handoff.zip")
        #expect(first != second && first.path.hasPrefix(parent.path))
        #expect(try Data(contentsOf: first) == Data("PK-data".utf8))
        // A suggested name without an extension gets the file's; slashes can't make folders.
        #expect(try OtherAppFiles.keep(source, named: "Report/Final", in: parent).lastPathComponent == "Report-Final.zip")
        #expect(try OtherAppFiles.keep(source, named: nil, in: parent).lastPathComponent == "promise-1234.zip")
    }

    @Test func promisedArchivesAreReceivedOthersIgnored() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let zip = folder.url.appending(path: "From Mail.zip")
        try ZipFixture(entries: [.file("a.txt", "a")]).write(to: zip)
        let archive = try #require(NSItemProvider(contentsOf: zip))
        archive.suggestedName = "From Mail.zip"
        let text = NSItemProvider(object: "just words" as NSString)
        let parent = folder.url.appending(path: "Received", directoryHint: .isDirectory)

        let received = await OtherAppFiles.receive([archive, text], into: parent)

        #expect(received.map(\.lastPathComponent) == ["From Mail.zip"])
        #expect(try Data(contentsOf: received[0]) == Data(contentsOf: zip))
        #expect(received[0].path.hasPrefix(parent.path))
    }

    @Test func receivedCopiesNeverSuggestTheirFolder() {
        let received = OtherAppFiles.receivedFolder.appending(path: "1234/From Mail.zip")
        #expect(OtherAppFiles.isReceived(received))
        #expect(OtherAppFiles.startFolder(near: received) == nil)
        let downloads = URL(filePath: "/Users/me/Downloads/a.zip")
        #expect(!OtherAppFiles.isReceived(downloads))
        #expect(OtherAppFiles.startFolder(near: downloads)?.path == "/Users/me/Downloads")
    }
}
