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
                "glance.openFromFinder", "glance.pinned", "glance.colourfulControls", "glance.material",
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
        #expect(panes.map(\.rawValue) == ["general", "extraction", "installing", "packing", "nextSteps", "glance",
                                          "previews", "passwords", "fileTypes", "integration", "advanced", "licenses"])
        #expect(panes.allSatisfy { !$0.title.isEmpty && !$0.systemImage.isEmpty })
        #expect(Set(panes.map(\.title)).count == 12)
        #expect(Set(panes.map(\.systemImage)).count == 12)
        #expect(SettingsPane.nextSteps.title == String(localized: "Actions"))
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
            store.set(SplitSize.mb500.rawValue, forKey: SettingsKeys.volumeSize)
            #expect(SettingsKeys.splitSize(in: store) == .mb500)
            store.set(250_000_000, forKey: SettingsKeys.volumeSize)
            let custom = SettingsKeys.splitSize(in: store)
            #expect(custom.isCustom)
            #expect(custom.rawValue == 250_000_000)
            #expect(!SettingsKeys.flag(SettingsKeys.hoverPreviews, in: store))
            #expect(SettingsKeys.flag(SettingsKeys.showPassword, in: store))
            #expect(SettingsKeys.flag(SettingsKeys.glanceColourfulControls, in: store))
        }
    }

    @Test func categoriesGroupEveryPaneExactlyOnce() {
        let grouped = SettingsCategory.allCases.flatMap(\.panes)
        #expect(grouped == SettingsPane.allCases)
        #expect(Set(grouped).count == SettingsPane.allCases.count)
        for pane in SettingsPane.allCases {
            #expect(pane.category.panes.contains(pane))
            #expect(SettingsCategory.allCases.filter { $0.panes.contains(pane) }.count == 1)
        }
        #expect(SettingsCategory.allCases.map(\.rawValue) == [
            "general", "archiveWork", "interaction", "security", "systemIntegration", "advanced"
        ])
        #expect(SettingsCategory.archiveWork.panes == [.extraction, .installing, .packing])
        #expect(SettingsCategory.interaction.panes == [.nextSteps, .glance, .previews])
        #expect(SettingsCategory.systemIntegration.panes == [.fileTypes, .integration])
        #expect(SettingsCategory.advanced.panes == [.advanced, .licenses])
        #expect(SettingsCategory.allCases.allSatisfy { !$0.title.isEmpty && !$0.systemImage.isEmpty })
        #expect(Set(SettingsCategory.allCases.map(\.title)).count == SettingsCategory.allCases.count)
    }

    @Test func everyResettableKeyBelongsToExactlyOnePage() {
        let mapped = SettingsPane.allCases.flatMap { SettingsKeys.resettableEntries(for: $0).map(\.key) }
        #expect(Set(mapped) == Set(SettingsKeys.resettable.map(\.key)))
        #expect(mapped.count == SettingsKeys.resettable.count)
        #expect(SettingsKeys.resettableEntries(for: .fileTypes).isEmpty)
        #expect(SettingsKeys.resettableEntries(for: .advanced).isEmpty)
        #expect(SettingsKeys.resettableEntries(for: .licenses).isEmpty)
        #expect(SettingsKeys.resettableEntries(for: .nextSteps).map(\.key)
                == [SettingsKeys.nextStepsShown, SettingsKeys.nextStepsHidden])
    }

    /// Glance's choices moved from General to their own page (#162): each reset follows its controls.
    @Test func glancePageResetLeavesGeneral() throws {
        let glanceKeys: Set<String> = [SettingsKeys.openInGlance, SettingsKeys.glancePinned,
                                       SettingsKeys.glanceColourfulControls, SettingsKeys.glanceMaterial]
        #expect(Set(SettingsKeys.resettableEntries(for: .glance).map(\.key)) == glanceKeys)
        #expect(glanceKeys.isDisjoint(with: SettingsKeys.resettableEntries(for: .general).map(\.key)))
        try withStore { store in
            store.set(true, forKey: SettingsKeys.openInGlance)
            store.set(true, forKey: SettingsKeys.glanceColourfulControls)
            store.set(SettingsKeys.GlanceMaterialPreference.classic.rawValue, forKey: SettingsKeys.glanceMaterial)
            store.set("dark", forKey: SettingsKeys.appearance)

            SettingsKeys.reset(.pane(.general), in: store)
            #expect(SettingsKeys.flag(SettingsKeys.openInGlance, in: store))
            #expect(SettingsKeys.glanceMaterialPreference(in: store) == .classic)
            #expect(SettingsKeys.appearance(in: store) == .system)

            store.set("dark", forKey: SettingsKeys.appearance)
            SettingsKeys.reset(.pane(.glance), in: store)
            for key in glanceKeys { #expect(store.object(forKey: key) == nil) }
            #expect(!SettingsKeys.flag(SettingsKeys.openInGlance, in: store))
            #expect(!SettingsKeys.flag(SettingsKeys.glanceColourfulControls, in: store))
            #expect(SettingsKeys.glanceMaterialPreference(in: store) == .liquidGlass)
            #expect(SettingsKeys.appearance(in: store) == .dark)
        }
    }

    @Test func pageResetLeavesOtherPagesAndNonPreferences() throws {
        try withStore { store in
            store.set("dark", forKey: SettingsKeys.appearance)
            store.set(false, forKey: SettingsKeys.hoverPreviews)
            store.set(true, forKey: SettingsKeys.showPassword)
            store.set("zip", forKey: Preferences.Key.extractAllFolder)
            store.set(["public.zip-archive": "previous.app"], forKey: "PreviousDefaultApps")
            store.set("keep", forKey: "Unrelated")
            store.set(true, forKey: "onboarding.completed")

            SettingsKeys.reset(.pane(.general), in: store)
            #expect(store.object(forKey: SettingsKeys.appearance) == nil)
            #expect(SettingsKeys.appearance(in: store) == .system)
            #expect(store.object(forKey: SettingsKeys.hoverPreviews) as? Bool == false)
            #expect(store.bool(forKey: SettingsKeys.showPassword))
            #expect(store.string(forKey: Preferences.Key.extractAllFolder) == "zip")
            #expect(store.dictionary(forKey: "PreviousDefaultApps") as? [String: String]
                    == ["public.zip-archive": "previous.app"])
            #expect(store.string(forKey: "Unrelated") == "keep")
            #expect(store.bool(forKey: "onboarding.completed"))

            SettingsKeys.reset(.pane(.previews), in: store)
            #expect(store.object(forKey: SettingsKeys.hoverPreviews) == nil)
            #expect(SettingsKeys.flag(SettingsKeys.hoverPreviews, in: store))
            #expect(store.bool(forKey: SettingsKeys.showPassword))

            SettingsKeys.reset(.pane(.passwords), in: store)
            #expect(store.object(forKey: SettingsKeys.showPassword) == nil)
            #expect(!SettingsKeys.flag(SettingsKeys.showPassword, in: store))

            store.set("always", forKey: Preferences.Key.extractAllFolder)
            store.set(true, forKey: SettingsKeys.rememberPasswords)
            SettingsKeys.reset(.all, in: store)
            #expect(store.object(forKey: Preferences.Key.extractAllFolder) == nil)
            #expect(store.object(forKey: SettingsKeys.rememberPasswords) == nil)
            #expect(store.dictionary(forKey: "PreviousDefaultApps") as? [String: String]
                    == ["public.zip-archive": "previous.app"])
            #expect(store.string(forKey: "Unrelated") == "keep")
        }
    }

    @Test func packingResetRestoresDefaultsWithoutResettingGeneral() throws {
        try withStore { store in
            let entries = SettingsKeys.resettableEntries(for: .packing)
            #expect(Set(entries.map(\.key)) == Set([
                "PackAudience", "PackVerify", "PackCPUCores", SettingsKeys.volumeSize,
                "PackLevel.windows", "PackLevel.mac", "PackLevel.linux", "PackLevel.web"
            ]))
            store.set("mac", forKey: "PackAudience")
            store.set(true, forKey: "PackVerify")
            store.set(2, forKey: "PackCPUCores")
            store.set(123456, forKey: SettingsKeys.volumeSize)
            for audience in Audience.allCases {
                store.set(-1, forKey: "PackLevel.\(audience.rawValue)")
            }
            SettingsKeys.reset(.pane(.general), in: store)
            for entry in entries {
                #expect(entry.read(in: store) != entry.defaultValue)
            }
            store.set("dark", forKey: SettingsKeys.appearance)
            store.set(false, forKey: SettingsKeys.nextStepsShown)

            SettingsKeys.reset(.pane(.packing), in: store)

            for entry in entries {
                #expect(store.object(forKey: entry.key) == nil)
                #expect(entry.read(in: store) == SettingsKeys.defaultValue(for: entry.key))
            }
            #expect(SettingsKeys.splitSize(in: store) == .none)
            #expect(!SettingsKeys.flag("PackVerify", in: store))
            #expect(SettingsKeys.appearance(in: store) == .dark)
            #expect(store.object(forKey: SettingsKeys.nextStepsShown) as? Bool == false)
        }
    }

    @Test func actionsPageResetRestoresSuggestionVisibility() throws {
        try withStore { store in
            let customized = NextStepsSettings(isShown: false, hidden: Set(NextStep.Kind.allCases))
            customized.save(to: store)
            store.set(true, forKey: "PackVerify")
            #expect(NextStepsSettings.load(from: store) == customized)

            SettingsKeys.reset(.pane(.nextSteps), in: store)

            for entry in SettingsKeys.resettableEntries(for: .nextSteps) {
                #expect(store.object(forKey: entry.key) == nil)
                #expect(entry.read(in: store) == entry.defaultValue)
            }
            let restored = NextStepsSettings.load(from: store)
            #expect(restored == .defaults)
            #expect(restored.isShown)
            for kind in NextStep.Kind.allCases {
                #expect(restored.shows(kind) == (kind != .pack))
            }
            #expect(store.bool(forKey: "PackVerify"))
            customized.save(to: store)
            NextStepsSettings.restoreDefaults(in: store)
            #expect(NextStepsSettings.load(from: store) == restored)
            #expect(store.bool(forKey: "PackVerify"))
        }
    }

    @Test func allResetScopesPreserveRestorationAndFolderState() throws {
        try withStore { store in
            let preserved: [String: Any] = [
                "PreviousDefaultApps": ["public.zip-archive": "previous.app"],
                "onboarding.completed": true,
                "Unrelated": "keep",
                "FolderGrants": [Data([1, 2, 3])],
                "install.folderBookmarks": ["/Applications": Data([4, 5, 6])],
                GatherDestination.key: "/tmp/Keep",
                "recent.archives": Data([7, 8, 9])
            ]
            for (key, value) in preserved { store.set(value, forKey: key) }
            let scopes: [SettingsKeys.ResetScope] = [.all] + SettingsPane.allCases.map { .pane($0) }
            for scope in scopes {
                SettingsKeys.reset(scope, in: store)
                for (key, value) in preserved {
                    #expect(!SettingsKeys.resettable.contains { $0.key == key })
                    #expect((store.object(forKey: key) as? NSObject)?.isEqual(value) == true)
                }
            }
        }
    }

    @MainActor @Test func demoPaneRawValuesRouteAndFallBackToGeneral() throws {
        try withStore { store in
            let router = SettingsRouter()
            var opened = 0
            router.open = { opened += 1 }
            for pane in SettingsPane.allCases {
                store.set(pane.rawValue, forKey: "StowSettingsPane")
                router.show(rawValue: store.string(forKey: "StowSettingsPane"))
                #expect(router.pane == pane)
                #expect(router.category == pane.category)
            }
            for invalid in ["", "Actions", "Next Steps", "unknown"] {
                router.show(.packing)
                router.show(rawValue: invalid)
                #expect(router.pane == .general)
                #expect(router.category == .general)
            }
            router.show(.nextSteps)
            store.removeObject(forKey: "StowSettingsPane")
            router.show(rawValue: store.string(forKey: "StowSettingsPane"))
            #expect(router.pane == .general)
            #expect(router.category == .general)
            #expect(opened == SettingsPane.allCases.count + 10)
        }
    }

    @MainActor @Test func routerShowUpdatesPaneWithoutLosingOpenHook() {
        let router = SettingsRouter()
        var opened = 0
        var openedPane: SettingsPane?
        var openedCategory: SettingsCategory?
        router.open = {
            opened += 1
            openedPane = router.pane
            openedCategory = router.category
        }
        let routes: [(SettingsPane, SettingsCategory)] = [
            (.nextSteps, .interaction), (.glance, .interaction), (.fileTypes, .systemIntegration),
            (.integration, .systemIntegration), (.packing, .archiveWork), (.general, .general)
        ]
        for (pane, category) in routes {
            router.show(pane)
            #expect(router.pane == pane)
            #expect(router.category == category)
            #expect(openedPane == pane)
            #expect(openedCategory == category)
        }
        router.show(.general)
        #expect(opened == routes.count + 1)
        router.open = {}
    }

}
