import AppKit
import SwiftUI
import Testing
@testable import Stow

@Suite("Sidebar layout")
@MainActor
struct SidebarLayoutTests {
    /// The sample archive with font sizes that made the card read "188.6 MB" and "157.7 MB packed":
    /// with these the browser window crashed on launch (`-StowScene list`, `fonts`, `search`).
    private static let unluckyTotals: Archive = {
        let sample = SampleArchive.make()
        let sizes: [String: Int64] = ["Fonts/Harbor Sans Regular.otf": 54_348,
                                      "Fonts/Harbor Sans Bold.otf": 55_256,
                                      "Fonts/Harbor Serif Italic.otf": 71_592]
        let files = sample.files.map { file in
            guard let size = sizes[file.path] else { return file }
            let ratio = EntryKind.infer(fromName: file.path).typicalCompressionRatio
            return ArchiveEntry(path: file.path, isFolder: false, size: size,
                                packedSize: Int64(Double(size) * ratio), modified: file.modified)
        }
        return Archive(name: sample.name, format: sample.format, files: files, checkup: sample.checkup)
    }()

    /// SwiftUI reads a split column's minimum size from a zero proposal. Measured at that width the
    /// archive card wrapped its captions a few characters per line and asked for ~690 pt of height,
    /// and with these totals the window then looped on Update Constraints until AppKit threw.
    @Test func columnMinimumIsMeasuredAtTheColumnsMinimumWidth() {
        let column = NSHostingController(rootView: SidebarView(model: BrowserModel(archive: Self.unluckyTotals)).sidebarColumnWidth())
        let minimum = column.sizeThatFits(in: .zero)
        #expect(minimum.width >= SidebarView.minWidth)
        #expect(minimum.height < 400, "The sidebar's minimum height is \(minimum.height) pt; the card is being measured too narrow")
    }
}
