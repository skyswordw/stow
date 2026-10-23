import Foundation
import Testing
@testable import Stow

@Suite("Settings")
struct SettingsTests {
    private func withStore(_ body: (UserDefaults) throws -> Void) throws {
        let name = "SettingsTests.\(UUID().uuidString)"
        let store = try #require(UserDefaults(suiteName: name))
        defer { store.removePersistentDomain(forName: name) }
        try body(store)
    }

    @Test func defaultsAndRegistry() throws {
        try withStore { store in
            let expected: Set<String> = [
                "extract.allFolder", "extract.afterExtractAll", "extract.closeWindowAfter",
                "extract.folderConflict", "extract.fileConflict", "extract.skipSystemFiles",
                "install.afterInstall", "install.removeQuarantine", "PackAudience", "PackVerify",
                "PackCPUCores", "FinderMenuOnExternalDrives", "HideDockIconWithoutWindows",
                "general.appearance", "browse.defaultView", "PackVolumeSize",
                "browse.hoverPreviews", "password.showByDefault", "password.rememberInKeychain",
                "glance.openFromFinder", "glance.pinned", "glance.colourfulControls",
                "tray.menuBarIcon", "tray.showWhileDragging", "tray.idleSeconds", "tray.border", "tray.pinned",
                "nextSteps.shown", "nextSteps.hidden", "SUEnableAutomaticChecks", "SUAutomaticallyUpdate",
                "PackLevel.windows", "PackLevel.mac", "PackLevel.linux", "PackLevel.web"
            ]
            let keys = SettingsKeys.resettable.map(\.key)
            #expect(Set(keys) == expected)
            #expect(keys.count == expected.count)
            for entry in SettingsKeys.resettable {
                #expect(entry.read(in: store) == entry.defaultValue)
                #expect(store.object(forKey: entry.key) == nil)
            }
            #expect(Preferences.values(in: store) == Preferences.defaults)
            #expect(SettingsKeys.appearance(in: store) == .system)
            #expect(SettingsKeys.browserView(in: store) == .grid)
            #expect(SettingsKeys.splitSize(in: store) == .none)
            #expect(SettingsKeys.flag(SettingsKeys.hoverPreviews, in: store))
            #expect(!SettingsKeys.flag(SettingsKeys.showPassword, in: store))
            #expect(!SettingsKeys.flag(SettingsKeys.rememberPasswords, in: store))
            #expect(!SettingsKeys.flag(SettingsKeys.glanceColourfulControls, in: store))
            #expect(SettingsKeys.flag(SettingsKeys.trayMenuBarIcon, in: store))
            #expect(SettingsKeys.flag(SettingsKeys.trayShowWhileDragging, in: store))
            #expect(!SettingsKeys.flag(SettingsKeys.trayPinned, in: store))
            #expect(SettingsKeys.trayIdleSeconds(in: store) == 30)
            #expect(SettingsKeys.trayBorder(in: store) == .accent)
        }
    }

    @Test func resetRemovesOnlyPreferences() throws {
        try withStore { store in
            for entry in SettingsKeys.resettable {
                switch entry.defaultValue {
                case .string: store.set("different", forKey: entry.key)
                case .integer: store.set(12345, forKey: entry.key)
                case .bool(let value): store.set(!value, forKey: entry.key)
                }
                #expect(entry.read(in: store) != entry.defaultValue)
            }
            store.set(["public.zip-archive": "previous.app"], forKey: "PreviousDefaultApps")
            store.set("keep", forKey: "Unrelated")
            SettingsKeys.reset(in: store)
            for entry in SettingsKeys.resettable {
                #expect(store.object(forKey: entry.key) == nil)
                #expect(entry.read(in: store) == entry.defaultValue)
            }
            #expect(store.dictionary(forKey: "PreviousDefaultApps") as? [String: String]
                    == ["public.zip-archive": "previous.app"])
            #expect(store.string(forKey: "Unrelated") == "keep")
        }
    }

    @Test func panesHaveDesignOrderAndUniqueLabels() {
        let panes = SettingsPane.allCases
        #expect(panes.map(\.rawValue) == ["general", "extraction", "installing", "packing", "nextSteps", "previews",
                                          "passwords", "fileTypes", "integration", "advanced", "licenses"])
        #expect(panes.allSatisfy { !$0.title.isEmpty && !$0.systemImage.isEmpty })
        #expect(Set(panes.map(\.title)).count == 11)
        #expect(Set(panes.map(\.systemImage)).count == 11)
    }

    @Test func invalidNewValuesFallBack() throws {
        try withStore { store in
            store.set("ultraviolet", forKey: SettingsKeys.appearance)
            store.set("coverflow", forKey: SettingsKeys.defaultView)
            store.set(-42, forKey: SettingsKeys.volumeSize)
            store.set("invalid", forKey: SettingsKeys.hoverPreviews)
            store.set(17, forKey: SettingsKeys.showPassword)
            store.set("invalid", forKey: SettingsKeys.glanceColourfulControls)
            #expect(SettingsKeys.appearance(in: store) == .system)
            #expect(SettingsKeys.browserView(in: store) == .grid)
            #expect(SettingsKeys.splitSize(in: store) == .none)
            #expect(SettingsKeys.flag(SettingsKeys.hoverPreviews, in: store))
            #expect(!SettingsKeys.flag(SettingsKeys.showPassword, in: store))
            #expect(!SettingsKeys.flag(SettingsKeys.glanceColourfulControls, in: store))
            store.set("not a size", forKey: SettingsKeys.volumeSize)
            #expect(SettingsKeys.splitSize(in: store) == .none)
            store.set("dark", forKey: SettingsKeys.appearance)
            store.set("columns", forKey: SettingsKeys.defaultView)
            store.set(SplitSize.mb700.rawValue, forKey: SettingsKeys.volumeSize)
            store.set(false, forKey: SettingsKeys.hoverPreviews)
            store.set(true, forKey: SettingsKeys.showPassword)
            store.set(true, forKey: SettingsKeys.glanceColourfulControls)
            #expect(SettingsKeys.appearance(in: store) == .dark)
            #expect(SettingsKeys.browserView(in: store) == .columns)
            #expect(SettingsKeys.splitSize(in: store) == .mb700)
            #expect(!SettingsKeys.flag(SettingsKeys.hoverPreviews, in: store))
            #expect(SettingsKeys.flag(SettingsKeys.showPassword, in: store))
            #expect(SettingsKeys.flag(SettingsKeys.glanceColourfulControls, in: store))
        }
    }
}
