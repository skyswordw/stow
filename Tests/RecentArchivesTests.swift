import AppKit
import Testing
@testable import Stow

@MainActor
@Suite("Recent archives")
struct RecentArchivesTests {
    /// A scratch folder of empty "archives" and a private defaults domain.
    private final class Scratch {
        let folder = FileManager.default.temporaryDirectory.appending(path: "RecentArchivesTests-\(UUID().uuidString)")
        let suite = "RecentArchivesTests.\(UUID().uuidString)"
        let defaults: UserDefaults

        init() throws {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defaults = try #require(UserDefaults(suiteName: suite))
        }

        func file(_ name: String) throws -> URL {
            let url = folder.appending(path: name)
            try Data("PK".utf8).write(to: url)
            return url
        }

        deinit {
            try? FileManager.default.removeItem(at: folder)
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
    }

    @Test(arguments: ["demo", "test-environment", "test-class"])
    func applicationTestAndDemoHistoryNeverTouchesPersistentEntries(_ mode: String) throws {
        let scratch = try Scratch()
        let ordinary = RecentArchives(defaults: scratch.defaults)
        ordinary.add(try scratch.file("user.zip"))
        let before = scratch.defaults.data(forKey: RecentArchives.key)
        if mode == "demo" { scratch.defaults.set("open", forKey: "StowScene") }
        let history = RecentArchives.forApplication(defaults: scratch.defaults,
            environment: mode == "test-environment" ? ["XCTestConfigurationFilePath": "/tmp/test.xctestconfiguration"] : [:],
            testCaseClassPresent: mode == "test-class")
        #expect(history.entries.isEmpty)
        // Enough test opens to have evicted a real entry if the standard persistence path leaked.
        for index in 0...RecentArchives.limit { history.add(try scratch.file("test-\(index).zip")) }
        history.clear()
        #expect(scratch.defaults.data(forKey: RecentArchives.key) == before)
        #expect(RecentArchives(defaults: scratch.defaults).entries.map(\.name) == ["user.zip"])
    }

    @Test func ordinaryApplicationHistoryStillPersists() throws {
        let scratch = try Scratch()
        let history = RecentArchives.forApplication(defaults: scratch.defaults, environment: [:], testCaseClassPresent: false)
        history.add(try scratch.file("ordinary.zip"))
        let restored = RecentArchives.forApplication(defaults: scratch.defaults, environment: [:], testCaseClassPresent: false)
        #expect(restored.entries.map(\.name) == ["ordinary.zip"])
    }

    @Test func appStateInTheTestHostDoesNotWriteTheUserHistory() throws {
        let before = UserDefaults.standard.data(forKey: RecentArchives.key)
        let app = AppState()
        #expect(app.recents.entries.isEmpty)
        app.recents.add(URL(filePath: "/tmp/Stow-test-history-\(UUID().uuidString).zip"))
        #expect(app.recents.entries.count == 1)
        app.recents.clear()
        #expect(UserDefaults.standard.data(forKey: RecentArchives.key) == before)
    }

    @Test func addsNewestFirst() throws {
        let scratch = try Scratch()
        let recents = RecentArchives(defaults: scratch.defaults)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        for (offset, name) in ["a.zip", "b.7z", "c.tar.xz"].enumerated() {
            recents.add(try scratch.file(name), at: start.addingTimeInterval(Double(offset) * 60))
        }
        #expect(recents.visible.map(\.name) == ["c.tar.xz", "b.7z", "a.zip"])
        #expect(recents.visible.first?.openedAt == start.addingTimeInterval(120))
        #expect(recents.visible.first?.folder.lastPathComponent == scratch.folder.lastPathComponent)
    }

    @Test func reopeningMovesToTopWithoutDuplicates() throws {
        let scratch = try Scratch()
        let recents = RecentArchives(defaults: scratch.defaults)
        let a = try scratch.file("a.zip")
        recents.add(a)
        recents.add(try scratch.file("b.zip"))
        // The same file spelled differently (/var vs /private/var, a `..` detour) is still one entry.
        let detour = scratch.folder.appending(path: "x/../a.zip")
        recents.add(detour)
        recents.add(URL(filePath: a.path.replacingOccurrences(of: "/private/var/", with: "/var/")))
        #expect(recents.visible.map(\.name) == ["a.zip", "b.zip"])
    }

    @Test func keepsTheLimit() throws {
        let scratch = try Scratch()
        let recents = RecentArchives(defaults: scratch.defaults)
        for index in 0..<(RecentArchives.limit + 3) {
            recents.add(try scratch.file("archive \(index).zip"))
        }
        #expect(recents.entries.count == RecentArchives.limit)
        #expect(recents.visible.first?.name == "archive \(RecentArchives.limit + 2).zip")
        #expect(!recents.visible.contains { $0.name == "archive 0.zip" })
    }

    @Test func persistsAcrossLaunches() throws {
        let scratch = try Scratch()
        let first = RecentArchives(defaults: scratch.defaults)
        first.add(try scratch.file("a.zip"))
        first.add(try scratch.file("b.zip"))
        let second = RecentArchives(defaults: scratch.defaults)
        #expect(second.visible.map(\.name) == ["b.zip", "a.zip"])
        #expect(second.visible.allSatisfy { $0.bookmark != nil })
    }

    @Test func hidesMissingFiles() throws {
        let scratch = try Scratch()
        let recents = RecentArchives(defaults: scratch.defaults)
        let gone = try scratch.file("gone.zip")
        recents.add(gone)
        recents.add(try scratch.file("kept.zip"))
        try FileManager.default.removeItem(at: gone)
        recents.refresh()
        #expect(recents.visible.map(\.name) == ["kept.zip"])
        // Hidden, not forgotten: a file on a drive that comes back shows up again.
        #expect(recents.entries.count == 2)
        let entry = try #require(recents.entries.first { $0.name == "gone.zip" })
        #expect(recents.url(for: entry) == nil)
        // And a new launch doesn't show it either.
        #expect(RecentArchives(defaults: scratch.defaults).visible.map(\.name) == ["kept.zip"])
    }

    @Test func followsMovedFiles() throws {
        let scratch = try Scratch()
        let recents = RecentArchives(defaults: scratch.defaults)
        let original = try scratch.file("before.zip")
        recents.add(original)
        let moved = scratch.folder.appending(path: "after.zip")
        try FileManager.default.moveItem(at: original, to: moved)
        recents.refresh()
        #expect(recents.visible.map(\.name) == ["after.zip"])
        let entry = try #require(recents.visible.first)
        #expect(recents.url(for: entry).map(RecentArchives.key(for:)) == RecentArchives.key(for: moved))
    }

    @Test func clearEmptiesTheList() throws {
        let scratch = try Scratch()
        let recents = RecentArchives(defaults: scratch.defaults)
        recents.add(try scratch.file("a.zip"))
        recents.add(try scratch.file("b.zip"))
        recents.clear()
        #expect(recents.visible.isEmpty)
        #expect(scratch.defaults.object(forKey: RecentArchives.key) == nil)
        #expect(RecentArchives(defaults: scratch.defaults).visible.isEmpty)
    }

    @Test func removesOne() throws {
        let scratch = try Scratch()
        let recents = RecentArchives(defaults: scratch.defaults)
        recents.add(try scratch.file("a.zip"))
        recents.add(try scratch.file("b.zip"))
        recents.remove(try #require(recents.visible.first))
        #expect(RecentArchives(defaults: scratch.defaults).visible.map(\.name) == ["a.zip"])
    }

    @Test func previewIsNeitherSavedNorChecked() throws {
        let scratch = try Scratch()
        let recents = RecentArchives(defaults: scratch.defaults)
        recents.preview([("/Volumes/Nowhere/Old Backup.rar", .now)])
        recents.refresh()
        #expect(recents.visible.map(\.name) == ["Old Backup.rar"])
        #expect(scratch.defaults.object(forKey: RecentArchives.key) == nil)
    }

    @Test func menuTitlesSayTheFolderOnlyForTwins() {
        func entry(_ path: String) -> RecentArchives.Entry { .init(path: path, openedAt: .now) }
        let entries = [entry("/a/Downloads/Brand Kit.zip"), entry("/a/Desktop/Brand Kit.zip"), entry("/a/Desktop/Fonts.zip")]
        #expect(entries.map { OpenRecentMenu.title(for: $0, among: entries) }
                == ["Brand Kit.zip — Downloads", "Brand Kit.zip — Desktop", "Fonts.zip"])
    }

    @Test func displaysFolderAndDate() {
        let home = FolderAccess.home.path
        let entry = RecentArchives.Entry(path: "\(home)/Downloads/a.zip", openedAt: .now.addingTimeInterval(-5))
        #expect(entry.folderDisplay == "~/Downloads")
        #expect(RecentArchives.Entry(path: "/Volumes/Disk/a.zip", openedAt: .now).folderDisplay == "/Volumes/Disk")
        #expect(entry.openedDisplay() == Date.now.formatted(.relative(presentation: .named, unitsStyle: .wide)))
    }
}

@MainActor
@Suite("Dock menu", .serialized)
struct DockMenuTests {
    @Test func menuUsesExistingHistoryAndMarksTheCurrentWindow() throws {
        let temp = try TemporaryFolder()
        defer { temp.cleanUp() }
        let existing = temp.url.appending(path: "existing.zip")
        try Data("fixture".utf8).write(to: existing)
        let app = AppState()
        app.recents.add(existing)
        app.recents.add(temp.url.appending(path: "missing.zip"))
        let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        window.identifier = NSUserInterfaceItemIdentifier("creation-instance")
        window.title = "Create Archive"
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        let controller = DockMenuController()
        let menu = controller.makeMenu(app: app, windows: [window], current: window)
        #expect(menu.items.count == 3)
        #expect(menu.items.first?.title == "existing.zip")
        #expect(menu.items.first?.submenu == nil)
        #expect(menu.items.first?.representedObject as? String == app.recents.visible.first?.id)
        #expect(menu.items[1].isSeparatorItem)
        #expect(menu.items.last?.title == "Create Archive")
        #expect(menu.items.last?.state == .on)
        window.orderOut(nil)
        let hidden = controller.makeMenu(app: app, windows: [window], current: window)
        #expect(hidden.items.count == 1, "A closed window must not remain in the Dock menu")
        app.recents.clear()
        #expect(controller.makeMenu(app: app, windows: [window], current: nil).items.isEmpty,
                "No empty submenu or separator is shown without history or open windows")
    }
}
