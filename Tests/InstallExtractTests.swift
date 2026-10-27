import Foundation
import Testing
@testable import Stow

@Suite("Conflict placement")
@MainActor
struct PlacementTests {
    /// A staged tree and a destination that already has some of the same names.
    struct Scene {
        let folder: TemporaryFolder
        var staged: URL { folder.url.appending(path: "Staged") }
        var out: URL { folder.url.appending(path: "Out") }

        init() throws {
            folder = try TemporaryFolder()
            try write("Staged/Docs/a.txt", "new a")
            try write("Staged/Docs/b.txt", "new b")
            try write("Staged/Docs/Sub/c.txt", "new c")
            try write("Out/Docs/a.txt", "old a")
            try write("Out/Docs/keep.txt", "mine")
        }

        func write(_ path: String, _ text: String) throws {
            let url = folder.url.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }

        func read(_ path: String) -> String? {
            (try? Data(contentsOf: out.appending(path: path))).map { String(decoding: $0, as: UTF8.self) }
        }

        func place(_ resolve: @escaping Placement.Resolver) async throws -> Placement.Result {
            try await Placement.place([(staged.appending(path: "Docs"), "Docs")], in: out, resolve: resolve)
        }
    }

    @Test func mergeThenReplaceFiles() async throws {
        let scene = try Scene()
        defer { scene.folder.cleanUp() }
        let result = try await scene.place { $0.canMerge ? .merge : .replace }

        #expect(result.placed.map(\.lastPathComponent) == ["Docs"])
        #expect(result.merged == 1 && result.replaced == 1)
        #expect(scene.read("Docs/a.txt") == "new a")
        #expect(scene.read("Docs/b.txt") == "new b")
        #expect(scene.read("Docs/Sub/c.txt") == "new c")
        #expect(scene.read("Docs/keep.txt") == "mine")
        // Only what moved in counts as new (it inherits a download's quarantine), not the merged folder.
        #expect(Set(result.added.map { String($0.path.dropFirst(scene.out.path.count + 1)) })
                == ["Docs/a.txt", "Docs/b.txt", "Docs/Sub"])
    }

    @Test func mergeAndKeepBothFiles() async throws {
        let scene = try Scene()
        defer { scene.folder.cleanUp() }
        _ = try await scene.place { $0.canMerge ? .merge : .keepBoth }

        #expect(scene.read("Docs/a.txt") == "old a")
        #expect(scene.read("Docs/a 2.txt") == "new a")
    }

    @Test func mergeAndSkipFiles() async throws {
        let scene = try Scene()
        defer { scene.folder.cleanUp() }
        let result = try await scene.place { $0.canMerge ? .merge : .skip }

        #expect(result.skipped == 1)
        #expect(scene.read("Docs/a.txt") == "old a")
        #expect(scene.read("Docs/b.txt") == "new b")
        #expect(!FileManager.default.fileExists(atPath: scene.out.appending(path: "Docs/a 2.txt").path))
    }

    @Test func keepBothFolders() async throws {
        let scene = try Scene()
        defer { scene.folder.cleanUp() }
        let result = try await scene.place { _ in .keepBoth }

        #expect(result.placed.map(\.lastPathComponent) == ["Docs 2"])
        #expect(scene.read("Docs/a.txt") == "old a")
        #expect(scene.read("Docs 2/a.txt") == "new a")
    }

    @Test func stoppingUndoesEverything() async throws {
        let scene = try Scene()
        defer { scene.folder.cleanUp() }
        let before = TemporaryFolder.contents(of: scene.out)
        var asked = 0
        await expectEngineFailure(.cancelled) {
            _ = try await scene.place { conflict throws(EngineError) in
                asked += 1
                if conflict.canMerge { return .merge }
                throw EngineError(.cancelled)
            }
        }
        #expect(asked == 2)
        #expect(TemporaryFolder.contents(of: scene.out) == before)
        #expect(scene.read("Docs/a.txt") == "old a")
        // The staged items are back where they were, so the staging folder cleans them up.
        #expect(FileManager.default.fileExists(atPath: scene.staged.appending(path: "Docs/b.txt").path))
    }

    @Test func packagesAreNeverMerged() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        for root in ["Staged", "Out"] {
            try FileManager.default.createDirectory(at: folder.url.appending(path: "\(root)/Tool.app/Contents"),
                                                    withIntermediateDirectories: true)
        }
        var sawMergeable = true
        _ = try await Placement.place([(folder.url.appending(path: "Staged/Tool.app"), "Tool.app")],
                                      in: folder.url.appending(path: "Out")) { conflict in
            sawMergeable = conflict.canMerge
            return .merge
        }
        #expect(!sawMergeable)
        #expect(FileManager.default.fileExists(atPath: folder.url.appending(path: "Out/Tool 2.app").path))
    }

    @Test func policyAppliesSettingsAndRemembersForAll() async throws {
        let file = Placement.Conflict(name: "a.txt", existing: URL(filePath: "/x/a.txt"), incoming: URL(filePath: "/y/a.txt"), canMerge: false)
        let folder = Placement.Conflict(name: "Docs", existing: URL(filePath: "/x/Docs"), incoming: URL(filePath: "/y/Docs"), canMerge: true)

        var fixed = Preferences.defaults
        fixed.folderConflict = .merge
        fixed.fileConflict = .skip
        let quiet = ConflictPolicy(fixed) { _ in Issue.record("shouldn't ask"); return nil }
        #expect(try await quiet.resolve(folder) == .merge)
        #expect(try await quiet.resolve(file) == .skip)

        var questions = 0
        let asking = ConflictPolicy(Preferences.defaults) { _ in
            questions += 1
            return (.replace, forAll: true)
        }
        #expect(try await asking.resolve(file) == .replace)
        #expect(try await asking.resolve(file) == .replace)
        #expect(questions == 1)

        let stopping = ConflictPolicy(Preferences.defaults) { _ in nil }
        await expectEngineFailure(.cancelled) { try await stopping.resolve(file) }
    }
}

@Suite("Preferences")
struct PreferencesTests {
    @Test func defaultsAreSafe() throws {
        let store = try #require(UserDefaults(suiteName: "StowTests-\(UUID().uuidString)"))
        let values = Preferences.values(in: store)
        #expect(values == Preferences.defaults)
        #expect(values.afterExtractAll == .keep)
        #expect(values.skipSystemFiles)
        #expect(!values.removeQuarantine)
        #expect(!values.closeWindowAfter)
    }

    @Test func storedValuesAreRead() throws {
        let store = try #require(UserDefaults(suiteName: "StowTests-\(UUID().uuidString)"))
        Preferences.set(Preferences.AfterwardsArchive.trash, for: Preferences.Key.afterExtractAll, in: store)
        Preferences.set(Preferences.FileConflict.replace, for: Preferences.Key.fileConflict, in: store)
        store.set(false, forKey: Preferences.Key.skipSystemFiles)
        store.set("nonsense", forKey: Preferences.Key.folderConflict)
        let values = Preferences.values(in: store)
        #expect(values.afterExtractAll == .trash)
        #expect(values.fileConflict == .replace)
        #expect(!values.skipSystemFiles)
        #expect(values.folderConflict == .ask)
    }
}

@Suite("Archive aftercare")
@MainActor
struct AftercareTests {
    @Test func keepLeavesTheArchive() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let archive = folder.url.appending(path: "kept.zip")
        try Data("zip".utf8).write(to: archive)
        let trashed = await ArchiveAftercare.apply(.keep, key: "unused", to: [archive], action: "")
        #expect(trashed.isEmpty)
        #expect(FileManager.default.fileExists(atPath: archive.path))
    }

    @Test func trashMovesTheArchiveToTheTrash() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let archive = folder.url.appending(path: "StowTest-trash-\(UUID().uuidString).zip")
        try Data("zip".utf8).write(to: archive)
        let trashed = await ArchiveAftercare.apply(.trash, key: "unused", to: [archive], action: "")
        #expect(trashed == [archive])
        #expect(!FileManager.default.fileExists(atPath: archive.path))
    }
}

@Suite("System files")
struct SystemFileTests {
    @Test(arguments: ["__MACOSX/a/._b.txt", "Docs/.DS_Store", "Docs/._a.txt", "Thumbs.db", "Pics/THUMBS.DB",
                      "Docs/desktop.ini", "Desktop.ini", ".Spotlight-V100", "Icon\r", ".fseventsd"])
    func skipped(path: String) {
        #expect(MacHelperFiles.matches(path))
    }

    @Test(arguments: [".gitignore", "src/.env", ".editorconfig", "Docs/.hidden-notes.txt", "Thumbs.db.txt", "a/desktop.ini.bak"])
    func kept(path: String) {
        #expect(!MacHelperFiles.matches(path))
    }
}

@Suite("Disk image layout")
struct DiskImageLayoutTests {
    @Test func hfsVolumeWithInstallerExtras() {
        let listing = ArchiveListing(type: "Dmg", physicalSize: 100, entries: [
            ListedEntry(path: "Stow Fixture", isFolder: true, size: 0),
            ListedEntry(path: "Stow Fixture/.background", isFolder: true, size: 0),
            ListedEntry(path: "Stow Fixture/.background/bg.png", isFolder: false, size: 3),
            ListedEntry(path: "Stow Fixture/.VolumeIcon.icns", isFolder: false, size: 10),
            ListedEntry(path: "Stow Fixture/.HFS+ Private Directory Data\r", isFolder: true, size: 0),
            ListedEntry(path: "Stow Fixture/[HFS+ Private Data]", isFolder: true, size: 0),
            ListedEntry(path: "Stow Fixture/Applications", isFolder: false, isSymlink: true, size: 13),
            ListedEntry(path: "Stow Fixture/Fixture.app/Contents/Info.plist", isFolder: false, size: 5),
            ListedEntry(path: "Stow Fixture/.gitignore", isFolder: false, size: 1),
        ])
        let archive = Archive(listing: listing, url: URL(filePath: "/tmp/Fixture.dmg"))

        #expect(archive.format == .dmg)
        #expect(archive.volumeRoot == "Stow Fixture")
        #expect(archive.dropTargets == [DiskImageLayout.DropTarget(path: "Stow Fixture/Applications", folder: "/Applications")])
        #expect(Set(archive.children(of: "Stow Fixture").map(\.name)) == ["Fixture.app", ".gitignore"])
        #expect(archive.checkup.contains { $0.title == "Installer layout hidden" })
        #expect(!archive.checkup.contains { $0.title.contains("symbolic link") })
        #expect(BrowserModel.suggestedSelection(in: archive) == "Stow Fixture/Fixture.app")
    }

    @Test func apfsVolumeAtTheTopWithAPlugInTarget() {
        let listing = ArchiveListing(type: "Dmg", physicalSize: 100, entries: [
            ListedEntry(path: "Echo.component/Contents/Info.plist", isFolder: false, size: 5),
            ListedEntry(path: "Components", isFolder: false, isSymlink: true, linkTarget: "/Library/Audio/Plug-Ins/Components", size: 34),
            ListedEntry(path: "Read Me.txt", isFolder: false, size: 4),
            ListedEntry(path: "Help", isFolder: false, isSymlink: true, linkTarget: "Read Me.txt", size: 11),
        ])
        let archive = Archive(listing: listing, url: URL(filePath: "/tmp/Echo.dmg"))

        #expect(archive.volumeRoot == "")
        #expect(archive.dropTargets.map(\.folder) == ["/Library/Audio/Plug-Ins/Components"])
        #expect(Set(archive.children(of: "").map(\.name)) == ["Echo.component", "Read Me.txt", "Help"])
        let plugIn = archive.children(of: "").first { $0.name == "Echo.component" }!
        #expect(NextStep.suggestions(for: [plugIn], dropTargets: archive.dropTargets).first
                == .copyTo(folder: "/Library/Audio/Plug-Ins/Components"))
    }

    @Test func zipsKeepEverything() {
        let listing = ArchiveListing(type: "zip", physicalSize: 100, entries: [
            ListedEntry(path: "Kit/.background/x.png", isFolder: false, size: 1),
            ListedEntry(path: "Kit/Applications", isFolder: false, isSymlink: true, size: 13),
        ])
        let archive = Archive(listing: listing, url: URL(filePath: "/tmp/Kit.zip"))
        #expect(archive.installerExtras.isEmpty && archive.dropTargets.isEmpty)
        #expect(archive.entries.count == 4)
    }

    @Test func downloadsInProgressAreRecognised() {
        #expect(DownloadCheck.isPartial(URL(filePath: "/tmp/Big.dmg.download")))
        #expect(DownloadCheck.isPartial(URL(filePath: "/tmp/Big.zip.crdownload")))
        #expect(!DownloadCheck.isPartial(URL(filePath: "/tmp/Big.dmg")))
    }
}
