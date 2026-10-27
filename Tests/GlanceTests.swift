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
