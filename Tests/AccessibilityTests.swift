import Foundation
import SwiftUI
import Testing
@testable import Stow

@Suite("Accessibility")
struct AccessibilityTests {
    private func entry(_ name: String, folder: Bool = false, size: Int64 = 2_400) -> ArchiveEntry {
        ArchiveEntry(path: name, isFolder: folder, size: size, packedSize: 0, modified: .distantPast)
    }

    @Test func fileLabelIncludesKindAndFormattedSize() {
        let file = entry("report.pdf")
        #expect(AccessibilityText.entry(file) == "report.pdf, \(file.kindDescription), \(file.size.bytes)")
    }

    @Test func folderLabelIncludesCount() {
        #expect(AccessibilityText.entry(entry("Photos", folder: true), itemCount: 3) == "Photos, Folder, 3 items")
    }

    @Test func emptyFolderLabel() {
        #expect(AccessibilityText.entry(entry("Empty", folder: true), itemCount: 0) == "Empty, Folder, 0 items")
    }

    @Test func folderWithoutCountOmitsSize() {
        #expect(AccessibilityText.entry(entry("Photos", folder: true)) == "Photos, Folder")
    }

    @Test func nestedEntryUsesName() {
        let file = entry("Docs/notes.txt")
        #expect(AccessibilityText.entry(file).hasPrefix("notes.txt, "))
    }

    @Test func progressRoundsToSpokenPercent() {
        #expect(AccessibilityText.progress(0.424) == "42 percent")
        #expect(AccessibilityText.progress(0.426) == "43 percent")
    }

    @Test func progressClampsInvalidValues() {
        #expect(AccessibilityText.progress(-1) == "0 percent")
        #expect(AccessibilityText.progress(2) == "100 percent")
        #expect(AccessibilityText.progress(.nan) == "0 percent")
    }

    @Test func standardContrastKeepsSubtleBorders() {
        let style = ContrastStyle.resolve(.standard, override: false)
        #expect(!style.increased)
        #expect(style.borderOpacity == 0.1)
        #expect(style.faintBorderOpacity == 0.06)
    }

    @Test func increasedContrastStrengthensBorders() {
        let style = ContrastStyle.resolve(.increased, override: false)
        #expect(style.increased)
        #expect(style.borderOpacity == 0.45)
        #expect(style.faintBorderOpacity == 0.45)
    }

    @Test func contrastOverridePromotesStandardContrast() {
        #expect(ContrastStyle.resolve(.standard, override: true).increased)
        #expect(ContrastStyle.resolve(.increased, override: true).increased)
    }

    @Test func reducedMotionUsesShortFades() {
        #expect(Motion.resolved(Motion.appear, reduceMotion: true) == .easeOut(duration: 0.15))
        #expect(Motion.resolved(Motion.panel, reduceMotion: true) == .easeOut(duration: 0.15))
        #expect(Motion.resolved(Motion.exit, reduceMotion: true) == .easeOut(duration: 0.1))
    }

    @Test func regularMotionPreservesPresets() {
        #expect(Motion.resolved(Motion.appear, reduceMotion: false) == Motion.appear)
        #expect(Motion.resolved(Motion.exit, reduceMotion: false) == Motion.exit)
    }

    @Test func nestedSearchResultSaysWhichArchive() {
        let file = entry("Q3.pdf")
        #expect(AccessibilityText.entry(file, container: "Reports.zip") == "Q3.pdf, \(file.kindDescription), \(file.size.bytes), in Reports.zip")
    }

    @Test func selectionSummaryReadsAsOneSentence() {
        let one = entry("report.pdf", size: 2_400)
        #expect(AccessibilityText.selectionSummary([one]) == "report.pdf, \(Int64(2_400).bytes)")
        #expect(AccessibilityText.selectionSummary([one, entry("b.txt", size: 600)]) == "2 items, \(Int64(3_000).bytes)")
    }
}
