import Foundation
import Testing
@testable import Stow

@Suite("Tray")
struct TrayTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "TrayTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func idleHidesOnlyWhenNothingKeepsItOpen() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let later = start.addingTimeInterval(31)
        #expect(TrayRules.shouldHide(lastActivity: start, now: later, idleSeconds: 30, pinned: false, isDragging: false, isHovered: false))
        #expect(!TrayRules.shouldHide(lastActivity: start, now: start.addingTimeInterval(29), idleSeconds: 30,
                                      pinned: false, isDragging: false, isHovered: false))
        #expect(!TrayRules.shouldHide(lastActivity: start, now: later, idleSeconds: 30, pinned: true, isDragging: false, isHovered: false))
        #expect(!TrayRules.shouldHide(lastActivity: start, now: later, idleSeconds: 30, pinned: false, isDragging: true, isHovered: false))
        #expect(!TrayRules.shouldHide(lastActivity: start, now: later, idleSeconds: 30, pinned: false, isDragging: false, isHovered: true))
        #expect(!TrayRules.shouldHide(lastActivity: start, now: start.addingTimeInterval(9999), idleSeconds: 0,
                                      pinned: false, isDragging: false, isHovered: false))
        #expect(TrayRules.idleChoices.contains(0) && TrayRules.idleChoices.contains(30))
    }

    @Test func addingSkipsDuplicates() {
        let a = URL(filePath: "/tmp/a.txt"), b = URL(filePath: "/tmp/b.txt")
        let fresh = TrayRules.newURLs([a, b, URL(filePath: "/tmp/./b.txt"), b], existing: [a])
        #expect(fresh == [b])
    }

    @Test func selectionFollowsFinder() {
        let ids = (0..<5).map { _ in UUID() }
        var result = TrayRules.select(ids[1], in: ids, current: [], anchor: nil, command: false, shift: false)
        #expect(result.selection == [ids[1]] && result.anchor == ids[1])
        result = TrayRules.select(ids[3], in: ids, current: result.selection, anchor: result.anchor, command: false, shift: true)
        #expect(result.selection == Set(ids[1...3]))
        result = TrayRules.select(ids[2], in: ids, current: result.selection, anchor: result.anchor, command: true, shift: false)
        #expect(result.selection == [ids[1], ids[3]] && result.anchor == ids[2])
        result = TrayRules.select(ids[0], in: ids, current: result.selection, anchor: result.anchor, command: true, shift: true)
        #expect(result.selection == Set([ids[0], ids[1], ids[2], ids[3]]))
        result = TrayRules.select(ids[4], in: ids, current: result.selection, anchor: result.anchor, command: false, shift: false)
        #expect(result.selection == [ids[4]])
    }

    @Test func freeNameCountsUp() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(TrayRules.freeName("New Folder", in: root) == "New Folder")
        try FileManager.default.createDirectory(at: root.appending(path: "New Folder"), withIntermediateDirectories: false)
        #expect(TrayRules.freeName("New Folder", in: root) == "New Folder 2")
        try FileManager.default.createDirectory(at: root.appending(path: "New Folder 2"), withIntermediateDirectories: false)
        #expect(TrayRules.freeName("New Folder", in: root) == "New Folder 3")
    }

    @Test func browsingListsFoldersFirst() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("b".utf8).write(to: root.appending(path: "b.txt"))
        try Data("a".utf8).write(to: root.appending(path: "A.zip"))
        try Data().write(to: root.appending(path: ".hidden"))
        try FileManager.default.createDirectory(at: root.appending(path: "zeta"), withIntermediateDirectories: false)
        let children = TrayRules.children(of: root)
        #expect(children.map(\.name) == ["zeta", "A.zip", "b.txt"])
        #expect(children[0].isFolder && !children[1].isFolder)
        #expect(children[1].isArchive && !children[2].isArchive)
        #expect(children[0].contentType == .folder)
    }

    @Test func borderSettingRoundTrips() throws {
        let name = "TrayTests.\(UUID().uuidString)"
        let store = try #require(UserDefaults(suiteName: name))
        defer { store.removePersistentDomain(forName: name) }
        store.set("pink", forKey: SettingsKeys.trayBorder)
        #expect(SettingsKeys.trayBorder(in: store) == .pink)
        store.set("nonsense", forKey: SettingsKeys.trayBorder)
        #expect(SettingsKeys.trayBorder(in: store) == .accent)
        store.set(60, forKey: SettingsKeys.trayIdleSeconds)
        #expect(SettingsKeys.trayIdleSeconds(in: store) == 60)
        store.set(17, forKey: SettingsKeys.trayIdleSeconds)
        #expect(SettingsKeys.trayIdleSeconds(in: store) == 30)
    }

    @Test @MainActor func trayAddsAndCollectsTargets() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let a = root.appending(path: "a.txt"), b = root.appending(path: "b.zip")
        try Data("a".utf8).write(to: a)
        try Data("b".utf8).write(to: b)
        let tray = TrayController()
        tray.add([a, b, a])
        #expect(tray.items.count == 2)
        #expect(tray.targetURLs.count == 2)
        tray.click(tray.items[1], command: false, shift: false)
        #expect(tray.targetURLs == [b])
        #expect(tray.canExtract)
        tray.removeSelected()
        #expect(tray.items.map(\.name) == ["a.txt"])
        tray.clear()
        #expect(tray.items.isEmpty && tray.selection.isEmpty)
    }

    @Test func dropPointsOutNewAndRepeatedItems() {
        let a = TrayItem(url: URL(filePath: "/tmp/a.txt")), b = TrayItem(url: URL(filePath: "/tmp/b.txt"))
        let sample = TrayItem(name: "Sample.pdf", size: 1)
        #expect(TrayRules.matching([URL(filePath: "/tmp/./b.txt")], in: [a, b, sample]) == [b.id])
        #expect(TrayRules.matching([], in: [a, b]).isEmpty)
    }

    @Test @MainActor func trayMarksWhatADropBrought() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let a = root.appending(path: "a.txt"), b = root.appending(path: "b.txt")
        try Data("a".utf8).write(to: a)
        try Data("b".utf8).write(to: b)
        let tray = TrayController()
        tray.add([a])
        #expect(tray.arrived == [tray.items[0].id])
        // Dropping a again with b: both are pointed out, a is not added twice.
        tray.add([a, b])
        #expect(tray.items.count == 2)
        #expect(tray.arrived == Set(tray.items.map(\.id)))
    }

    @Test @MainActor func collectingKeepsTheQuestionOpenForAnUnusableName() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let a = root.appending(path: "a.txt")
        try Data("a".utf8).write(to: a)
        try FileManager.default.createDirectory(at: root.appending(path: "Taken"), withIntermediateDirectories: false)
        let tray = TrayController()
        tray.add([a])
        tray.beginCollecting(remembered: nil)
        #expect(tray.collectDestination?.standardizedFileURL == root.standardizedFileURL) // one folder: that one
        tray.collectingName = "a/b"
        await tray.collectIntoFolder()
        #expect(tray.collectingName == "a/b")
        #expect(tray.collectProblem != nil)
        #expect(tray.failure == nil)
        tray.collectingName = "Taken"
        #expect(tray.collectProblem == nil) // typing clears it
        await tray.collectIntoFolder()
        #expect(tray.collectingName == "Taken")
        #expect(tray.collectProblem != nil)
        #expect(tray.items.map(\.name) == ["a.txt"])
    }

    @Test func destinationFollowsOneRule() throws {
        let a = URL(filePath: "/tmp/A/one.txt"), a2 = URL(filePath: "/tmp/A/two.txt"), b = URL(filePath: "/tmp/B/three.txt")
        let remembered = URL(filePath: "/tmp/Chosen", directoryHint: .isDirectory)
        #expect(GatherDestination.sources(of: [a, b, a2]).map(\.count) == [2, 1])
        #expect(GatherDestination.sources(of: [a, b, a2]).map(\.folder.lastPathComponent) == ["A", "B"])
        // One folder: that folder, whatever was remembered.
        #expect(GatherDestination.suggestion(for: [a, a2], remembered: remembered)?.lastPathComponent == "A")
        // Several: the remembered folder, or nothing (ask).
        #expect(GatherDestination.suggestion(for: [a, b], remembered: remembered) == remembered)
        #expect(GatherDestination.suggestion(for: [a, b], remembered: nil) == nil)
        #expect(GatherDestination.suggestion(for: [], remembered: remembered) == nil)

        let store = try #require(UserDefaults(suiteName: "GatherDestinationTests-\(UUID().uuidString)"))
        GatherDestination.remember(remembered, for: [a, a2], in: store) // one folder: not remembered
        #expect(GatherDestination.remembered(in: store) == nil)
        GatherDestination.remember(remembered, for: [a, b], in: store)
        #expect(GatherDestination.remembered(in: store)?.path == "/tmp/Chosen")
    }

    @Test @MainActor func collectingFromSeveralFoldersAsksWhere() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        // Remembering writes the app's own defaults: put back what was there.
        let saved = UserDefaults.standard.string(forKey: GatherDestination.key)
        defer { UserDefaults.standard.set(saved, forKey: GatherDestination.key) }
        let a = root.appending(path: "A/one.txt"), b = root.appending(path: "B/two.txt"), out = root.appending(path: "Out")
        for url in [a, b] {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: url)
        }
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: false)
        let tray = TrayController()
        tray.add([a, b])
        tray.beginCollecting(remembered: nil)
        #expect(tray.collectsFromSeveralFolders)
        #expect(tray.collectDestination == nil)
        await tray.collectIntoFolder() // nowhere chosen: asks, makes nothing
        #expect(tray.collectingName == "New Folder")
        #expect(tray.collectProblem != nil)
        tray.chooseCollectDestination(out)
        #expect(tray.collectProblem == nil)
        await tray.collectIntoFolder()
        let made = out.appending(path: "New Folder")
        #expect(FileManager.default.fileExists(atPath: made.appending(path: "one.txt").path))
        #expect(FileManager.default.fileExists(atPath: made.appending(path: "two.txt").path))
        #expect(FileManager.default.fileExists(atPath: a.path)) // copies: the originals stay
        #expect(tray.collected?.standardizedFileURL == made.standardizedFileURL)
        #expect(tray.items.map(\.name) == ["New Folder"])
        #expect(GatherDestination.remembered()?.standardizedFileURL.path == out.standardizedFileURL.path)
        tray.clear()
        #expect(tray.collected == nil)
    }

    @Test @MainActor func aSuggestedNameFollowsTheChosenFolder() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let a = root.appending(path: "a.txt"), other = root.appending(path: "Other")
        try Data("a".utf8).write(to: a)
        try FileManager.default.createDirectory(at: other.appending(path: "New Folder"), withIntermediateDirectories: true)
        let tray = TrayController()
        tray.add([a])
        tray.beginCollecting(remembered: nil)
        #expect(tray.collectingName == "New Folder")
        tray.chooseCollectDestination(other)
        #expect(tray.collectingName == "New Folder 2") // Stow's suggestion follows the folder
        tray.collectingName = "Mine"
        tray.chooseCollectDestination(root)
        #expect(tray.collectingName == "Mine") // a typed name stays
    }

    @Test @MainActor func removingTakesTheSelectionAndCanBeUndone() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let urls = try ["a.txt", "b.txt", "c.txt", "d.txt"].map { name in
            let url = root.appending(path: name)
            try Data(name.utf8).write(to: url)
            return url
        }
        let tray = TrayController()
        tray.add(urls)
        tray.removeSelected() // nothing selected: nothing removed
        #expect(tray.items.count == 4)
        let (a, b, c, d) = (tray.items[0], tray.items[1], tray.items[2], tray.items[3])
        tray.click(b, command: false, shift: false)
        tray.click(d, command: true, shift: false)
        tray.removeSelected()
        #expect(tray.items.map(\.name) == ["a.txt", "c.txt"])
        #expect(tray.selection.isEmpty)
        #expect(tray.undoManager.undoActionName == "Remove from Tray")
        tray.undoManager.undo()
        #expect(tray.items.map(\.name) == ["a.txt", "b.txt", "c.txt", "d.txt"]) // back in place
        #expect(tray.selection == [b.id, d.id])
        tray.undoManager.redo()
        #expect(tray.items.map(\.name) == ["a.txt", "c.txt"])
        #expect(FileManager.default.fileExists(atPath: urls[1].path)) // the Tray never touches the file

        // A row's own ⓧ takes only that row, even inside a selection.
        tray.click(a, command: false, shift: false)
        tray.click(c, command: true, shift: false)
        tray.remove(c)
        #expect(tray.items.map(\.name) == ["a.txt"])
        #expect(tray.selection == [a.id])

        tray.clear()
        #expect(tray.items.isEmpty)
        #expect(tray.undoManager.undoActionName == "Clear Tray")
        tray.undoManager.undo()
        #expect(tray.items.map(\.name) == ["a.txt"])
    }

    @Test @MainActor func undoDoesNotDoubleAFileDroppedAgain() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let a = root.appending(path: "a.txt")
        try Data("a".utf8).write(to: a)
        let tray = TrayController()
        tray.add([a])
        tray.clear()
        tray.add([a])
        tray.undoManager.undo() // undoes the clear: a is already back
        #expect(tray.items.count == 1)
    }

    @Test @MainActor func aMenuOnAnUnselectedRowSelectsItFirst() {
        let tray = TrayController()
        tray.items = [TrayItem(name: "a", size: 1), TrayItem(name: "b", size: 1), TrayItem(name: "c", size: 1)]
        let (a, b, c) = (tray.items[0], tray.items[1], tray.items[2])
        tray.click(a, command: false, shift: false)
        tray.click(b, command: true, shift: false)
        tray.selectForMenu(b.id) // part of the selection: the whole selection stays
        #expect(tray.selection == [a.id, b.id])
        tray.selectForMenu(c.id) // outside it: that row alone
        #expect(tray.selection == [c.id])
    }

    @Test @MainActor func trayBrowsesIntoFolders() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let inner = root.appending(path: "Photos", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: false)
        try Data("x".utf8).write(to: inner.appending(path: "x.jpg"))
        let tray = TrayController()
        tray.add([inner])
        tray.open(tray.items[0])
        #expect(tray.folderTitle == "Photos")
        #expect(tray.visibleItems.map(\.name) == ["x.jpg"])
        tray.goBack()
        #expect(tray.folderTitle == nil)
        #expect(tray.visibleItems.count == 1)
    }
}
