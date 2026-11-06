import Foundation
import Testing
@testable import Stow

/// The words the Browser's title, Details, Archive Info and archive findings show (#160).
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
        #expect(DetailsPane.compressedFigures(size: 100, packed: nil, staged: nil) == ("Not reported by the archive", nil))
        #expect(DetailsPane.compressedFigures(size: 100, packed: 60, staged: "New") == ("Available after saving", nil))
    }

    @Test func packedSizeSaysHowItChangedOrThatItIsUnknown() {
        #expect(ArchiveInfoView.packedFigures(Self.archive([Self.entry("a", size: 100, packed: 25)])) == ("25 bytes", "75% smaller"))
        #expect(ArchiveInfoView.packedFigures(Self.archive([Self.entry("a", size: 100, packed: 120)])) == ("120 bytes", "20% larger"))
        // A listing without packed sizes says so rather than "100% smaller".
        #expect(ArchiveInfoView.packedFigures(Self.archive([Self.entry("a", size: 100, packed: nil)])) == ("Not reported by the archive", nil))
    }

    @Test func normalFindingsDoNotDemandAttention() {
        let fine = CheckupFinding(severity: .fine, title: "Names and sizes look normal", detail: "")
        let info = CheckupFinding(severity: .info, title: "Metadata", detail: "")
        let planned = CheckupFinding(severity: .handled, title: "Links point outside", detail: "Will be left out")
        let caution = CheckupFinding(severity: .caution, title: "Format mismatch", detail: "")
        #expect(!fine.needsAttention && !info.needsAttention)
        #expect(planned.needsAttention && caution.needsAttention)
    }

    @Test func detailsNamesItsScopeAndDoesNotCountDescendantsTwice() {
        let folder = Self.entry("Docs", size: 300, folder: true)
        let child = Self.entry("Docs/a.txt", size: 100)
        let archive = Self.entry("inner.zip", size: 50)
        let nested = Self.entry("inner.zip/a.txt", size: 100)
        #expect(DetailsPane.heading(for: []) == "Archive Info")
        #expect(DetailsPane.heading(for: [folder]) == "Folder Info")
        #expect(DetailsPane.heading(for: [child]) == "File Info")
        #expect(DetailsPane.heading(for: [folder, child]) == "Selection Info")
        #expect(DetailsPane.combinedSize(of: [folder, child, archive, nested, child]) == 350)
        #expect(DetailsPane.combinedSize(of: [child, nested]) == 200)
        #expect(DetailsPane.combinedSize(of: [Self.entry("Doc", size: 10), child]) == 110)
    }

    @Test func packedSizeLabelsKeepTheirMeasurementSourceAcrossRelisting() {
        let file = Self.entry("a.txt", size: 100, packed: 50)
        let entries = Self.archive([file])
        #expect(!entries.packedSizeIncludesContainer)
        let relisted = Archive(entries, files: [file], helpers: [], source: ArchiveSource(url: URL(filePath: "/tmp/clarity-test.zip"), storedPaths: [:]))
        #expect(!relisted.packedSizeIncludesContainer && relisted.packedSize == 50)
        let container = Archive(name: "a.7z", format: .sevenZip, files: [file], containerPackedSize: 90)
        let updated = Archive(container, files: [file], helpers: [], source: ArchiveSource(url: URL(filePath: "/tmp/clarity-test.zip"), storedPaths: [:]))
        #expect(updated.packedSizeIncludesContainer && updated.packedSize == 90)
    }

    /// Search is a button until it's opened, then a field that takes the free room and then the
    /// name's, never the view and editing controls' (#242).
    @Test func searchOpensIntoTheTitleBarsFreeRoom() {
        let closed = TitleBarLayout(windowWidth: 1100, isSearchOpen: false)
        #expect(closed.searchWidth == TitleBarLayout.buttonWidth)
        #expect(closed.titleMaxWidth == TitleBarLayout.titleMaximum)

        // A wide window: the full field, and the name keeps all its room.
        let open = TitleBarLayout(windowWidth: 1100, isSearchOpen: true)
        #expect(open.searchWidth == TitleBarLayout.fieldMaximum)
        #expect(open.titleMaxWidth == TitleBarLayout.titleMaximum)

        // The narrowest window (480 pt of files beside 250 pt of Details): a shorter field, and the
        // name gives way to it rather than the field closing.
        let narrow = TitleBarLayout(windowWidth: 730, isSearchOpen: true)
        #expect(narrow.searchWidth >= TitleBarLayout.fieldMinimum)
        #expect(narrow.searchWidth < TitleBarLayout.fieldMaximum)
        #expect(narrow.titleMaxWidth >= TitleBarLayout.titleSqueezed)
        #expect(narrow.titleMaxWidth < TitleBarLayout(windowWidth: 730, isSearchOpen: false).titleMaxWidth)
    }

    /// Save saying its name (there are changes) takes its room from Search and the name, not the reverse.
    @Test func saveWithItsNameLeavesSearchLessRoom() {
        let plain = TitleBarLayout(windowWidth: 760, isSearchOpen: true)
        let saving = TitleBarLayout(windowWidth: 760, isSearchOpen: true, saveShowsTitle: true)
        #expect(saving.searchWidth + saving.titleMaxWidth <= plain.searchWidth + plain.titleMaxWidth)
        #expect(saving.searchWidth >= TitleBarLayout.fieldMinimum)
    }

    /// Opening and closing Search move its width over a few frames; ⌘F and Reduce Motion don't (#242).
    @Test func searchWidthMovesOnlyForAPointerAndWithoutReduceMotion() {
        #expect(ToolbarWidthMotion.duration(opening: true, byKeyboard: false, reduceMotion: false) == ToolbarWidthMotion.opening)
        #expect(ToolbarWidthMotion.duration(opening: false, byKeyboard: false, reduceMotion: false) == ToolbarWidthMotion.closing)
        // Closing is quicker than opening, as everything leaving is (DESIGN.md › Motion).
        #expect(ToolbarWidthMotion.closing < ToolbarWidthMotion.opening)
        #expect(ToolbarWidthMotion.duration(opening: true, byKeyboard: true, reduceMotion: false) == nil)
        #expect(ToolbarWidthMotion.duration(opening: true, byKeyboard: false, reduceMotion: true) == nil)
        #expect(ToolbarWidthMotion.duration(opening: false, byKeyboard: false, reduceMotion: true) == nil)

        // The curve starts and ends where it should, never runs backwards and never overshoots.
        #expect(ToolbarWidthMotion.progress(0) == 0 && ToolbarWidthMotion.progress(1) == 1)
        #expect(ToolbarWidthMotion.progress(-1) == 0 && ToolbarWidthMotion.progress(2) == 1)
        let steps = stride(from: 0.0, through: 1.0, by: 0.05).map(ToolbarWidthMotion.progress)
        #expect(zip(steps, steps.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(steps.allSatisfy { $0 >= 0 && $0 <= 1 })
        // Ease-out: most of the way there by halfway.
        #expect(ToolbarWidthMotion.progress(0.5) > 0.8)
    }

    /// Save's and Pack…'s names unroll over a few frames and end exactly where they're headed; a key
    /// press or Reduce Motion (no duration) sets the width at once, stopping a move in progress.
    @Test func toolbarWidthStepArrivesAndKeyPressesSetItAtOnce() async throws {
        let step = ToolbarWidthStep(0)
        step.move(to: 1, duration: 0.05)
        #expect(step.value < 1)
        try await Task.sleep(for: .milliseconds(250))
        #expect(step.value == 1)

        step.move(to: 0, duration: 0.5)
        step.move(to: 0.25, duration: nil)
        #expect(step.value == 0.25)
        try await Task.sleep(for: .milliseconds(80))
        #expect(step.value == 0.25)
    }

    @Test func passwordAccessTakesTheLocksWidthFromTheName() {
        let plain = TitleBarLayout(windowWidth: 730, isSearchOpen: true)
        let encrypted = TitleBarLayout(windowWidth: 730, isSearchOpen: true, isEncrypted: true)
        #expect(encrypted.searchWidth + encrypted.titleMaxWidth
                == plain.searchWidth + plain.titleMaxWidth - TitleBarLayout.unlockIcon)
    }

    /// A deep path folds its middle into a menu one folder at a time, keeping the archive it starts
    /// from and where you are, until only where you are is left (#242).
    @Test func deepPathsFoldTheirMiddleFirst() {
        #expect(Breadcrumbs.folds(count: 1).map(\.hidden) == [0])
        #expect(Breadcrumbs.folds(count: 2).map(\.hidden) == [0])

        let folds = Breadcrumbs.folds(count: 5)
        #expect(folds.map(\.hidden) == [0, 1, 2, 3, 4])
        // The whole route first.
        #expect(folds[0].head == 0..<1 && folds[0].folded.isEmpty && folds[0].tail == 1..<5)
        // Then the folder after the archive goes into the menu, then the next.
        #expect(folds[1].head == 0..<1 && folds[1].folded == 1..<2 && folds[1].tail == 2..<5)
        #expect(folds[3].head == 0..<1 && folds[3].folded == 1..<4 && folds[3].tail == 4..<5)
        // Last: the menu holds everything above where you are, archive included.
        #expect(folds[4].head.isEmpty && folds[4].folded == 0..<4 && folds[4].tail == 4..<5)
        // Every part is either shown or in the menu, exactly once.
        for fold in folds {
            #expect(fold.head.count + fold.folded.count + fold.tail.count == 5)
        }
    }
}
