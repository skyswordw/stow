import AppKit
import SwiftUI
import Testing
@testable import Stow

@Suite("Sidebar layout")
@MainActor
struct SidebarLayoutTests {
    /// The sample archive with font sizes that made the card read "188.6 MB" and "157.7 MB packed":
    /// with these the browser window crashed on launch (`-StowScene list`, `fonts`, `search`).
    /// The three fonts are picked by folder, in path order, so renaming them doesn't quietly undo this.
    private static func unluckyTotals() -> (archive: Archive, overridden: Int) {
        let sample = SampleArchive.make()
        let fonts = sample.files.map(\.path).filter { $0.hasPrefix("Fonts/") }.sorted()
        let sizes = Dictionary(uniqueKeysWithValues: zip(fonts, [54_348, 55_256, 71_592] as [Int64]))
        let files = sample.files.map { file in
            guard let size = sizes[file.path] else { return file }
            let ratio = EntryKind.infer(fromName: file.path).typicalCompressionRatio
            return ArchiveEntry(path: file.path, isFolder: false, size: size,
                                packedSize: Int64(Double(size) * ratio), modified: file.modified)
        }
        return (Archive(name: sample.name, format: sample.format, files: files, checkup: sample.checkup), sizes.count)
    }

    /// SwiftUI reads a split column's minimum size from a zero proposal. Measured at that width the
    /// archive card wrapped its captions a few characters per line and asked for ~690 pt of height,
    /// and with these totals the window then looped on Update Constraints until AppKit threw.
    @Test func columnMinimumIsMeasuredAtTheColumnsMinimumWidth() {
        let (archive, overridden) = Self.unluckyTotals()
        #expect(overridden == 3, "The sample should have three fonts to resize; it has \(overridden)")
        let column = NSHostingController(rootView: SidebarView(model: BrowserModel(archive: archive)).sidebarColumnWidth())
        let minimum = column.sizeThatFits(in: .zero)
        #expect(minimum.width >= SidebarView.minWidth)
        #expect(minimum.height < 400, "The sidebar's minimum height is \(minimum.height) pt; the card is being measured too narrow")
    }
}
