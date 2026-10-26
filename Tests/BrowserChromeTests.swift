import Foundation
import Testing
@testable import Stow

/// The words the Browser's title, Details, Archive Info and Checkup button show (#160).
@Suite("Browser chrome")
@MainActor
struct BrowserChromeTests {
    private static func entry(_ path: String, size: Int64 = 100, packed: Int64? = 50, folder: Bool = false) -> ArchiveEntry {
        ArchiveEntry(path: path, isFolder: folder, size: size, packedSize: packed, modified: Date(timeIntervalSince1970: 1_800_000_000))
    }

    private static func archive(_ files: [ArchiveEntry], checkup: [CheckupFinding] = []) -> Archive {
        Archive(name: "Brand Kit.zip", format: .zip, files: files, checkup: checkup)
    }

    @Test func theTitleNamesTheArchiveWhereverYouAre() {
        let model = BrowserModel(archive: Self.archive([Self.entry("Docs/a.txt"), Self.entry("Docs/b.txt"), Self.entry("c.txt")]))
        #expect(model.title == "Brand Kit.zip")
        #expect(model.subtitle == "ZIP archive · 3 files")
        model.navigate(to: "Docs")
        // Where you are is the breadcrumbs' job; the title stays the archive's.
        #expect(model.title == "Brand Kit.zip")
        #expect(model.subtitle == "ZIP archive · 3 files")
    }

    @Test func locationNamesTheArchiveAndItsFolders() {
        let model = BrowserModel(archive: Self.archive([Self.entry("Showcase/Docs/a.txt"), Self.entry("c.txt")]))
        // The top level is the archive itself, not an abstract "Top level".
        #expect(model.location(ofFolder: "") == "Brand Kit.zip")
        #expect(model.location(ofFolder: "Showcase/Docs") == "Brand Kit.zip › Showcase › Docs")
        // Search results say where they are in the archive, with the archive's name for its top level.
        #expect(model.searchLocation(of: Self.entry("c.txt")) == "Brand Kit.zip")
        #expect(model.searchLocation(of: Self.entry("Showcase/Docs/a.txt")) == "Showcase › Docs")
    }

    @Test func compressedSizeDoesntGuessWhenNothingWasSaved() {
        #expect(DetailsPane.compressedFigures(size: 100, packed: 60, staged: nil) == ("60 bytes", "40% smaller"))
        // Equal sizes don't say how a file was stored before; no "already compressed".
        #expect(DetailsPane.compressedFigures(size: 27, packed: 27, staged: nil) == ("27 bytes", nil))
        #expect(DetailsPane.compressedFigures(size: 100, packed: nil, staged: nil) == ("Unavailable", nil))
        #expect(DetailsPane.compressedFigures(size: 100, packed: 60, staged: "New") == ("When you save", nil))
    }

    @Test func packedSizeSaysHowItChangedOrThatItIsUnknown() {
        #expect(ArchiveInfoView.packedFigures(Self.archive([Self.entry("a", size: 100, packed: 25)])) == ("25 bytes", "75% smaller"))
        #expect(ArchiveInfoView.packedFigures(Self.archive([Self.entry("a", size: 100, packed: 120)])) == ("120 bytes", "20% larger"))
        // A listing without packed sizes says so rather than "100% smaller".
        #expect(ArchiveInfoView.packedFigures(Self.archive([Self.entry("a", size: 100, packed: nil)])) == ("Unavailable", nil))
    }

    @Test func checkupShieldFollowsTheFindings() {
        let fine = CheckupFinding(severity: .fine, title: "Names and sizes look normal", detail: "")
        let handled = CheckupFinding(severity: .handled, title: "1 path tried to leave the folder", detail: "")
        let caution = CheckupFinding(severity: .caution, title: "Named .zip, but it’s really 7Z", detail: "")

        let safe = CheckupStatus([fine])
        // Checkup reads the listing, so it reports no warnings rather than calling the archive safe.
        #expect(safe.symbol == "checkmark.shield.fill" && safe.summary == "Checkup: no warnings")
        #expect(CheckupStatus([fine, handled]).summary == "Checkup: no warnings, 1 handled")
        let warned = CheckupStatus([fine, caution, caution])
        #expect(warned.symbol == "exclamationmark.shield.fill" && warned.summary == "Checkup: 2 things to know")
    }
}
