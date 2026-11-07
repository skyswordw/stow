import Testing
@testable import Stow

/// Glance's archive capsule (2026-11-07, replacing #248's one extraction button at a time): Quick
/// Look and Extract All stay fixed at the trailing end, and a selection adds its own ⚡ Extract.
@MainActor
@Suite("Glance extraction controls")
struct GlanceExtractTests {
    private func model(selecting paths: Set<String>) -> BrowserModel {
        let model = BrowserModel(archive: SampleArchive.make())
        model.folder = "Photos"
        model.selection = paths
        return model
    }

    private let photos: Set<String> = ["Photos/Lighthouse.jpg", "Photos/Pier at Dawn.jpg"]

    /// Extract and Extract All never share an icon, so both can show at once without reading as two
    /// of the same button.
    @Test func extractAndExtractAllHaveTheirOwnIcons() {
        #expect(NextStep.extract.symbol != ArchiveActions.extractAllSymbol)
    }

    @Test func quickLookWaitsForASelection() {
        #expect(model(selecting: []).quickLookUnavailableReason != nil)
    }

    @Test func quickLookOpensSelectedFiles() {
        #expect(model(selecting: photos).quickLookUnavailableReason == nil)
    }

    /// Results inside other archives only offer to go there; there's nothing of this archive to preview.
    @Test func quickLookWaitsOnResultsInsideOtherArchives() {
        #expect(model(selecting: ["Nested.zip/inner.txt"]).quickLookUnavailableReason != nil)
    }

    @Test func helpNamesWhatQuickLookOpens() {
        #expect(model(selecting: ["Photos/Lighthouse.jpg"]).selectionScope == "Lighthouse.jpg")
        #expect(model(selecting: photos).selectionScope == String(localized: "\(2) items"))
    }
}
