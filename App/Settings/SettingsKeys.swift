import Foundation

/// Shared with background preference readers; never depends on an actor-isolated view.
nonisolated enum SettingsKeys {
    static let appearance = "general.appearance"
    static let defaultView = "browse.defaultView"
    static let volumeSize = "PackVolumeSize"
    static let hoverPreviews = "browse.hoverPreviews"
    static let showPassword = "password.showByDefault"
    /// Opt-in Keychain vault for archive passwords (#76). Off by default.
    static let rememberPasswords = "password.rememberInKeychain"
    static let openInGlance = "glance.openFromFinder" // Legacy fixed-mode preference.
    static let archiveWindowMode = "browse.archiveWindowMode"
    static let lastArchiveWindow = "browse.lastArchiveWindow"

    enum ArchiveWindow: String, Sendable { case browser, glance }
    enum ArchiveWindowMode: String, CaseIterable, Identifiable, Sendable {
        case lastUsed, browser, glance
        var id: Self { self }
        var title: String {
            switch self {
            case .lastUsed: String(localized: "Last Used Window")
            case .browser: String(localized: "Full Browser")
            case .glance: String(localized: "Glance")
            }
        }
    }

    static func archiveWindowMode(in store: UserDefaults = .standard) -> ArchiveWindowMode {
        if let raw = store.string(forKey: archiveWindowMode), let mode = ArchiveWindowMode(rawValue: raw) { return mode }
        // Preserve an explicit old choice; new/default installs remember the last window.
        if store.object(forKey: openInGlance) != nil { return store.bool(forKey: openInGlance) ? .glance : .browser }
        return .lastUsed
    }

    static func archiveWindow(in store: UserDefaults = .standard) -> ArchiveWindow {
        switch archiveWindowMode(in: store) {
        case .browser: .browser
        case .glance: .glance
        case .lastUsed: store.string(forKey: lastArchiveWindow).flatMap(ArchiveWindow.init(rawValue:)) ?? .browser
        }
    }
    static let glancePinned = "glance.pinned"
    static let glanceColourfulControls = "glance.colourfulControls"
    /// Liquid Glass vs classic frosted Glance background (#158). Default preserves Liquid Glass.
    static let glanceMaterial = "glance.material"
    static let trayEnabled = "tray.enabled"
    static let trayMenuBarIcon = "tray.menuBarIcon"
    static let trayShowWhileDragging = "tray.showWhileDragging"
    static let trayBorder = "tray.border"
    static let trayPinned = "tray.pinned"
    static let nextStepsShown = "nextSteps.shown"
    static let nextStepsHidden = "nextSteps.hidden"
    /// Sparkle reads and writes these itself; Stow only resets them.
    static let updatesAutomaticallyCheck = "SUEnableAutomaticChecks"
    static let updatesAutomaticallyDownload = "SUAutomaticallyUpdate"

    enum Appearance: String, CaseIterable, Sendable { case system, light, dark }
    /// Glance window material preference (#158). Independent of colourful controls.
    enum GlanceMaterialPreference: String, CaseIterable, Sendable, Identifiable {
        case liquidGlass
        case classic
        var id: String { rawValue }
        var title: String {
            switch self {
            case .liquidGlass: String(localized: "Liquid Glass")
            case .classic: String(localized: "Classic frosted")
            }
        }
    }
    enum DefaultValue: Equatable, Sendable {
        case string(String), integer(Int64), bool(Bool)

    }
    struct Entry: Sendable {
        let key: String
        let defaultValue: DefaultValue
        func read(in store: UserDefaults) -> DefaultValue {
            guard store.object(forKey: key) != nil else { return defaultValue }
            switch defaultValue {
            case .string: return .string(store.string(forKey: key) ?? "")
            case .integer: return .integer(Int64(store.integer(forKey: key)))
            case .bool: return .bool(store.bool(forKey: key))
            }
        }
    }
    // PreviousDefaultApps is restoration state, not a preference. Keep the switch-back memory.
    // onboarding.completed is first-run state, not a preference. Keep completion remembered.
    // destination.severalFolders is the last folder chosen for a mix (GatherDestination), not a preference.
    static let resettable: [Entry] = [
        .init(key: Preferences.Key.extractAllFolder, defaultValue: .string(Preferences.defaults.extractAllFolder.rawValue)),
        .init(key: Preferences.Key.afterExtractAll, defaultValue: .string(Preferences.defaults.afterExtractAll.rawValue)),
        .init(key: Preferences.Key.afterInstall, defaultValue: .string(Preferences.defaults.afterInstall.rawValue)),
        .init(key: Preferences.Key.closeWindowAfter, defaultValue: .bool(Preferences.defaults.closeWindowAfter)),
        .init(key: Preferences.Key.folderConflict, defaultValue: .string(Preferences.defaults.folderConflict.rawValue)),
        .init(key: Preferences.Key.fileConflict, defaultValue: .string(Preferences.defaults.fileConflict.rawValue)),
        .init(key: Preferences.Key.skipSystemFiles, defaultValue: .bool(Preferences.defaults.skipSystemFiles)),
        .init(key: Preferences.Key.removeQuarantine, defaultValue: .bool(Preferences.defaults.removeQuarantine)),
        .init(key: "PackAudience", defaultValue: .string(Audience.windows.rawValue)),
        .init(key: "PackVerify", defaultValue: .bool(false)),
        .init(key: "PackCPUCores", defaultValue: .integer(0)),
        .init(key: "FinderMenuOnExternalDrives", defaultValue: .bool(false)),
        .init(key: appearance, defaultValue: .string("system")),
        .init(key: defaultView, defaultValue: .string("grid")),
        .init(key: volumeSize, defaultValue: .integer(0)),
        .init(key: hoverPreviews, defaultValue: .bool(true)),
        .init(key: showPassword, defaultValue: .bool(false)),
        .init(key: rememberPasswords, defaultValue: .bool(false)),
        .init(key: openInGlance, defaultValue: .bool(false)),
        .init(key: archiveWindowMode, defaultValue: .string(ArchiveWindowMode.lastUsed.rawValue)),
        .init(key: lastArchiveWindow, defaultValue: .string(ArchiveWindow.browser.rawValue)),
        .init(key: glancePinned, defaultValue: .bool(false)),
        .init(key: glanceColourfulControls, defaultValue: .bool(false)),
        .init(key: glanceMaterial, defaultValue: .string(GlanceMaterialPreference.liquidGlass.rawValue)),
        .init(key: trayEnabled, defaultValue: .bool(false)),
        .init(key: trayMenuBarIcon, defaultValue: .bool(true)),
        .init(key: trayShowWhileDragging, defaultValue: .bool(true)),
        .init(key: trayBorder, defaultValue: .string(TrayBorder.accent.rawValue)),
        .init(key: trayPinned, defaultValue: .bool(false)),
        .init(key: nextStepsShown, defaultValue: .bool(true)),
        .init(key: nextStepsHidden, defaultValue: .string(NextStepsSettings.encode(NextStepsSettings.defaultHidden))),
        // Sparkle's own keys (#35): resetting falls back to Info.plist (check daily, ask before installing).
        .init(key: updatesAutomaticallyCheck, defaultValue: .bool(true)),
        .init(key: updatesAutomaticallyDownload, defaultValue: .bool(false))
    ] + Audience.allCases.map {
        Entry(key: "PackLevel.\($0.rawValue)", defaultValue: .integer(Int64(CompressionLevel.balanced.rawValue)))
    }

    static func reset(in store: UserDefaults) {
        for entry in resettable { store.removeObject(forKey: entry.key) }
    }

    /// Preferences hosted on one Settings page (#162). Empty for pages that only show
    /// system state (File Types associations memory, Licenses) or tools (Advanced cache).
    /// Resetting a page never touches Keychain contents, folder grants, PreviousDefaultApps,
    /// onboarding completion, or GatherDestination memory.
    static func resettableEntries(for pane: SettingsPane) -> [Entry] {
        let keys: Set<String>
        switch pane {
        case .general:
            keys = [
                appearance, defaultView,
                updatesAutomaticallyCheck, updatesAutomaticallyDownload
            ]
        case .tray:
            keys = [trayEnabled, trayMenuBarIcon, trayShowWhileDragging, trayBorder, trayPinned]
        case .glance:
            // Pin on Top is set from Glance itself (and Window › Keep Glance on Top), not shown here,
            // but it is Glance's preference, so it resets with this page.
            keys = [openInGlance, archiveWindowMode, lastArchiveWindow, glancePinned, glanceColourfulControls, glanceMaterial]
        case .extraction:
            keys = [
                Preferences.Key.extractAllFolder, Preferences.Key.afterExtractAll,
                Preferences.Key.closeWindowAfter, Preferences.Key.folderConflict,
                Preferences.Key.fileConflict, Preferences.Key.skipSystemFiles
            ]
        case .installing:
            keys = [Preferences.Key.afterInstall, Preferences.Key.removeQuarantine]
        case .packing:
            keys = Set(["PackAudience", "PackVerify", volumeSize, "PackCPUCores"]
                       + Audience.allCases.map { "PackLevel.\($0.rawValue)" })
        case .nextSteps:
            keys = [nextStepsShown, nextStepsHidden]
        case .previews:
            keys = [hoverPreviews]
        case .passwords:
            keys = [showPassword, rememberPasswords]
        case .integration:
            keys = ["FinderMenuOnExternalDrives"]
        case .fileTypes, .advanced, .licenses:
            keys = []
        }
        return resettable.filter { keys.contains($0.key) }
    }

    /// Clears one page's preferences, or every resettable preference.
    enum ResetScope: Equatable, Sendable {
        case all
        case pane(SettingsPane)
    }

    static func reset(_ scope: ResetScope, in store: UserDefaults) {
        switch scope {
        case .all:
            reset(in: store)
        case .pane(let pane):
            for entry in resettableEntries(for: pane) { store.removeObject(forKey: entry.key) }
        }
    }
    static func defaultValue(for key: String) -> DefaultValue {
        resettable.first { $0.key == key }!.defaultValue
    }
    static func appearance(in store: UserDefaults = .standard) -> Appearance {
        Appearance(rawValue: store.string(forKey: appearance) ?? "") ?? .system
    }
    static func browserView(in store: UserDefaults = .standard) -> BrowserModel.ViewMode {
        BrowserModel.ViewMode(rawValue: store.string(forKey: defaultView) ?? "") ?? .grid
    }
    static func splitSize(in store: UserDefaults = .standard) -> SplitSize {
        guard let number = store.object(forKey: volumeSize) as? NSNumber else { return .none }
        let value = number.int64Value
        guard value > 0 else { return .none }
        return SplitSize.stored(value)
    }
    /// The marker is installation state, not a resettable preference. Reset must not remigrate.
    static func migrateTray(in store: UserDefaults, persistent: [String: Any]) {
        let marker = "tray.enablementMigrated"
        guard !store.bool(forKey: marker) else { return }
        if persistent[trayEnabled] == nil {
            let oldKeys = Set(resettable.map(\.key)).subtracting([trayEnabled])
                .union([Onboarding.completedKey, "recent.archives", "FolderGrants", "HideDockIconWithoutWindows"])
            let existing = persistent.keys.contains { oldKeys.contains($0) || $0.hasPrefix("tray.") }
            let icon = (persistent[trayMenuBarIcon] as? NSNumber)?.boolValue ?? true
            let drag = (persistent[trayShowWhileDragging] as? NSNumber)?.boolValue ?? true
            store.set(existing && (icon || drag), forKey: trayEnabled)
        }
        store.set(true, forKey: marker)
    }

    // Legacy tray.idleSeconds values are intentionally ignored. Keep Open is the only
    // persistence preference; an old timeout (including Never) never changes tray.pinned.
    static func trayBorder(in store: UserDefaults = .standard) -> TrayBorder {
        TrayBorder(rawValue: store.string(forKey: trayBorder) ?? "") ?? .accent
    }
    
    static func glanceMaterialPreference(in store: UserDefaults = .standard) -> GlanceMaterialPreference {
        GlanceMaterialPreference(rawValue: store.string(forKey: glanceMaterial) ?? "") ?? .liquidGlass
    }

    static func flag(_ key: String, in store: UserDefaults = .standard) -> Bool {
        if let number = store.object(forKey: key) as? NSNumber, number == 0 || number == 1 {
            return number.boolValue
        }
        if case .bool(let fallback) = defaultValue(for: key) { return fallback }
        return false
    }
}
