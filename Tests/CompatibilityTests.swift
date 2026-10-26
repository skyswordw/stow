import Foundation
import Testing
@testable import Stow

@Suite("Windows-safe names")
struct WindowsNameTests {
    @Test(arguments: [
        ("Q3 Report: Final.pdf", "Q3 Report- Final.pdf"),
        ("aux.txt", "_aux.txt"),
        ("CON", "_CON"),
        ("To do.", "To do"),
        ("trailing  ", "trailing"),
        ("what?*.png", "what--.png"),
        ("normal.jpg", "normal.jpg"),
    ])
    func component(input: String, expected: String) {
        #expect(Compatibility.windowsSafeComponent(input) == expected)
    }

    @Test func decomposedAccentsBecomeComposed() {
        let decomposed = "Cafe\u{301}.pdf"
        let result = Compatibility.windowsSafeComponent(decomposed)
        #expect(result.unicodeScalars.count == "Café.pdf".unicodeScalars.count)
        #expect(result == "Café.pdf")
    }
}

@Suite("Pack report")
struct PackReportTests {
    @Test func macHelperFilesAreRecognised() {
        #expect(Compatibility.isMacHelperFile(".DS_Store"))
        #expect(Compatibility.isMacHelperFile("Photos/._Lighthouse.jpg"))
        #expect(Compatibility.isMacHelperFile("__MACOSX/Photos/x.jpg"))
        #expect(Compatibility.isMacHelperFile("Slides/Icon\r"))
        #expect(!Compatibility.isMacHelperFile("Photos/Lighthouse.jpg"))
    }

    @Test func windowsDropsHelpersAndRenames() {
        let report = Compatibility.report(for: SampleArchive.packCandidates, options: PackOptions())
        #expect(report.excluded.count == 4)
        #expect(report.renames.map(\.to).contains("Q3 Report- Final.pdf"))
        // NFC-only changes aren't reported as renames people would notice.
        #expect(!report.renames.map(\.from).contains("Cafe\u{301} Menu.pdf"))
    }

    @Test func macKeepsEverything() {
        var options = PackOptions()
        options.setAudience(.mac)
        let report = Compatibility.report(for: SampleArchive.packCandidates, options: options)
        #expect(report.excluded.isEmpty)
        #expect(report.renames.isEmpty)
    }

    @Test func switchingAudienceKeepsOptionsConsistent() {
        var options = PackOptions()
        options.setFormat(.zip)
        options.usesPassword = true
        options.setAudience(.linux)
        #expect(options.format == .zip) // still allowed for Linux
        options.setFormat(.tarXz)
        #expect(!options.usesPassword)  // tar can't carry a password
        options.setAudience(.web)
        #expect(options.format == .zip)
    }

    @Test func perJobHelperOverrideKeepsMacHelpersOnWindows() {
        var options = PackOptions()
        options.includeMacHelperFiles = true
        let report = Compatibility.report(for: SampleArchive.packCandidates, options: options)
        #expect(report.excluded.isEmpty)
        #expect(options.dropsMacHelperFiles == false)
    }

    @Test func perJobHelperOverrideDropsHelpersOnMac() {
        var options = PackOptions()
        options.setAudience(.mac)
        options.includeMacHelperFiles = false
        let report = Compatibility.report(for: SampleArchive.packCandidates, options: options)
        #expect(report.excluded.count == 4)
        #expect(options.dropsMacHelperFiles)
    }

    @Test func perJobMacMetadataOverrideForZip() {
        var options = PackOptions()
        options.setAudience(.windows)
        options.setFormat(.zip)
        #expect(!options.effectiveKeepsMacMetadata)
        options.keepsMacMetadata = true
        #expect(options.effectiveKeepsMacMetadata)
        options.setFormat(.sevenZip)
        #expect(options.keepsMacMetadata == nil)
        #expect(!options.effectiveKeepsMacMetadata)
    }

    @Test func encryptFilenamesDefaultAndNotes() {
        var options = PackOptions()
        options.setFormat(.sevenZip)
        options.usesPassword = true
        #expect(options.encryptFilenames)
        let hidden = Compatibility.report(for: SampleArchive.packCandidates, options: options, password: "pw")
        #expect(hidden.notes.contains { $0.title == "Contents and file names are encrypted" })
        options.encryptFilenames = false
        let visible = Compatibility.report(for: SampleArchive.packCandidates, options: options, password: "pw")
        #expect(visible.notes.contains { $0.title == "Contents are encrypted; file names stay visible" })
    }

    @Test @MainActor func resetToPurposeDefaultsClearsOverrides() {
        var options = PackOptions()
        options.setAudience(.windows)
        options.includeMacHelperFiles = true
        options.keepsMacMetadata = true
        options.encryptFilenames = false
        options.threads = 2
        options.resetToPurposeDefaults()
        #expect(options.includeMacHelperFiles == nil)
        #expect(options.keepsMacMetadata == nil)
        #expect(options.encryptFilenames)
        #expect(options.threads == nil)
        #expect(options.dropsMacHelperFiles) // windows default
    }

    @Test func effectiveThreadsRespectsBounds() {
        var options = PackOptions()
        options.threads = 0
        #expect(options.effectiveThreads(global: 4) == 1)
        options.threads = 9_999
        let capped = options.effectiveThreads(global: nil)!
        #expect(capped == ProcessInfo.processInfo.activeProcessorCount)
        options.threads = nil
        #expect(options.effectiveThreads(global: 3) == 3)
    }

    @Test func splitCountsParts() {
        var options = PackOptions()
        options.split = .mb100
        let big = [PackFile(path: "movie.mov", size: 450_000_000)]
        #expect(Compatibility.report(for: big, options: options).parts == 5)
    }
}

@Suite("Next steps")
struct NextStepTests {
    private func entry(_ path: String) -> ArchiveEntry {
        ArchiveEntry(path: path, isFolder: false, size: 1, packedSize: 1, modified: .now)
    }

    @Test func fontsSuggestInstall() {
        let steps = NextStep.suggestions(for: [entry("a.otf"), entry("b.ttf")])
        #expect(steps.first == .installFonts(count: 2))
        #expect(steps.last == .extract)
    }

    @Test func singleAppSuggestsApplications() {
        #expect(NextStep.suggestions(for: [entry("X.app")]) == [.moveToApplications, .extract])
    }

    @Test func emptySelectionSuggestsNothing() {
        #expect(NextStep.suggestions(for: []).isEmpty)
    }
}
