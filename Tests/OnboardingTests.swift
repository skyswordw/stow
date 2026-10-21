import Foundation
import Testing
@testable import Stow

@Suite("Onboarding")
struct OnboardingTests {
    private func withStore(_ body: (UserDefaults) throws -> Void) throws {
        let name = "OnboardingTests.\(UUID().uuidString)"
        let store = try #require(UserDefaults(suiteName: name))
        defer { store.removePersistentDomain(forName: name) }
        try body(store)
    }

    @Test func showsOnFirstLaunch() throws {
        try withStore { store in
            #expect(Onboarding.shouldShowAutomatically(defaults: store, arguments: ["Stow"],
                                                       environment: [:], testCaseClassPresent: false))
        }
    }

    @Test func notAfterCompletion() throws {
        try withStore { store in
            Onboarding.markCompleted(in: store)
            #expect(store.bool(forKey: "onboarding.completed"))
            #expect(!Onboarding.shouldShowAutomatically(defaults: store, arguments: ["Stow"],
                                                        environment: [:], testCaseClassPresent: false))
        }
    }

    @Test func notInDemoScenes() throws {
        try withStore { store in
            for scene in ["grid", "onboarding"] {
                #expect(!Onboarding.shouldShowAutomatically(defaults: store, arguments: ["Stow", "-StowScene", scene],
                                                            environment: [:], testCaseClassPresent: false))
            }
        }
    }

    @Test func notInTestHosts() throws {
        try withStore { store in
            #expect(!Onboarding.shouldShowAutomatically(defaults: store, arguments: ["Stow"],
                environment: ["XCTestConfigurationFilePath": "/tmp/tests.xctestconfiguration"], testCaseClassPresent: false))
            #expect(!Onboarding.shouldShowAutomatically(defaults: store, arguments: ["Stow"],
                                                        environment: [:], testCaseClassPresent: true))
        }
    }

    @Test func resetPreservesCompletion() throws {
        try withStore { store in
            #expect(!SettingsKeys.resettable.contains { $0.key == "onboarding.completed" })
            Onboarding.markCompleted(in: store)
            store.set("dark", forKey: SettingsKeys.appearance)
            SettingsKeys.reset(in: store)
            #expect(store.object(forKey: SettingsKeys.appearance) == nil)
            #expect(store.bool(forKey: "onboarding.completed"))
        }
    }

    @Test func checklistOrderAndLabels() {
        #expect(OnboardingStep.allCases.map(\.rawValue) == ["archives", "fileTypes", "finder", "tray"])
        #expect(OnboardingStep.allCases.allSatisfy { !$0.title.isEmpty && !$0.detail.isEmpty && !$0.systemImage.isEmpty })
    }
}
