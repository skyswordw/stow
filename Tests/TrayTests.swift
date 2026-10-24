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
        #expect(TrayRules.collectionParent(for: [root.appending(path: "x.txt")])?.standardizedFileURL == root.standardizedFileURL)
        #expect(TrayRules.collectionParent(for: []) == nil)
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
