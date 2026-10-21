import Foundation
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
