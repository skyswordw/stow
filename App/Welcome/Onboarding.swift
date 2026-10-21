import Foundation

nonisolated enum Onboarding {
    // First-run state, not a preference. Resetting settings must keep completion remembered.
    static let completedKey = "onboarding.completed"

    static func shouldShowAutomatically(
        defaults: UserDefaults = .standard,
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        testCaseClassPresent: Bool = NSClassFromString("XCTestCase") != nil
    ) -> Bool {
        !defaults.bool(forKey: completedKey)
            && !arguments.contains("-StowScene")
            && environment["XCTestConfigurationFilePath"] == nil
            && !testCaseClassPresent
    }

    static func markCompleted(in defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: completedKey)
    }
}

nonisolated enum OnboardingStep: String, CaseIterable, Identifiable {
    case archives, fileTypes, finder, tray
    var id: Self { self }
    var title: String {
        switch self {
        case .archives: String(localized: "What Stow does")
        case .fileTypes: String(localized: "File Types")
        case .finder: String(localized: "Finder extension")
        case .tray: String(localized: "Tray")
        }
    }
    var detail: String {
        switch self {
        case .archives: String(localized: "Open, explore and share archives with confidence.")
        case .fileTypes: String(localized: "Choose which everyday archives open with Stow.")
        case .finder: String(localized: "Archive actions in Finder’s context menu.")
        case .tray: String(localized: "Collect files from anywhere, then pack them — ⌥⌘T.")
        }
    }
    var systemImage: String {
        switch self {
        case .archives: "shippingbox"
        case .fileTypes: "doc.on.doc"
        case .finder: "puzzlepiece.extension"
        case .tray: "tray"
        }
    }
}

/// Receives RootView's scene action, like SettingsRouter receives its Settings action.
final class OnboardingRouter {
    static let shared = OnboardingRouter()
    var open: () -> Void = {}
    var didCheckAutomaticPresentation = false
}
