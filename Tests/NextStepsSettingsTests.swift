import Foundation
import Testing
@testable import Stow

@Suite("Next Steps settings")
struct NextStepsSettingsTests {
    private func entry(_ path: String) -> ArchiveEntry {
        ArchiveEntry(path: path, isFolder: false, size: 1, packedSize: 1, modified: .now)
    }

    private func withStore(_ body: (UserDefaults) throws -> Void) throws {
        let name = "NextStepsSettingsTests.\(UUID().uuidString)"
        let store = try #require(UserDefaults(suiteName: name))
        defer { store.removePersistentDomain(forName: name) }
        try body(store)
    }

    /// Selections that between them reach every kind of step.
    private var selections: [(entries: [ArchiveEntry], targets: [DiskImageLayout.DropTarget])] {
        [([entry("Photos/Pier.jpg")], []),
         ([entry("Fonts/A.otf"), entry("Fonts/B.ttf")], []),
         ([entry("Harbor.app")], []),
         ([entry("Setup.pkg")], []),
         ([entry("Nested.zip")], []),
         ([entry("Echo.component")], [DiskImageLayout.DropTarget(path: "Components", folder: "/Library/Audio/Plug-Ins/Components")]),
         ([entry("notes.txt"), entry("Harbor.app")], [])]
    }

    @Test func defaultsSuggestTheSpecificStepThenExtract() {
        let settings = NextStepsSettings.defaults
        let image = settings.layout(for: [entry("Photos/Pier.jpg")])
        #expect(image.suggestions == [.quickLook])
        #expect(image.primary == .extract)
        #expect(image.alternatives == [.pack])

        let app = settings.layout(for: [entry("Harbor.app")])
        #expect(app.suggestions == [.moveToApplications])
        #expect(app.primary == .extract)
        #expect(app.alternatives == [.pack])
        #expect(settings.layout(for: []) == .init())
    }

    @Test func applicableStepsInCapsuleOrder() {
        #expect(NextStep.applicable(for: [entry("A.otf"), entry("B.ttf")])
                == [.installFonts(count: 2), .quickLook, .pack, .extract])
        #expect(NextStep.applicable(for: [entry("Nested.zip")]) == [.openInside, .pack, .extract])
        #expect(NextStep.applicable(for: []).isEmpty)
        // The older list (inspector, context menus) is unchanged: no Pack.
        #expect(NextStep.suggestions(for: [entry("A.otf"), entry("B.ttf")]) == [.installFonts(count: 2), .quickLook, .extract])
    }

    @Test func hiddenStepsLeaveTheCapsule() {
        var settings = NextStepsSettings.defaults
        settings.set(.quickLook, shown: false)
        let image = settings.layout(for: [entry("Photos/Pier.jpg")])
        #expect(image.suggestions.isEmpty)
        #expect(image.primary == .extract)
        #expect(image.alternatives == [.quickLook, .pack])
    }

    @Test func shownPackTakesASuggestionSlot() {
        var settings = NextStepsSettings.defaults
        settings.set(.pack, shown: true)
        #expect(settings.layout(for: [entry("Photos/Pier.jpg")]).suggestions == [.quickLook, .pack])
        // Never more than two beside the main button; the rest wait in More.
        let fonts = settings.layout(for: [entry("A.otf"), entry("B.ttf")])
        #expect(fonts.suggestions == [.installFonts(count: 2), .quickLook])
        #expect(fonts.alternatives == [.pack])
    }

    @Test func hidingExtractPromotesTheFirstShownStep() {
        var settings = NextStepsSettings.defaults
        settings.set(.extract, shown: false)
        let app = settings.layout(for: [entry("Harbor.app")])
        #expect(app.primary == .moveToApplications)
        #expect(app.suggestions.isEmpty)
        #expect(app.alternatives == [.pack, .extract])

        for kind in NextStep.Kind.allCases { settings.set(kind, shown: false) }
        let nothing = settings.layout(for: [entry("Harbor.app")])
        #expect(nothing.primary == nil)
        #expect(nothing.suggestions.isEmpty)
        #expect(nothing.alternatives == [.moveToApplications, .pack, .extract])
    }

    /// Whatever is hidden, every step that applies is on the capsule or in More — exactly once.
    @Test func everyApplicableStepStaysReachable() {
        let kinds = NextStep.Kind.allCases
        for mask in 0..<(1 << kinds.count) {
            let hidden = Set(kinds.indices.filter { mask & (1 << $0) != 0 }.map { kinds[$0] })
            let settings = NextStepsSettings(hidden: hidden)
            for selection in selections {
                let all = NextStep.applicable(for: selection.entries, dropTargets: selection.targets)
                let layout = settings.layout(for: selection.entries, dropTargets: selection.targets)
                let placed = layout.suggestions + [layout.primary].compactMap(\.self) + layout.alternatives
                #expect(placed.count == all.count)
                #expect(Set(placed) == Set(all))
                #expect(layout.suggestions.count <= NextStepsSettings.maxSuggestions)
                #expect(layout.suggestions.allSatisfy { !hidden.contains($0.kind) })
                if let primary = layout.primary { #expect(!hidden.contains(primary.kind)) }
                for step in all where hidden.contains(step.kind) {
                    #expect(layout.alternatives.contains(step))
                }
                // Alternatives keep the capsule's order.
                #expect(layout.alternatives == all.filter(layout.alternatives.contains))
            }
        }
    }

    @Test func everyStepHasAKindSettingsCanName() {
        let steps: [NextStep] = [.installFonts(count: 3), .moveToApplications, .openInstaller, .copyTo(folder: "/Library/Fonts"),
                                 .openInside, .quickLook, .pack, .extract]
        #expect(steps.map(\.kind) == NextStep.Kind.allCases)
        for kind in NextStep.Kind.allCases {
            #expect(!kind.title.isEmpty && !kind.when.isEmpty && !kind.symbol.isEmpty)
        }
        #expect(Set(NextStep.Kind.allCases.map(\.title)).count == NextStep.Kind.allCases.count)
        // The same keys as the menu bar: File › Extract, Go › Quick Look, Go › Open.
        #expect(NextStep.extract.menuShortcut == .init("e"))
        #expect(NextStep.quickLook.menuShortcut == .init("y"))
        #expect(NextStep.openInside.menuShortcut == .init(.downArrow))
        #expect(NextStep.pack.menuShortcut == nil)
    }

    @Test func storedChoicesRoundTrip() throws {
        try withStore { store in
            #expect(NextStepsSettings.load(from: store) == .defaults)
            var settings = NextStepsSettings.defaults
            settings.isShown = false
            settings.set(.pack, shown: true)
            settings.set(.quickLook, shown: false)
            settings.set(.extract, shown: false)
            settings.save(to: store)
            #expect(store.string(forKey: SettingsKeys.nextStepsHidden) == "quickLook,extract")
            #expect(NextStepsSettings.load(from: store) == settings)
            #expect(!NextStepsSettings.load(from: store).isDefault)
        }
    }

    @Test func storedValuesDecodeForgivingly() {
        #expect(NextStepsSettings.decode(nil) == [.pack])
        #expect(NextStepsSettings.decode("").isEmpty)
        #expect(NextStepsSettings.decode("quickLook,fromTheFuture,,extract") == [.quickLook, .extract])
        #expect(NextStepsSettings.encode([.extract, .installFonts]) == "installFonts,extract")
    }

    @Test func restoreDefaults() throws {
        try withStore { store in
            NextStepsSettings(isShown: false, hidden: Set(NextStep.Kind.allCases)).save(to: store)
            store.set("keep", forKey: SettingsKeys.appearance)
            NextStepsSettings.restoreDefaults(in: store)
            #expect(store.object(forKey: SettingsKeys.nextStepsShown) == nil)
            #expect(store.object(forKey: SettingsKeys.nextStepsHidden) == nil)
            #expect(NextStepsSettings.load(from: store) == .defaults)
            #expect(NextStepsSettings.load(from: store).isDefault)
            // Only Next Steps goes back; other preferences stay.
            #expect(store.string(forKey: SettingsKeys.appearance) == "keep")
        }
    }

    @Test func resetAllPreferencesRestoresNextStepsToo() throws {
        try withStore { store in
            NextStepsSettings(isShown: false, hidden: []).save(to: store)
            SettingsKeys.reset(in: store)
            #expect(NextStepsSettings.load(from: store) == .defaults)
            #expect(SettingsKeys.defaultValue(for: SettingsKeys.nextStepsHidden) == .string("pack"))
            #expect(SettingsKeys.defaultValue(for: SettingsKeys.nextStepsShown) == .bool(true))
        }
    }
}
