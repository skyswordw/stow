import Foundation

/// "Harbor Rebrand Handoff": Try the Sample opens the bundled genuine ZIP (`bundledURL`); design-review
/// scenes still use `make()` for an in-memory listing (including fictional Prototype/Audio entries that
/// are not in the release ZIP). Real preview files live under Resources/Sample (see `SampleContent`).
enum SampleArchive {
    /// The genuine ZIP Try the Sample opens. Sizes and Extract/Install go through the normal engine.
    static var bundledURL: URL? {
        let name = "Harbor Rebrand Handoff"
        if let url = Bundle.main.url(forResource: name, withExtension: "zip", subdirectory: "Sample") {
            return url
        }
        let fallback = Bundle.main.resourceURL?.appending(path: "Sample/\(name).zip")
        if let fallback, FileManager.default.fileExists(atPath: fallback.path) { return fallback }
        return nil
    }

    /// In-memory listing for design-review scenes and tests that do not open the bundled ZIP.
    /// Fictional sizes and entries (Prototype.app, nested .7z, …) stay here; they are not in `bundledURL`.
    static func make(named name: String = "Harbor Rebrand Handoff.zip") -> Archive {
        let files: [(String, Int64)] = [
            ("README.md", 4_200),
            ("Specs/Brand Guidelines.pdf", 8_400_000),
            ("Specs/Color Tokens.json", 12_300),
            ("Specs/Motion Notes.txt", 3_100),
            ("Logo/Harbor Mark.svg", 18_400),
            ("Logo/Harbor Wordmark.svg", 22_900),
            ("Logo/Harbor Mark@2x.png", 241_000),
            ("Screens/Home.png", 1_820_000),
            ("Screens/Checkout.png", 2_140_000),
            ("Screens/Onboarding 1.png", 1_310_000),
            ("Screens/Onboarding 2.png", 1_290_000),
            ("Screens/Onboarding 3.png", 1_350_000),
            ("Screens/Settings.png", 980_000),
            ("Screens/Dark/Home.png", 1_760_000),
            ("Screens/Dark/Checkout.png", 2_020_000),
            ("Photos/Pier at Dawn.jpg", 4_210_000),
            ("Photos/Lighthouse.jpg", 3_870_000),
            ("Photos/Rope Detail.jpg", 2_660_000),
            ("Photos/Old Jetty.heic", 2_940_000),
            ("Photos/Harbor at Night.jpg", 3_120_000),
            ("Fonts/Atkinson Hyperlegible Regular.ttf", 186_000),
            ("Fonts/Atkinson Hyperlegible Bold.ttf", 191_000),
            ("Fonts/Instrument Serif Italic.ttf", 204_000),
            ("Prototype/Harbor Prototype.app", 48_600_000),
            ("Prototype/Install Helper.pkg", 3_400_000),
            ("Audio/Brand Sting.wav", 5_300_000),
            ("Video/Logo Reveal.mov", 28_700_000),
            ("Earlier Rounds/Old Explorations.7z", 64_200_000),
        ]

        let base = Date(timeIntervalSince1970: 1_791_000_000)
        let entries = files.enumerated().map { index, file in
            ArchiveEntry(
                path: file.0,
                isFolder: false,
                size: file.1,
                packedSize: Int64(Double(file.1) * EntryKind.infer(fromName: file.0).typicalCompressionRatio),
                modified: base.addingTimeInterval(Double(index) * -86_400 * 1.7)
            )
        }

        return Archive(
            name: name,
            format: ArchiveFormat.infer(fromName: name) ?? .zip,
            files: entries,
            checkup: [
                CheckupFinding(
                    severity: .caution,
                    title: String(localized: "Harbor Prototype.app isn’t notarized"),
                    detail: String(localized: "macOS will ask before opening it. Only run it if you trust whoever sent this.")
                ),
                CheckupFinding(
                    severity: .handled,
                    title: String(localized: "1 path tried to leave the folder"),
                    detail: String(localized: "“../../.zshrc” will be kept inside the destination folder instead.")
                ),
                CheckupFinding(
                    severity: .info,
                    title: String(localized: "14 macOS helper files"),
                    detail: String(localized: "While “Leave out system files” is on, extracting skips files like “.DS_Store” and “._”. To keep one, show helper items from the View menu and select it.")
                ),
                CheckupFinding(
                    severity: .fine,
                    title: String(localized: "Names and sizes look normal"),
                    detail: String(localized: "Nothing expands unusually and no names collide.")
                ),
            ]
        )
    }

    /// What's inside "Earlier Rounds/Old Explorations.7z", for the demo that searches into it.
    static let oldExplorations: [ArchiveEntry] = ([
        ("Round 1/Wordmark Ideas.pdf", 2_400_000), ("Round 2/Wordmark Draft.svg", 31_000),
        ("Round 2/Mark Sketches.png", 880_000), ("Notes.txt", 2_000),
    ] as [(String, Int64)]).map { ArchiveEntry(path: $0.0, isFolder: false, size: $0.1, packedSize: $0.1 / 2, modified: Date(timeIntervalSince1970: 1_700_000_000)) }

    /// Files that show off the Pack sentence's compatibility report.
    static let packCandidates: [PackFile] = [
        PackFile(path: "Q3 Report: Final.pdf", size: 2_400_000),
        PackFile(path: "Cafe\u{301} Menu.pdf", size: 880_000),          // decomposed é, as macOS stores it
        PackFile(path: "Photos/Pier at Dawn.jpg", size: 4_210_000),
        PackFile(path: "Photos/Lighthouse.jpg", size: 3_870_000),
        PackFile(path: "Photos/.DS_Store", size: 6_148),
        PackFile(path: "Photos/._Lighthouse.jpg", size: 4_096),
        PackFile(path: "Notes/aux.txt", size: 1_200),
        PackFile(path: "Notes/To do.", size: 900),
        PackFile(path: "Budget.numbers", size: 412_000),
        PackFile(path: ".DS_Store", size: 8_196),
        PackFile(path: "Slides/Kickoff.key", size: 18_900_000),
        PackFile(path: "Slides/Icon\r", size: 0),
    ]
}
