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
        refresh()
    }

    func reloadPreferences() {
        isReloadingPreferences = true
        defer { isReloadingPreferences = false }
        showsOnExternalDrives = defaults.bool(forKey: Keys.externalDrives)
    }

    private enum Keys {
        static let externalDrives = "FinderMenuOnExternalDrives"
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
        case .enabled: String(localized: "Stow opens quietly at login when Tray is enabled.")
        case .requiresApproval: String(localized: "macOS needs your OK in Login Items settings.")
        case .notFound: String(localized: "macOS can’t find this copy of Stow. Move it to Applications and try again.")
        default: String(localized: "Stow opens when you use it.")
        }
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func refresh() {
        finderExtensionEnabled = FIFinderSyncController.isExtensionEnabled
        loginItemStatus = SMAppService.mainApp.status
    }
}
