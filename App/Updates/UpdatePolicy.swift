import Foundation
import Security

/// When Stow may talk to its update feed (#35). Only a Developer ID–signed release build does:
/// tests, snapshot and demo scenes, Debug builds and ad-hoc builds never start Sparkle, so they
/// never touch the network and never show an update prompt.
nonisolated enum UpdatePolicy {
    /// The appcast attached to the latest *published* GitHub release (drafts and pre-releases are
    /// never "latest"). Mirrors `SUFeedURL` in project.yml.
    static let feedURL = "https://github.com/skyswordw/stow/releases/latest/download/appcast.xml"

    enum Unavailable: Equatable, Sendable {
        /// Sparkle hasn't been started yet (before launch finishes).
        case notStarted
        case testing
        case demoScene
        case debugBuild
        /// Ad-hoc or unsigned: an update signed by Stow's Developer ID couldn't replace it anyway.
        case notDeveloperIDSigned
        /// Info.plist lacks a usable feed or public key.
        case notConfigured
    }

    static func unavailable(
        info: [String: Any] = Bundle.main.infoDictionary ?? [:],
        isDebugBuild: Bool = UpdatePolicy.isDebugBuild,
        teamIdentifier: @autoclosure () -> String? = UpdatePolicy.currentTeamIdentifier(),
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        testCaseClassPresent: Bool = NSClassFromString("XCTestCase") != nil
    ) -> Unavailable? {
        if testCaseClassPresent || environment["XCTestConfigurationFilePath"] != nil { return .testing }
        if arguments.contains(where: { $0.hasPrefix("-Stow") }) { return .demoScene }
        if isDebugBuild { return .debugBuild }
        guard let team = teamIdentifier(), !team.isEmpty else { return .notDeveloperIDSigned }
        guard isConfigured(info) else { return .notConfigured }
        return nil
    }

    /// An https feed, a 32-byte EdDSA public key and the sandbox's installer service.
    static func isConfigured(_ info: [String: Any]) -> Bool {
        guard let feed = info["SUFeedURL"] as? String, let url = URL(string: feed), url.scheme == "https",
              url.host() != nil else { return false }
        guard let key = info["SUPublicEDKey"] as? String, Data(base64Encoded: key)?.count == 32 else { return false }
        return (info["SUEnableInstallerLauncherService"] as? Bool) == true
    }

    /// Info.plist's default for a Sparkle setting when no user choice is stored.
    static func defaultFlag(_ key: String, info: [String: Any] = Bundle.main.infoDictionary ?? [:],
                            fallback: Bool) -> Bool {
        (info[key] as? Bool) ?? fallback
    }

    static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    /// The Team ID Stow's own signature carries; `nil` when ad-hoc signed or unsigned.
    static func currentTeamIdentifier() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation),
                                            &information) == errSecSuccess,
              let dictionary = information as? [String: Any] else { return nil }
        return dictionary[kSecCodeInfoTeamIdentifier as String] as? String
    }
}
