import Foundation
import Synchronization
import Testing
@testable import Stow

/// Holds requests in memory, one read each, like the pasteboard does.
private final class MemoryMailbox: HandoffMailbox, Sendable {
    let box = Mutex<[HandoffToken: Data]>([:])

    func post(_ data: Data, for token: HandoffToken) throws {
        box.withLock { $0[token] = data }
    }

    func take(_ token: HandoffToken) -> Data? {
        box.withLock { $0.removeValue(forKey: token) }
    }
}

@Suite("Finder hand-off tokens")
struct HandoffTests {
    @Test func roundTripCarriesNoPathsInTheURL() throws {
        let handoff = Handoff(mailbox: MemoryMailbox())
        let url = try handoff.send(HandoffRequest(action: .extractHere, paths: ["/Users/a/Downloads/secret plan.zip"]))
        #expect(url.scheme == "stow" && url.host == "handoff")
        #expect(!url.absoluteString.contains("Downloads") && !url.absoluteString.contains("zip"))
        let request = try handoff.receive(url)
        #expect(request.action == .extractHere)
        #expect(request.paths == ["/Users/a/Downloads/secret plan.zip"])
    }

    @Test func tokensWorkOnce() throws {
        let handoff = Handoff(mailbox: MemoryMailbox())
        let url = try handoff.send(HandoffRequest(action: .open, paths: ["/a.zip"]))
        _ = try handoff.receive(url)
        #expect(throws: HandoffError.unknownToken) { try handoff.receive(url) }
    }

    @Test func staleRequestsAreRefused() throws {
        let handoff = Handoff(mailbox: MemoryMailbox())
        let url = try handoff.send(HandoffRequest(action: .open, paths: ["/a.zip"], created: .now - 61))
        #expect(throws: HandoffError.expired) { try handoff.receive(url) }
        let future = try handoff.send(HandoffRequest(action: .open, paths: ["/a.zip"], created: .now + 600))
        #expect(throws: HandoffError.expired) { try handoff.receive(future) }
    }

    @Test func unknownTokensDoNothing() {
        let handoff = Handoff(mailbox: MemoryMailbox())
        let url = Handoff.url(for: .random())
        #expect(throws: HandoffError.unknownToken) { try handoff.receive(url) }
    }

    @Test(arguments: [
        "stow://handoff/0123456789abcdef0123456789abcdef?path=/etc",
        "stow://handoff/0123456789abcdef0123456789abcdef#x",
        "stow://handoff/0123456789ABCDEF0123456789ABCDEF",
        "stow://handoff/0123456789abcdef",
        "stow://handoff/../0123456789abcdef0123456789abcdef",
        "stow://open/0123456789abcdef0123456789abcdef",
        "stow://user@handoff/0123456789abcdef0123456789abcdef",
        "stow://handoff:80/0123456789abcdef0123456789abcdef",
        "https://handoff/0123456789abcdef0123456789abcdef",
        "stow:///Users/a/Downloads/x.zip",
    ])
    func malformedURLsAreRejected(_ string: String) throws {
        let url = try #require(URL(string: string))
        #expect(Handoff.token(in: url) == nil)
    }

    @Test func wellFormedURLIsAccepted() throws {
        let url = try #require(URL(string: "stow://handoff/0123456789abcdef0123456789abcdef"))
        #expect(Handoff.token(in: url)?.value == "0123456789abcdef0123456789abcdef")
    }

    @Test func randomTokensAreDistinctAndValid() {
        let tokens = (0..<200).map { _ in HandoffToken.random() }
        #expect(Set(tokens).count == 200)
        #expect(tokens.allSatisfy { HandoffToken($0.value) != nil })
    }

    @Test(arguments: [[String](), ["relative/a.zip"], ["/a/../etc/passwd"], ["/a\0b"]])
    func implausiblePathsAreRefused(_ paths: [String]) throws {
        let mailbox = MemoryMailbox()
        let handoff = Handoff(mailbox: mailbox)
        let url = try handoff.send(HandoffRequest(action: .extractHere, paths: paths))
        #expect(throws: HandoffError.invalidRequest) { try handoff.receive(url) }
    }

    @Test func garbageInTheMailboxIsRefused() throws {
        let mailbox = MemoryMailbox()
        let token = HandoffToken.random()
        try mailbox.post(Data("{\"action\":\"format-disk\"}".utf8), for: token)
        #expect(throws: HandoffError.invalidRequest) { try Handoff(mailbox: mailbox).receive(Handoff.url(for: token)) }
    }

    @Test func pasteboardMailboxIsSingleUse() throws {
        let handoff = Handoff(mailbox: PasteboardMailbox())
        let url = try handoff.send(HandoffRequest(action: .compress, paths: ["/x/a.txt", "/x/b.txt"]))
        #expect(try handoff.receive(url).paths == ["/x/a.txt", "/x/b.txt"])
        #expect(throws: HandoffError.unknownToken) { try handoff.receive(url) }
    }

    @Test func fileMailboxRoundTripsAndIsSingleUse() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "stow-handoff-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let handoff = Handoff(mailbox: FileMailbox(root: root))
        let url = try handoff.send(HandoffRequest(action: .extractTo, paths: ["/Users/a/a.zip"]))
        #expect(!url.absoluteString.contains("zip"))
        #expect(try handoff.receive(url).paths == ["/Users/a/a.zip"])
        #expect(throws: HandoffError.unknownToken) { try handoff.receive(url) }
    }

    @Test func fileMailboxRefusesTokenCollision() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "stow-handoff-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let mailbox = FileMailbox(root: root)
        let token = HandoffToken.random()
        try mailbox.post(Data("one".utf8), for: token)
        #expect(throws: HandoffError.invalidRequest) { try mailbox.post(Data("two".utf8), for: token) }
    }

    @Test func fileMailboxSweepsStaleRequests() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "stow-handoff-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let mailbox = FileMailbox(root: root)
        let token = HandoffToken.random()
        try mailbox.post(Data("{}".utf8), for: token)
        let file = root.appending(path: "handoff/\(token.value).json")
        let stale = Date.now.addingTimeInterval(-(Handoff.lifetime * 2 + 5))
        try FileManager.default.setAttributes([.modificationDate: stale], ofItemAtPath: file.path)
        mailbox.sweep(now: .now)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func defaultMailboxIsFileWhenContainerExistsElsePasteboard() {
        let mailbox = Handoff.defaultMailbox()
        if AppGroup.containerURL != nil {
            #expect(mailbox is FileMailbox)
        } else {
            #expect(mailbox is PasteboardMailbox)
        }
    }

    @Test func appGroupIdentifierMatchesEntitlements() {
        #expect(AppGroup.identifier == "group.app.stow.Stow")
    }
}

@Suite("Finder menu settings store")
struct FinderMenuSettingsStoreTests {
    @Test func settingsRoundTripThroughAFolder() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "stow-settings-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let settings = FinderMenuSettings(showsOnExternalDrives: true)
        try FinderMenuSettings.publish(settings, into: root)
        #expect(FinderMenuSettings.published(from: root) == settings)
    }
}

@Suite("Finder menu")
struct FinderMenuTests {
    private let settings = FinderMenuSettings()

    @Test func archivesGetExtractActions() {
        #expect(FinderMenu.actions(for: ["/u/a.zip"], settings: settings) == [.extractHere, .extractTo, .open, .compress])
        #expect(FinderMenu.actions(for: ["/u/a.zip", "/u/b.tar.xz"], settings: settings) == [.extractHere, .extractTo, .compress])
    }

    @Test func otherFilesOnlyCompress() {
        #expect(FinderMenu.actions(for: ["/u/a.pdf"], settings: settings) == [.compress])
        #expect(FinderMenu.actions(for: ["/u/a.zip", "/u/b.pdf"], settings: settings) == [.compress])
        #expect(FinderMenu.actions(for: [], settings: settings).isEmpty)
    }

    @Test func externalDrivesAreOptIn() {
        #expect(FinderMenu.actions(for: ["/Volumes/USB/a.zip"], settings: settings).isEmpty)
        let on = FinderMenuSettings(showsOnExternalDrives: true)
        #expect(FinderMenu.actions(for: ["/Volumes/USB/a.zip"], settings: on).first == .extractHere)
        #expect(!FinderMenu.isOnExternalVolume("/Users/a/Volumes/b.zip"))
    }
}

@Suite("Quick Compress and folder grants")
struct QuickCompressTests {
    @Test func namesFollowFinder() {
        let none: (URL) -> Bool = { _ in false }
        #expect(QuickCompress.destination(for: [URL(filePath: "/u/Report.pdf")], exists: none).path == "/u/Report.zip")
        #expect(QuickCompress.destination(for: [URL(filePath: "/u/Photos", directoryHint: .isDirectory)], exists: none).path == "/u/Photos.zip")
        #expect(QuickCompress.destination(for: [URL(filePath: "/u/a.txt"), URL(filePath: "/u/b.txt")], exists: none).path == "/u/Archive.zip")
    }

    @Test func takenNamesAreNumbered() {
        let taken: Set<String> = ["/u/Archive.zip", "/u/Archive 2.zip"]
        let url = QuickCompress.destination(for: [URL(filePath: "/u/a"), URL(filePath: "/u/b")]) { taken.contains($0.path) }
        #expect(url.path == "/u/Archive 3.zip")
    }

    @Test func nestedGrantsCollapse() {
        let folders = ["/Users/a", "/Users/a/Downloads", "/Users/ab", "/Volumes/X/y"].map { URL(filePath: $0) }
        #expect(FolderAccess.minimal(folders).map(\.path) == ["/Users/a", "/Users/ab", "/Volumes/X/y"])
    }
}
