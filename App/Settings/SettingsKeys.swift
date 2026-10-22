import Foundation

/// Shared with background preference readers; never depends on an actor-isolated view.
nonisolated enum SettingsKeys {
    static let appearance = "general.appearance"
    static let defaultView = "browse.defaultView"
    static let volumeSize = "PackVolumeSize"
    static let hoverPreviews = "browse.hoverPreviews"
    static let showPassword = "password.showByDefault"
    static let openInGlance = "glance.openFromFinder"
    static let glancePinned = "glance.pinned"
    static let trayMenuBarIcon = "tray.menuBarIcon"
    static let trayShowWhileDragging = "tray.showWhileDragging"
    static let trayIdleSeconds = "tray.idleSeconds"
    static let trayBorder = "tray.border"
    static let trayPinned = "tray.pinned"
    static let nextStepsShown = "nextSteps.shown"
    static let nextStepsHidden = "nextSteps.hidden"
    /// Sparkle reads and writes these itself; Stow only resets them.
    static let updatesAutomaticallyCheck = "SUEnableAutomaticChecks"
    static let updatesAutomaticallyDownload = "SUAutomaticallyUpdate"

    enum Appearance: String, CaseIterable, Sendable { case system, light, dark }
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
        .init(key: "HideDockIconWithoutWindows", defaultValue: .bool(false)),
        .init(key: appearance, defaultValue: .string("system")),
        .init(key: defaultView, defaultValue: .string("grid")),
        .init(key: volumeSize, defaultValue: .integer(0)),
        .init(key: hoverPreviews, defaultValue: .bool(true)),
        .init(key: showPassword, defaultValue: .bool(false)),
        .init(key: openInGlance, defaultValue: .bool(false)),
        .init(key: glancePinned, defaultValue: .bool(false)),
        .init(key: trayMenuBarIcon, defaultValue: .bool(true)),
        .init(key: trayShowWhileDragging, defaultValue: .bool(true)),
        .init(key: trayIdleSeconds, defaultValue: .integer(30)),
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
        return SplitSize(rawValue: number.int64Value) ?? .none
    }
    static func trayIdleSeconds(in store: UserDefaults = .standard) -> Int {
        guard let number = store.object(forKey: trayIdleSeconds) as? NSNumber,
              TrayRules.idleChoices.contains(number.intValue) else { return 30 }
        return number.intValue
    }
    static func trayBorder(in store: UserDefaults = .standard) -> TrayBorder {
        TrayBorder(rawValue: store.string(forKey: trayBorder) ?? "") ?? .accent
    }
    static func flag(_ key: String, in store: UserDefaults = .standard) -> Bool {
        if let number = store.object(forKey: key) as? NSNumber, number == 0 || number == 1 {
            return number.boolValue
        }
        if case .bool(let fallback) = defaultValue(for: key) { return fallback }
        return false
    }
}
