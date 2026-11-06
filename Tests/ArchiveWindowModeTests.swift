import AppKit
import Testing
@testable import Stow

@Suite("Archive presentation choice")
@MainActor
struct ArchiveWindowModeTests {
    @Test func defaultRemembersLastWindowAndExplicitModesWin() throws {
        let name = "WindowMode.\(UUID().uuidString)"
        let store = try #require(UserDefaults(suiteName: name))
        defer { store.removePersistentDomain(forName: name) }
        #expect(SettingsKeys.archiveWindowMode(in: store) == .lastUsed)
        #expect(SettingsKeys.archiveWindow(in: store) == .browser)
        store.set("glance", forKey: SettingsKeys.lastArchiveWindow)
        #expect(SettingsKeys.archiveWindow(in: store) == .glance)
        store.set("browser", forKey: SettingsKeys.archiveWindowMode)
        #expect(SettingsKeys.archiveWindow(in: store) == .browser)
        store.set("glance", forKey: SettingsKeys.archiveWindowMode)
        store.set("browser", forKey: SettingsKeys.lastArchiveWindow)
        #expect(SettingsKeys.archiveWindow(in: store) == .glance)
        store.removeObject(forKey: SettingsKeys.archiveWindowMode)
        store.set(true, forKey: SettingsKeys.openInGlance)
        #expect(SettingsKeys.archiveWindowMode(in: store) == .glance)
        store.set(false, forKey: SettingsKeys.openInGlance)
        #expect(SettingsKeys.archiveWindowMode(in: store) == .browser)
        store.set("lastUsed", forKey: SettingsKeys.archiveWindowMode)
        #expect(SettingsKeys.archiveWindowMode(in: store) == .lastUsed)
    }

    @Test func choosingGlanceThenClosingAndReopeningKeepsGlance() throws {
        let name = "WindowMode.\(UUID().uuidString)"
        let store = try #require(UserDefaults(suiteName: name))
        defer { store.removePersistentDomain(forName: name) }
        let app = AppState()
        app.presentationDefaults = store
        app.glance.presentsWindow = false
        app.glance.closeMainWindow = {}
        app.showMainWindow = {}
        app.openArchive(named: "First.zip")
        app.glance.collapse(near: .zero, animated: false)
        #expect(SettingsKeys.archiveWindow(in: store) == .glance)
        app.glance.close()
        app.receive([URL(filePath: "/tmp/missing-\(UUID().uuidString).zip")])
        let second = try #require(app.additionalSessions.first)
        #expect(second.glance.isShown && second.isOpening)
        #expect(app.browser?.archive.name == "First.zip", "Opening a second archive preserves the first")
        second.cancelOpening()
        second.glance.expand()
        #expect(SettingsKeys.archiveWindow(in: store) == .browser)
        let restored = try #require(UserDefaults(suiteName: name))
        #expect(SettingsKeys.archiveWindow(in: restored) == .browser)
    }

    @Test func externalOpenEstablishesBrowserOwnershipBeforePresentation() throws {
        let name = "WindowMode.\(UUID().uuidString)"
        let store = try #require(UserDefaults(suiteName: name))
        defer { store.removePersistentDomain(forName: name) }
        let app = AppState()
        app.presentationDefaults = store
        var presented = false
        app.showMainWindow = {
            #expect(app.isOpening && app.usesBrowserWindow)
            #expect(app.browser == nil)
            presented = true
        }
        app.receive([URL(filePath: "/tmp/missing-\(UUID().uuidString).zip")])
        #expect(presented)
        app.mainWindowDidClose(.welcome)
        #expect(app.isOpening) // An obsolete Welcome cannot cancel Browser's load.
        app.mainWindowDidClose(.browser)
        #expect(!app.isOpening && app.mainWindowDismissed)
    }
}
