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

    /// The stack puts installing in front for something to install, Extract in front otherwise,
    /// and More reaches every action but the front one.
    @Test func stackFrontIsInstallForInstallablesOtherwiseExtract() {
        let settings = NextStepsSettings.defaults
        let app = settings.layout(for: [entry("Harbor.app")])
        #expect(app.front == .moveToApplications)
        #expect(app.behind == [.extract])
        #expect(app.more == [.extract, .pack])

        let fonts = settings.layout(for: [entry("A.otf"), entry("B.ttf")])
        #expect(fonts.front == .installFonts(count: 2))
        #expect(fonts.behind == [.quickLook, .extract])

        #expect(settings.layout(for: [entry("Setup.pkg")]).front == .openInstaller)

        let image = settings.layout(for: [entry("Photos/Pier.jpg")])
        #expect(image.front == .extract)
        #expect(image.behind == [.quickLook])
        #expect(image.more == [.quickLook, .pack])

        // An archive inside opens from the stack, but Extract stays in front.
        let nested = settings.layout(for: [entry("Nested.zip")])
        #expect(nested.front == .extract)
        #expect(nested.behind == [.openInside])

        #expect(settings.layout(for: []).front == nil)
    }

    @Test func hidingInstallLeavesExtractInFront() {
        var settings = NextStepsSettings.defaults
        settings.set(.moveToApplications, shown: false)
        let app = settings.layout(for: [entry("Harbor.app")])
        #expect(app.front == .extract)
        #expect(app.behind.isEmpty)
        #expect(app.more == [.moveToApplications, .pack])
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

/// With nothing selected, Actions offers installing the archive's one app, as ArcZip 1.1.4 does.
@Suite("Actions with nothing selected")
@MainActor
struct ArchiveActionsTests {
    private static let plist = "Harbor.app/Contents/Info.plist"
    private static let executable = "Harbor.app/Contents/MacOS/Harbor"

    /// Through the real listing path, which tells helper items (`__MACOSX`, `.DS_Store`) apart.
    private func archive(_ paths: [String], type: String = "zip") -> Archive {
        Archive(listing: ArchiveListing(type: type, entries: paths.map { ListedEntry(path: $0, isFolder: false, size: 1) }),
                url: URL(filePath: "/tmp/Harbor.\(type.lowercased())"))
    }

    private func entry(_ path: String) -> ArchiveEntry {
        ArchiveEntry(path: path, isFolder: false, size: 1, packedSize: 1, modified: .now)
    }

    @Test func theArchivesOneAppIsWhatItsFor() {
        #expect(archive([Self.plist, Self.executable]).installable?.path == "Harbor.app")
        // The helper items a Mac packs beside it don't count.
        #expect(archive([Self.plist, "__MACOSX/Harbor.app/Contents/._Info.plist", ".DS_Store"]).installable?.path == "Harbor.app")
        // Nor do a couple of other things: ArcZip's test archive was an app and a text file.
        #expect(archive([Self.plist, "Read Me.txt", "LICENSE"]).installable?.path == "Harbor.app")
        #expect(archive(["Setup.pkg"]).installable?.path == "Setup.pkg")
        // A disk image is for installing, however much window dressing is left beside the app.
        #expect(archive([Self.plist, "a.txt", "b.txt", "c.txt", "d.txt"], type: "Dmg").installable?.path == "Harbor.app")
    }

    @Test func notWhenTheAppIsOneThingAmongMany() {
        // Two candidates, a folder around it, or more than two other things: nothing to guess at.
        #expect(archive([Self.plist, "Other.app/Contents/Info.plist"]).installable == nil)
        #expect(archive([Self.plist, "Setup.pkg"]).installable == nil)
        #expect(archive(["Harbor/" + Self.plist]).installable == nil)
        #expect(archive([Self.plist, "a.txt", "b.txt", "c.txt"]).installable == nil)
        #expect(archive(["notes.txt"]).installable == nil)
        #expect(archive([]).installable == nil)
    }

    @Test func installIsTheStacksOnlyAction() throws {
        let settings = NextStepsSettings.defaults
        let harbor = try #require(archive([Self.plist]).installable)
        let layout = settings.archiveLayout(installable: harbor)
        #expect(layout.front == .moveToApplications)
        // Extract All has its own button beside the stack: nothing behind, nothing in More.
        #expect(layout.behind.isEmpty)
        #expect(layout.more.isEmpty)
        // An installer package or anything else: no stack, Extract All alone.
        #expect(settings.archiveLayout(installable: entry("Setup.pkg")) == .init())
        #expect(settings.archiveLayout(installable: entry("notes.txt")) == .init())
        #expect(settings.archiveLayout(installable: nil) == .init())
    }

    @Test func hidingInstallAppLeavesTheStackEmpty() throws {
        let harbor = try #require(archive([Self.plist]).installable)
        var settings = NextStepsSettings.defaults
        settings.set(.extract, shown: false)
        #expect(settings.archiveLayout(installable: harbor).front == .moveToApplications)
        settings.set(.moveToApplications, shown: false)
        let layout = settings.archiveLayout(installable: harbor)
        #expect(layout.front == nil)
        // Still in File › Actions, like a selection's hidden steps.
        #expect(layout.more == [.moveToApplications])
    }

    @Test func theBrowserOffersItOnlyWithNothingSelected() {
        let files = [Self.plist, Self.executable, "Read Me.txt"].map(entry)
        let model = BrowserModel(archive: Archive(name: "Harbor.zip", format: .zip, files: files))
        // Opening selects the app, so Actions works on the selection.
        #expect(model.selection == ["Harbor.app"])
        #expect(model.archiveTarget == nil)
        model.select([])
        #expect(model.archiveTarget?.path == "Harbor.app")
        model.select(["Read Me.txt"])
        #expect(model.archiveTarget == nil)

        // While the listing is still coming in, the top level may not be complete.
        let listing = BrowserModel(archive: Archive(name: "Harbor.zip", format: .zip, files: files), isListing: true)
        listing.select([])
        #expect(listing.archiveTarget == nil)
    }
}
