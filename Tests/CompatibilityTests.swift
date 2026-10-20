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
