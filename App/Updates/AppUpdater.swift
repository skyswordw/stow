import AppKit
import OSLog
internal import Sparkle

/// Stow's one Sparkle updater (#35). Created only when `UpdatePolicy` allows it — a Developer ID
/// release build outside tests and demo scenes — so every other build stays offline.
/// Settings and the app menu read it; Sparkle keeps the choices in user defaults
/// (`SUEnableAutomaticChecks`, `SUAutomaticallyUpdate`), with Info.plist as the default.
@Observable
final class AppUpdater: NSObject {
    static let shared = AppUpdater()

    private(set) var unavailable: UpdatePolicy.Unavailable? = .notStarted
    private(set) var automaticallyChecks = UpdatePolicy.defaultFlag(SettingsKeys.updatesAutomaticallyCheck, fallback: true)
    private(set) var automaticallyDownloads = false

    var isAvailable: Bool { unavailable == nil }

    let installGate = UpdateInstallGate()
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    private static let log = Logger(subsystem: "app.stow.Stow", category: "updates")

    /// Called once launching finishes. `isBusy` reports running extraction, packing or opening.
    func start(isBusy: @escaping () -> Bool) {
        installGate.isBusy = isBusy
        guard controller == nil else { return }
        if let reason = UpdatePolicy.unavailable() {
            unavailable = reason
            Self.log.info("Updates are off in this build: \(String(describing: reason), privacy: .public)")
            reload()
            return
        }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
        unavailable = nil
        reload()
    }

    /// App menu › Check for Updates…
    func checkForUpdates() {
        guard let controller, controller.updater.canCheckForUpdates else { return }
        controller.checkForUpdates(nil)
    }

    func setAutomaticallyChecks(_ value: Bool) {
        controller?.updater.automaticallyChecksForUpdates = value
        reload()
    }

    func setAutomaticallyDownloads(_ value: Bool) {
        controller?.updater.automaticallyDownloadsUpdates = value
        reload()
    }

    /// Re-reads the settings (after Reset All Preferences, which clears Sparkle's keys too).
    func reload() {
        if let updater = controller?.updater {
            automaticallyChecks = updater.automaticallyChecksForUpdates
            automaticallyDownloads = updater.automaticallyDownloadsUpdates
        } else {
            let defaults = UserDefaults.standard
            automaticallyChecks = (defaults.object(forKey: SettingsKeys.updatesAutomaticallyCheck) as? Bool)
                ?? UpdatePolicy.defaultFlag(SettingsKeys.updatesAutomaticallyCheck, fallback: true)
            automaticallyDownloads = automaticallyChecks
                && ((defaults.object(forKey: SettingsKeys.updatesAutomaticallyDownload) as? Bool) ?? false)
        }
    }
}

extension AppUpdater: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        installGate.postpone(installHandler)
    }
}

extension AppUpdater: SPUStandardUserDriverDelegate {
    /// Stow keeps running without windows (and can hide its Dock icon), so scheduled update
    /// alerts appear without stealing focus.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }
}
