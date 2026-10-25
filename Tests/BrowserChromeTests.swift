import Foundation
import Testing
@testable import Stow

/// The words the Browser's title, bottom bar, Archive Info and Checkup button show (#160).
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

    @Test func theBottomBarCountsWhatsHereThenWhatsSelected() {
        let model = BrowserModel(archive: Self.archive([Self.entry("Docs/a.txt"), Self.entry("c.txt"), Self.entry("d.txt")]))
        #expect(model.statusText == "3 items")
        model.select(["c.txt"])
        #expect(model.statusText == "1 of 3 selected")
        model.navigate(to: "Docs")
        #expect(model.statusText == "1 item")
    }

    @Test func packedSizeSaysHowItChangedOrThatItIsUnknown() {
        #expect(ArchiveInfoView.packedDescription(Self.archive([Self.entry("a", size: 100, packed: 25)])) == "25 bytes · 75% smaller")
        #expect(ArchiveInfoView.packedDescription(Self.archive([Self.entry("a", size: 100, packed: 120)])) == "120 bytes · 20% larger")
        // A listing without packed sizes says so rather than "100% smaller".
        #expect(ArchiveInfoView.packedDescription(Self.archive([Self.entry("a", size: 100, packed: nil)])) == "Unavailable")
    }

    @Test func checkupShieldFollowsTheFindings() {
        let fine = CheckupFinding(severity: .fine, title: "Names and sizes look normal", detail: "")
        let handled = CheckupFinding(severity: .handled, title: "1 path tried to leave the folder", detail: "")
        let caution = CheckupFinding(severity: .caution, title: "Named .zip, but it’s really 7Z", detail: "")

        let safe = CheckupStatus([fine])
        #expect(safe.symbol == "checkmark.shield.fill" && safe.summary == "Checkup: looks safe")
        #expect(CheckupStatus([fine, handled]).summary == "Checkup: safe, 1 handled")
        let warned = CheckupStatus([fine, caution, caution])
        #expect(warned.symbol == "exclamationmark.shield.fill" && warned.summary == "Checkup: 2 things to know")
    }
}
