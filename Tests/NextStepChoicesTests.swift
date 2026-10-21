import Foundation
import Testing
@testable import Stow

/// Issue #20: the More Actions list and turning suggestions off.
@MainActor
struct NextStepChoicesTests {
    private func entry(_ path: String) -> ArchiveEntry {
        ArchiveEntry(path: path, isFolder: false, size: 1, packedSize: 1, modified: .now)
    }

    private func withStore(_ body: (UserDefaults) throws -> Void) throws {
        let name = "NextStepChoicesTests.\(UUID().uuidString)"
        let store = try #require(UserDefaults(suiteName: name))
        defer { store.removePersistentDomain(forName: name) }
        try body(store)
    }

    @Test func turnedOffStepMovesToMore() {
        let pdf = [entry("Specs/Guide.pdf")]
        #expect(NextStep.suggestions(for: pdf) == [.quickLook, .extract])
        #expect(NextStep.alternatives(for: pdf).isEmpty)
        #expect(NextStep.suggestions(for: pdf, hidden: [.quickLook]) == [.extract])
        #expect(NextStep.alternatives(for: pdf, hidden: [.quickLook]) == [.quickLook])
    }

    @Test func extraDropFoldersWaitInMore() {
        let targets = [
            DiskImageLayout.DropTarget(path: "Applications", folder: "/Applications"),
            DiskImageLayout.DropTarget(path: "Components", folder: "/Library/Audio/Plug-Ins/Components"),
            DiskImageLayout.DropTarget(path: "VST3", folder: "/Library/Audio/Plug-Ins/VST3"),
            DiskImageLayout.DropTarget(path: "HAL", folder: "/Library/Audio/Plug-Ins/HAL"),
        ]
        let plugIn = [entry("Echo.component")]
        let shown = NextStep.suggestions(for: plugIn, dropTargets: targets)
        // Two on the bar (the first two folders), the third waits in More.
        #expect(shown == [.copyTo(folder: "/Library/Audio/Plug-Ins/Components"),
                          .copyTo(folder: "/Library/Audio/Plug-Ins/VST3"), .extract])
        let more = NextStep.alternatives(for: plugIn, dropTargets: targets)
        #expect(more == [.copyTo(folder: "/Library/Audio/Plug-Ins/HAL")])
        #expect(!more.contains(.copyTo(folder: "/Applications")))
        #expect(Set(more).isDisjoint(with: shown))
        // Turning Copy off moves every drop folder to More; nothing is lost.
        let hidden = NextStep.alternatives(for: plugIn, dropTargets: targets, hidden: [.copyTo])
        #expect(hidden.filter { if case .copyTo = $0 { true } else { false } }.count == 3)
    }

    @Test func extractCannotBeTurnedOff() {
        let app = [entry("X.app")]
        let everything = Set(NextStep.Kind.allCases)
        #expect(NextStep.suggestions(for: app, hidden: everything) == [.extract])
        #expect(NextStep.alternatives(for: app, hidden: everything) == [.moveToApplications])
        #expect(NextStep.extract.kind == nil)
        #expect(NextStep.suggestions(for: [], hidden: everything).isEmpty)
    }

    @Test func kindsHaveDistinctTitles() {
        let steps: [NextStep] = [.installFonts(count: 2), .moveToApplications, .openInstaller,
                                 .copyTo(folder: "/Library/Screen Savers"), .openInside, .quickLook]
        #expect(Set(steps.compactMap(\.kind)) == Set(NextStep.Kind.allCases))
        let titles = NextStep.Kind.allCases.map(\.title)
        #expect(titles.allSatisfy { !$0.isEmpty })
        #expect(Set(titles).count == titles.count)
    }

    @Test func preferencesRoundTripAndRestore() throws {
        try withStore { store in
            #expect(NextStepPreferences.hidden(in: store).isEmpty)
            NextStepPreferences.setHidden(.quickLook, true, in: store)
            NextStepPreferences.setHidden(.installApp, true, in: store)
            // Stable order, so Settings and the bar agree on one string.
            #expect(store.string(forKey: NextStepPreferences.key) == "installApp,quickLook")
            #expect(NextStepPreferences.hidden(in: store) == [.installApp, .quickLook])
            NextStepPreferences.setHidden(.installApp, false, in: store)
            #expect(NextStepPreferences.hidden(in: store) == [.quickLook])
            #expect(NextStepPreferences.parse("quickLook,someday,,openInside") == [.quickLook, .openInside])
            NextStepPreferences.restore(in: store)
            #expect(store.object(forKey: NextStepPreferences.key) == nil)
            #expect(SettingsKeys.resettable.contains { $0.key == NextStepPreferences.key })
        }
    }
}
