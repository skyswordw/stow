import AppKit
import Testing
@testable import Stow

@MainActor
@Suite("Glance")
struct GlanceTests {
    /// An app whose Glance stays off screen and whose full window is counted, not shown.
    private final class Harness {
        let app = AppState()
        var mainClosed = 0
        var mainOpened = 0

        init() {
            app.glance.presentsWindow = false
            app.glance.closeMainWindow = { [unowned self] in mainClosed += 1 }
            app.glance.openMainWindow = { [unowned self] in mainOpened += 1 }
            app.showMainWindow = { [unowned self] in mainOpened += 1 }
        }
    }

    private struct Place: Equatable {
        let folder: String
        let selection: Set<ArchiveEntry.ID>
        let history: [String]
        let historyIndex: Int

        init(_ model: BrowserModel) {
            folder = model.folder
            selection = model.selection
            history = model.history.map(\.folder)
            historyIndex = model.historyIndex
        }
    }

    @Test func switchingKeepsFolderSelectionAndHistory() throws {
        let harness = Harness()
        let app = harness.app, glance = app.glance
        app.openArchive(named: SampleArchive.make().name)
        let browser = try #require(app.browser)
        // Somewhere with both a Back and a Forward: top → Photos → Specs, then back to Photos.
        browser.navigate(to: "Photos")
        browser.navigate(to: "Specs")
        browser.goBack()
        browser.select(["Photos/Lighthouse.jpg", "Photos/Pier at Dawn.jpg"])
        let before = Place(browser)
        #expect(before.history == ["", "Photos", "Specs"] && before.historyIndex == 1)

        // Full window → Glance: the same model, untouched.
        glance.collapse(near: .zero, animated: false)
        #expect(glance.isShown)
        #expect(harness.mainClosed == 1)
        #expect(glance.model === browser && app.browser === browser)
        #expect(Place(browser) == before)
        #expect(browser.canGoBack && browser.canGoForward)

        // Browsing in Glance moves the shared history.
        glance.model?.goForward()
        #expect(browser.folder == "Specs")
        glance.model?.goBack()
        browser.select(["Photos/Rope Detail.jpg"])
        let inGlance = Place(browser)

        // Glance → full window: still the same model, with what was done in Glance.
        glance.expand()
        #expect(!glance.isShown)
        #expect(harness.mainOpened == 1)
        #expect(app.browser === browser)
        #expect(Place(browser) == inGlance)
        #expect(inGlance.folder == "Photos" && inGlance.selection == ["Photos/Rope Detail.jpg"])
        #expect(inGlance.history == before.history && inGlance.historyIndex == before.historyIndex)

        // And back again.
        glance.collapse(near: .zero, animated: false)
        #expect(glance.model === browser && Place(browser) == inGlance)
    }

    @Test func enclosingFolderUsesParentNotBack() throws {
        let harness = Harness()
        let app = harness.app, glance = app.glance
        app.openArchive(named: SampleArchive.make().name)
        let browser = try #require(app.browser)
        // Nested folder so Up is parent, while history Back would be a sibling path.
        browser.navigate(to: "Screens")
        browser.navigate(to: "Screens/Dark")
        #expect(browser.canGoUp)
        #expect(browser.folder == "Screens/Dark")

        glance.collapse(near: .zero, animated: false)
        glance.model?.goUp()
        #expect(browser.folder == "Screens")
        // Parent is not the same as Back: history still has Screens/Dark ahead.
        #expect(browser.canGoForward)
        #expect(browser.history.map(\.folder) == ["", "Screens", "Screens/Dark"])

        glance.model?.goUp()
        #expect(browser.folder.isEmpty)
        #expect(!browser.canGoUp)
    }

    @Test func columnParentSelectionIsVisibleInGlanceAndSurvivesTheRoundTrip() throws {
        let harness = Harness(), browser = columnBrowser()
        harness.app.browser = browser
        browser.navigate(to: "A")
        browser.navigate(to: "A/B")
        browser.columnSelect(try #require(browser.archive.entry(at: "A/B/c.txt")))
        browser.move(.left)
        let before = Place(browser)
        #expect(before.folder == "A/B" && before.selection == ["A/B"])
        #expect(!browser.visibleEntries.contains { $0.id == "A/B" })

        harness.app.glance.collapse(near: .zero, animated: false)
        #expect(browser.folder == "A")
        #expect(browser.selection == ["A/B"])
        #expect(browser.visibleEntries.contains { $0.id == "A/B" })
        #expect(browser.cursor == "A/B" && browser.scrollTarget == "A/B")
        #expect(browser.viewMode == .columns)
        #expect(Place(browser).history == before.history && browser.historyIndex == before.historyIndex)
        // Selection extraction still targets the visible folder, not its children or the archive.
        #expect(browser.selectedEntries.map(\.id) == ["A/B"])
        browser.run(.extract)
        #expect(browser.activity?.itemCount == 1)
        browser.cancelActivity()

        harness.app.glance.expand()
        #expect(Place(browser) == before)
        #expect(browser.cursor == "A/B" && browser.viewMode == .columns)
    }

    @Test func selectedRootAndEmptyFoldersAreVisibleInGlance() throws {
        let harness = Harness(), browser = columnBrowser()
        harness.app.browser = browser
        for path in ["A", "Empty"] {
            browser.columnSelect(try #require(browser.archive.entry(at: path)))
            let before = Place(browser)
            harness.app.glance.collapse(near: .zero, animated: false)
            #expect(browser.folder.isEmpty)
            #expect(browser.selection == [path])
            #expect(browser.visibleEntries.contains { $0.id == path })
            harness.app.glance.expand()
            #expect(Place(browser) == before)
        }
    }

    @Test func changingSelectionInGlanceDoesNotRestoreTheOldColumnFolder() throws {
        let harness = Harness(), browser = columnBrowser()
        harness.app.browser = browser
        browser.columnSelect(try #require(browser.archive.entry(at: "A/B")))
        harness.app.glance.collapse(near: .zero, animated: false)
        browser.select(["A/other.txt"])
        let changed = Place(browser)
        harness.app.glance.expand()
        #expect(Place(browser) == changed)
        #expect(browser.folder == "A" && browser.selection == ["A/other.txt"])

        // Opening the folder explicitly in Glance clears its selection and keeps its contents.
        harness.app.glance.collapse(near: .zero, animated: false)
        browser.open(try #require(browser.archive.entry(at: "A/B")))
        let opened = Place(browser)
        harness.app.glance.expand()
        #expect(Place(browser) == opened)
        #expect(browser.folder == "A/B" && browser.selection.isEmpty)
    }

    @Test func aDifferentFolderSelectedInGlanceOpensInColumns() throws {
        let harness = Harness(), browser = columnBrowser()
        harness.app.browser = browser
        browser.columnSelect(try #require(browser.archive.entry(at: "A")))
        harness.app.glance.collapse(near: .zero, animated: false)
        browser.select(["Empty"])
        harness.app.glance.expand()
        #expect(browser.folder == "Empty" && browser.selection == ["Empty"])
    }

    @Test func columnTransferKeepsSearchAndMultipleSelections() throws {
        let harness = Harness(), browser = columnBrowser()
        harness.app.browser = browser
        browser.columnSelect(try #require(browser.archive.entry(at: "A")))
        browser.query = "A"
        let searching = Place(browser)
        harness.app.glance.collapse(near: .zero, animated: false)
        harness.app.glance.expand()
        #expect(browser.query == "A" && Place(browser) == searching)

        browser.navigate(to: "", selecting: ["A", "Empty"])
        let multiple = Place(browser)
        harness.app.glance.collapse(near: .zero, animated: false)
        #expect(browser.selection.isSubset(of: Set(browser.visibleEntries.map(\.id))))
        harness.app.glance.expand()
        #expect(Place(browser) == multiple)
    }

    @Test func columnTransferStaysInsideTheSameNestedArchive() throws {
        let harness = Harness(), browser = columnBrowser()
        harness.app.browser = browser
        let inner = BrowserModel.Level(archive: columnBrowser().archive, entryPath: "Inner.zip")
        inner.password = "test-password"
        browser.navigate(to: "A/B", levels: [browser.level, inner])
        browser.columnSelect(try #require(browser.archive.entry(at: "A/B")))
        let before = Place(browser), ids = browser.levels.map(\.id)
        harness.app.glance.collapse(near: .zero, animated: false)
        #expect(browser.folder == "A" && browser.selection == ["A/B"])
        #expect(browser.levels.map(\.id) == ids && browser.level === inner)
        #expect(browser.visibleEntries.contains { $0.id == "A/B" })
        harness.app.glance.expand()
        #expect(Place(browser) == before && browser.levels.map(\.id) == ids)
        #expect(inner.password == "test-password")
    }

    @Test func editsInGlanceDoNotResurrectTheOldColumnSelection() throws {
        let harness = Harness()
        let browser = BrowserModel(archive: Archive(listing: ArchiveListing(type: "zip", entries: [
            ListedEntry(path: "A/B/c.txt", isFolder: false, size: 1),
            ListedEntry(path: "A/other.txt", isFolder: false, size: 1)
        ]), url: URL(filePath: "/tmp/ColumnTransfer-\(UUID().uuidString).zip")))
        browser.viewMode = .columns
        harness.app.browser = browser
        browser.columnSelect(try #require(browser.archive.entry(at: "A/B")))
        harness.app.glance.collapse(near: .zero, animated: false)
        browser.editSession.rename("A/B", to: "Renamed")
        #expect(browser.selection == ["A/Renamed"])
        harness.app.glance.expand()
        #expect(browser.folder == "A/Renamed" && browser.selection == ["A/Renamed"])

        harness.app.glance.collapse(near: .zero, animated: false)
        browser.editSession.delete(["A/Renamed"])
        harness.app.glance.expand()
        #expect(browser.folder == "A" && browser.selection.isEmpty)
        #expect(browser.editSession.isEdited)
    }

    private func columnBrowser() -> BrowserModel {
        let files = ["A/B/c.txt", "A/B/d.txt", "A/other.txt", "root.txt", "Empty"].map {
            ArchiveEntry(path: $0, isFolder: $0 == "Empty", size: 1, packedSize: 1, modified: .now)
        }
        let model = BrowserModel(archive: Archive(name: "Columns.zip", format: .zip, files: files))
        model.viewMode = .columns
        return model
    }

    /// Glance's title bar names the archive and what it is, wherever you are inside it (#159); the
    /// path over the files says where that is, from the archive down (#157).
    @Test func glanceKeepsArchiveIdentityApartFromThePath() throws {
        let harness = Harness()
        let app = harness.app
        app.openArchive(named: SampleArchive.make().name)
        let browser = try #require(app.browser)
        let subtitle = browser.subtitle
        #expect(browser.title == browser.archive.name)
        #expect(subtitle.contains("archive"))
        #expect(subtitle.contains("\(browser.archive.files.count) files"))
        #expect(browser.pathSegments.map(\.title) == [browser.archive.name])

        browser.navigate(to: "Photos")
        // The archive's identity doesn't turn into the folder's.
        #expect(browser.title == browser.archive.name)
        #expect(browser.subtitle == subtitle)
        #expect(browser.pathSegments.map(\.title) == [browser.archive.name, "Photos"])
        #expect(browser.pathSegments.first?.isArchive == true)
        #expect(browser.pathSegments.last?.isArchive == false)
    }

    @Test func noArchiveNoGlance() {
        let harness = Harness()
        harness.app.glance.collapse(near: .zero, animated: false)
        #expect(!harness.app.glance.isShown)
        #expect(harness.mainClosed == 0)
    }

    @Test func expandingWithoutGlanceDoesNothing() {
        let harness = Harness()
        harness.app.openArchive(named: SampleArchive.make().name)
        harness.app.glance.expand()
        #expect(harness.mainOpened == 0)
    }

    @Test func closingGlanceKeepsTheArchiveOpen() throws {
        let harness = Harness()
        harness.app.openArchive(named: SampleArchive.make().name)
        let browser = try #require(harness.app.browser)
        harness.app.glance.collapse(near: .zero, animated: false)
        harness.app.glance.close()
        #expect(!harness.app.glance.isShown)
        #expect(harness.app.browser === browser)
    }

    /// The opening screen's Close (and Escape) stops the opening, so the archive doesn't finish
    /// opening into a hidden Glance with no way back to it.
    @Test func closingWhileOpeningStopsTheOpening() async throws {
        let harness = Harness()
        let app = harness.app
        let zip = FileManager.default.temporaryDirectory.appending(path: "Glance \(UUID().uuidString).zip")
        try ZipFixture(entries: [.file("a.txt", "a")]).write(to: zip)
        defer { try? FileManager.default.removeItem(at: zip) }

        app.glance.open(zip)
        #expect(app.isOpening)
        #expect(app.glance.pendingName == zip.lastPathComponent)
        app.glance.stopOpening()
        #expect(!app.glance.isShown)
        #expect(!app.isOpening)
        #expect(app.glance.pendingName == nil)

        // Long enough for the listing to have landed had it carried on.
        try await Task.sleep(for: .milliseconds(500))
        #expect(app.browser == nil)
        #expect(app.openFailure == nil)
    }

    @Test func stopOpeningOnAnOpenArchiveIsAPlainClose() throws {
        let harness = Harness()
        harness.app.openArchive(named: SampleArchive.make().name)
        let browser = try #require(harness.app.browser)
        harness.app.glance.collapse(near: .zero, animated: false)
        harness.app.glance.stopOpening()
        #expect(!harness.app.glance.isShown)
        #expect(harness.app.browser === browser)
    }

    @Test(arguments: [false, true])
    func finderOpensInGlanceWhenAskedTo(_ glanceSetting: Bool) async throws {
        let harness = Harness()
        let app = harness.app
        UserDefaults.standard.set(glanceSetting, forKey: SettingsKeys.openInGlance)
        defer { UserDefaults.standard.removeObject(forKey: SettingsKeys.openInGlance) }
        let missing = FileManager.default.temporaryDirectory.appending(path: "Glance \(UUID().uuidString).zip")

        app.receive([missing])
        #expect(app.glance.isShown == glanceSetting)
        #expect(harness.mainClosed == (glanceSetting ? 1 : 0))
        #expect(harness.mainOpened == (glanceSetting ? 0 : 1))
        if glanceSetting { #expect(app.glance.pendingName == missing.lastPathComponent) }

        let deadline = ContinuousClock.now + .seconds(10)
        while app.isOpening, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(app.openFailure?.url?.lastPathComponent == missing.lastPathComponent)
    }

    @Test func settingDefaultsToTheFullWindow() throws {
        let name = "GlanceTests.\(UUID().uuidString)"
        let store = try #require(UserDefaults(suiteName: name))
        defer { store.removePersistentDomain(forName: name) }
        #expect(!SettingsKeys.flag(SettingsKeys.openInGlance, in: store))
        #expect(!SettingsKeys.flag(SettingsKeys.glancePinned, in: store))
    }

    // MARK: - Placement

    private static let size = GlancePlacement.defaultSize
    private static let screens = [
        CGRect(x: 0, y: 0, width: 1512, height: 944),          // laptop, menu bar taken off the top
        CGRect(x: -1920, y: 120, width: 1920, height: 1055),    // a second display to the left, Dock below
        CGRect(x: 1512, y: -600, width: 1080, height: 1890),    // portrait, below the main display
    ]

    @Test(arguments: GlancePlacement.Edge.allCases)
    func staysInsideTheVisibleAreaAtEveryEdge(_ edge: GlancePlacement.Edge) {
        for visible in Self.screens {
            let pointer = edge.pointer(in: visible)
            let frame = GlancePlacement.frame(size: Self.size, pointer: pointer, visible: visible)
            let room = visible.insetBy(dx: GlancePlacement.margin, dy: GlancePlacement.margin)
            #expect(room.contains(frame), "\(edge) on \(visible): \(frame)")
            #expect(frame.size == Self.size)
            // As close to the pointer as the screen allows: centred on it unless an edge is in the way.
            let centred = pointer.x - Self.size.width / 2
            if centred >= room.minX, centred + Self.size.width <= room.maxX {
                #expect(frame.midX == pointer.x)
            } else {
                #expect(frame.minX == room.minX || frame.maxX == room.maxX)
            }
        }
    }

    @Test func opensWithThePointerInItsToolbar() {
        let visible = Self.screens[0]
        let pointer = CGPoint(x: 700, y: 500)
        let frame = GlancePlacement.frame(size: Self.size, pointer: pointer, visible: visible)
        #expect(frame.midX == pointer.x)
        #expect(frame.maxY - pointer.y == GlancePlacement.pointerInset)
        let anchor = GlancePlacement.anchor(pointer: pointer, in: frame)
        #expect(anchor.x == 0.5)
        #expect(abs(anchor.y - GlancePlacement.pointerInset / Self.size.height) < 0.0001)
    }

    @Test func anchorStaysInsideTheWindowWhenClamped() {
        let visible = Self.screens[0]
        let pointer = GlancePlacement.Edge.bottomRight.pointer(in: visible)
        let frame = GlancePlacement.frame(size: Self.size, pointer: pointer, visible: visible)
        let anchor = GlancePlacement.anchor(pointer: pointer, in: frame)
        #expect((0...1).contains(anchor.x) && (0...1).contains(anchor.y))
        #expect(anchor.x == 1 && anchor.y == 1)
    }

    @Test func shrinksOnAScreenSmallerThanItself() {
        let visible = CGRect(x: 0, y: 0, width: 400, height: 360)
        let frame = GlancePlacement.frame(size: Self.size, pointer: CGPoint(x: 200, y: 180), visible: visible)
        #expect(frame == visible.insetBy(dx: GlancePlacement.margin, dy: GlancePlacement.margin))
    }

    @Test func reduceTransparencyGetsASolidBackground() {
        #expect(GlanceMaterial.resolve(reduceTransparency: false, override: false) == .glass)
        #expect(GlanceMaterial.resolve(reduceTransparency: true, override: false) == .solid)
        #expect(GlanceMaterial.resolve(reduceTransparency: false, override: true) == .solid)
    }

    @Test func classicPreferenceUsesFrostedUnlessReduceTransparency() {
        #expect(GlanceMaterial.resolve(reduceTransparency: false, preference: .classic, override: false) == .frosted)
        #expect(GlanceMaterial.resolve(reduceTransparency: false, preference: .liquidGlass, override: false) == .glass)
        #expect(GlanceMaterial.resolve(reduceTransparency: true, preference: .classic, override: false) == .solid)
        #expect(GlanceMaterial.resolve(reduceTransparency: false, preference: .classic, override: true) == .solid)
    }
}
