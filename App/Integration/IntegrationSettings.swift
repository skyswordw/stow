import AppKit
import FinderSync
import ServiceManagement

/// Stow's place in macOS: login item, Dock icon, Finder menu. Hosted by Settings › Integration
/// (IntegrationView); everything reports the state macOS actually ends up in.
@Observable
final class IntegrationSettings {
    static let shared = IntegrationSettings()

    private let defaults: UserDefaults
    private var isReloadingPreferences = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showsOnExternalDrives = defaults.bool(forKey: Keys.externalDrives)
        hidesDockIconWithoutWindows = defaults.bool(forKey: Keys.hideDock)
        refresh()
    }

    func reloadPreferences() {
        isReloadingPreferences = true
        defer { isReloadingPreferences = false }
        showsOnExternalDrives = defaults.bool(forKey: Keys.externalDrives)
        hidesDockIconWithoutWindows = defaults.bool(forKey: Keys.hideDock)
    }

    private enum Keys {
        static let externalDrives = "FinderMenuOnExternalDrives"
        static let hideDock = "HideDockIconWithoutWindows"
    }

    // MARK: - Finder

    var showsOnExternalDrives: Bool {
        didSet {
            if !isReloadingPreferences { defaults.set(showsOnExternalDrives, forKey: Keys.externalDrives) }
            publishFinderSettings()
        }
    }

    private(set) var finderExtensionEnabled = false
    private(set) var repairSteps: [RepairStep] = []
    private(set) var isRepairing = false

    struct RepairStep: Identifiable, Equatable {
        enum Outcome: Equatable { case done, failed, todo }
        let id = UUID()
        let outcome: Outcome
        let text: String
    }

    /// The extension reads these at menu time (see FinderMenuSettings).
    func publishFinderSettings() {
        FinderMenuSettings(showsOnExternalDrives: showsOnExternalDrives).publish()
    }

    /// Registers Stow and its extensions with macOS again, opens the switch for the Finder
    /// extension when it's off, and says what's left for people to do. (`pluginkit` and
    /// restarting Finder aren't reachable from the sandbox, so those become instructions.)
    func repairFinderExtension() async {
        isRepairing = true
        defer { isRepairing = false }
        var steps: [RepairStep] = []

        if LSRegisterURL(Bundle.main.bundleURL as CFURL, true) == noErr {
            steps.append(RepairStep(outcome: .done, text: String(localized: "Registered Stow and its extensions with macOS again.")))
        } else {
            steps.append(RepairStep(outcome: .todo, text: String(localized: "Quit Stow and open it again from Applications — macOS registers its extensions when it starts.")))
        }

        refresh()
        if finderExtensionEnabled {
            steps.append(RepairStep(outcome: .done, text: String(localized: "The Finder extension is on.")))
        } else {
            FIFinderSyncController.showExtensionManagementInterface()
            steps.append(RepairStep(outcome: .todo, text: String(localized: "Turn on Stow in the settings window that just opened.")))
        }
        steps.append(RepairStep(outcome: .todo, text: String(localized: "Finder picks up changes when it restarts. To restart it now, hold Option, Control-click Finder in the Dock and choose Relaunch.")))
        publishFinderSettings()
        repairSteps = steps
    }

    func showExtensionSettings() {
        FIFinderSyncController.showExtensionManagementInterface()
    }

    // MARK: - Login item

    private(set) var loginItemStatus: SMAppService.Status = .notRegistered
    private(set) var loginItemError: String?

    var launchesAtLogin: Bool { loginItemStatus == .enabled || loginItemStatus == .requiresApproval }

    func setLaunchesAtLogin(_ on: Bool) {
        loginItemError = nil
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginItemError = error.localizedDescription
        }
        refresh()
    }

    var loginItemSummary: String {
        if let loginItemError { return loginItemError }
        return switch loginItemStatus {
        case .enabled: String(localized: "Stow opens quietly when you log in, so Finder actions start instantly.")
        case .requiresApproval: String(localized: "macOS needs your OK in Login Items settings.")
        case .notFound: String(localized: "macOS can’t find this copy of Stow. Move it to Applications and try again.")
        default: String(localized: "Stow opens when you use it.")
        }
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    // MARK: - Dock

    var hidesDockIconWithoutWindows: Bool {
        didSet {
            if !isReloadingPreferences { defaults.set(hidesDockIconWithoutWindows, forKey: Keys.hideDock) }
            DockPolicy.shared.update()
        }
    }

    func refresh() {
        finderExtensionEnabled = FIFinderSyncController.isExtensionEnabled
        loginItemStatus = SMAppService.mainApp.status
    }
}

/// Hides the Dock icon once the last window closes (when people ask for that) and brings it back
/// with the next window. Stow keeps running either way, so Finder actions don't pay for a launch.
final class DockPolicy {
    static let shared = DockPolicy()
    private var observers: [NSObjectProtocol] = []

    func install() {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
                let closing = note.object as? NSWindow
                MainActor.assumeIsolated { DockPolicy.shared.update(closing: closing) }
            },
            center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { DockPolicy.shared.update() }
            },
        ]
        update()
    }

    func update(closing: NSWindow? = nil) {
        let windows = NSApp.windows.filter { $0 !== closing && Self.counts($0) }.count
        let policy: NSApplication.ActivationPolicy = Self.shouldHide(
            setting: IntegrationSettings.shared.hidesDockIconWithoutWindows, openWindows: windows) ? .accessory : .regular
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
    }

    static func shouldHide(setting: Bool, openWindows: Int) -> Bool {
        setting && openWindows == 0
    }

    /// Real windows: not the Tray panel, alerts or sheets.
    private static func counts(_ window: NSWindow) -> Bool {
        window.isVisible && !(window is NSPanel) && window.sheetParent == nil && window.canBecomeMain
    }
}
