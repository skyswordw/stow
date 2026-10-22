import Foundation
import Testing
@testable import Stow

/// Sparkle updates (#35): what Info.plist configures, which builds may check, and the install
/// gate that waits for running tasks.
@Suite("Updates")
struct UpdateTests {
    private static let validInfo: [String: Any] = [
        "SUFeedURL": UpdatePolicy.feedURL,
        "SUPublicEDKey": Data(repeating: 7, count: 32).base64EncodedString(),
        "SUEnableInstallerLauncherService": true
    ]

    private func reason(info: [String: Any] = UpdateTests.validInfo, debug: Bool = false, team: String? = "YNQ2233752",
                        arguments: [String] = ["Stow"], environment: [String: String] = [:],
                        testing: Bool = false) -> UpdatePolicy.Unavailable? {
        UpdatePolicy.unavailable(info: info, isDebugBuild: debug, teamIdentifier: team, arguments: arguments,
                                 environment: environment, testCaseClassPresent: testing)
    }

    @Test func infoPlistConfiguresSparkle() throws {
        let info = try #require(Bundle.main.infoDictionary)
        #expect(info["SUFeedURL"] as? String == UpdatePolicy.feedURL)
        let key = try #require(info["SUPublicEDKey"] as? String)
        #expect(Data(base64Encoded: key)?.count == 32)
        // Sandboxed: the installer runs outside the sandbox; the downloader keeps Stow off the network.
        #expect(info["SUEnableInstallerLauncherService"] as? Bool == true)
        #expect(info["SUEnableDownloaderService"] as? Bool == true)
        #expect(info["SUEnableAutomaticChecks"] as? Bool == true)
        #expect(info["SUEnableSystemProfiling"] as? Bool == false)
        #expect(UpdatePolicy.isConfigured(info))
        // Updates compare CFBundleVersion: it must be a plain number the release workflow raises.
        let build = try #require(info["CFBundleVersion"] as? String)
        #expect(!build.isEmpty && build.allSatisfy { $0.isNumber || $0 == "." })
    }

    @Test func feedIsTheLatestPublishedRelease() throws {
        let url = try #require(URL(string: UpdatePolicy.feedURL))
        #expect(url.scheme == "https")
        #expect(url.host() == "github.com")
        // `latest` never resolves to a draft or a pre-release, so nothing reaches people unpublished.
        #expect(url.path() == "/skyswordw/stow/releases/latest/download/appcast.xml")
    }

    @Test func onlySignedReleaseBuildsCheck() {
        #expect(reason() == nil)
        #expect(reason(debug: true) == .debugBuild)
        #expect(reason(team: nil) == .notDeveloperIDSigned)
        #expect(reason(team: "") == .notDeveloperIDSigned)
    }

    @Test func testsAndDemoScenesNeverCheck() {
        #expect(reason(testing: true) == .testing)
        #expect(reason(environment: ["XCTestConfigurationFilePath": "/tmp/x.xctestconfiguration"]) == .testing)
        #expect(reason(arguments: ["Stow", "-StowScene", "grid", "-StowSnapshot", "YES"]) == .demoScene)
        #expect(reason(arguments: ["Stow", "-StowSettingsPane", "general"]) == .demoScene)
        // Tests win over everything else, even a fully signed release.
        #expect(reason(debug: true, team: nil, arguments: ["Stow", "-StowScene", "x"], testing: true) == .testing)
    }

    @Test func incompleteConfigurationNeverChecks() {
        var info = Self.validInfo
        info["SUFeedURL"] = "http://github.com/skyswordw/stow/releases/latest/download/appcast.xml"
        #expect(reason(info: info) == .notConfigured)
        info = Self.validInfo
        info["SUPublicEDKey"] = Data(repeating: 1, count: 16).base64EncodedString()
        #expect(reason(info: info) == .notConfigured)
        info = Self.validInfo
        info["SUPublicEDKey"] = nil
        #expect(reason(info: info) == .notConfigured)
        info = Self.validInfo
        info["SUEnableInstallerLauncherService"] = false
        #expect(reason(info: info) == .notConfigured)
    }

    @MainActor @Test func thisTestRunNeverStartsSparkle() {
        #expect(UpdatePolicy.unavailable() == .testing)
        #expect(!AppUpdater.shared.isAvailable)
        AppUpdater.shared.checkForUpdates() // a no-op without an updater
        #expect(!AppUpdater.shared.isAvailable)
    }

    @Test func resetFallsBackToInfoPlistDefaults() {
        let info = Bundle.main.infoDictionary ?? [:]
        #expect(SettingsKeys.defaultValue(for: SettingsKeys.updatesAutomaticallyCheck)
                == .bool(UpdatePolicy.defaultFlag(SettingsKeys.updatesAutomaticallyCheck, info: info, fallback: false)))
        #expect(SettingsKeys.defaultValue(for: SettingsKeys.updatesAutomaticallyDownload) == .bool(false))
        #expect(UpdatePolicy.defaultFlag("SUMissing", info: [:], fallback: true))
        #expect(!UpdatePolicy.defaultFlag("SUMissing", info: ["SUMissing": false], fallback: true))
    }

    @MainActor @Test func installWaitsForRunningTasks() {
        let gate = UpdateInstallGate()
        var busy = false
        var installs = 0
        gate.isBusy = { busy }
        gate.pollInterval = .seconds(60)
        #expect(!gate.postpone { installs += 1 }) // idle: Sparkle relaunches right away
        #expect(gate.pending == nil && installs == 0)

        busy = true
        #expect(gate.postpone { installs += 1 })
        #expect(!gate.resumeIfIdle())
        #expect(installs == 0 && gate.pending != nil)

        busy = false
        #expect(gate.resumeIfIdle())
        #expect(installs == 1 && gate.pending == nil)
        #expect(gate.resumeIfIdle())
        #expect(installs == 1)
    }

    @MainActor @Test func heldInstallResumesByItself() async {
        let gate = UpdateInstallGate()
        var busy = true
        var installs = 0
        gate.isBusy = { busy }
        gate.pollInterval = .milliseconds(10)
        #expect(gate.postpone { installs += 1 })
        try? await Task.sleep(for: .milliseconds(50))
        #expect(installs == 0)
        busy = false
        for _ in 0 ..< 200 where installs == 0 { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(installs == 1 && gate.pending == nil)
    }
}
