import Testing
@testable import Stow

/// Glance shows one extraction button at a time (#248): Extract All steps aside only while the
/// selection's Actions offer Extract, so the bar never shows two of them, or none.
@MainActor
@Suite("Glance extraction button")
struct GlanceExtractTests {
    private func model(selecting paths: Set<String>) -> BrowserModel {
        let model = BrowserModel(archive: SampleArchive.make())
        model.folder = "Photos"
        model.selection = paths
        return model
    }

    private let photos: Set<String> = ["Photos/Lighthouse.jpg", "Photos/Pier at Dawn.jpg"]

    @Test func aSelectionsExtractTakesOverFromExtractAll() {
        #expect(GlanceLayout.selectionExtracts(model(selecting: photos), settings: .defaults))
    }

    @Test func nothingSelectedKeepsExtractAll() {
        #expect(!GlanceLayout.selectionExtracts(model(selecting: []), settings: .defaults))
    }

    @Test func actionsTurnedOffKeepExtractAll() {
        var settings = NextStepsSettings.defaults
        settings.isShown = false
        #expect(!GlanceLayout.selectionExtracts(model(selecting: photos), settings: settings))
    }

    /// Hidden, Extract waits in ⋯: without Extract All the bar would have no extraction button.
    @Test func extractHiddenFromActionsKeepsExtractAll() {
        var settings = NextStepsSettings.defaults
        settings.set(.extract, shown: false)
        #expect(!GlanceLayout.selectionExtracts(model(selecting: photos), settings: settings))
    }

    /// Results inside other archives only offer to go there; there's no Extract beside them.
    @Test func resultsInsideOtherArchivesKeepExtractAll() {
        #expect(!GlanceLayout.selectionExtracts(model(selecting: ["Nested.zip/inner.txt"]), settings: .defaults))
    }

    // Where Extract All sits: always at the trailing end, where a selection's stack takes its place.

    @Test func extractAllIsAloneWithoutActions() {
        #expect(GlanceLayout.extractAllPlacement(showsActions: false, selectionExtracts: false, hasActivity: false) == .alone)
    }

    @Test func aStackWithExtractTakesExtractAllsPlace() {
        #expect(GlanceLayout.extractAllPlacement(showsActions: true, selectionExtracts: true, hasActivity: false) == .hidden)
    }

    /// Install App for an archive that's one app, or a stack without Extract: Extract All stays beside it.
    @Test func aStackWithoutExtractKeepsExtractAllBesideIt() {
        #expect(GlanceLayout.extractAllPlacement(showsActions: true, selectionExtracts: false, hasActivity: false) == .besideActions)
    }

    /// A step's progress holds the place; Extract All would only wait, dimmed, and push it aside.
    @Test func progressTakesExtractAllsPlace() {
        #expect(GlanceLayout.extractAllPlacement(showsActions: true, selectionExtracts: false, hasActivity: true) == .hidden)
    }
}
