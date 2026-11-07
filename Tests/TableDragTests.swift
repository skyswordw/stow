import AppKit
import SwiftUI
import Testing
@testable import Stow

/// The list and Glance tables drag and take drops through `ArchiveTableDragSource`, in front of
/// SwiftUI's own data source (#332).
@MainActor
@Suite("Native table drag and drop", .serialized)
struct TableDragTests {
    private func model() -> BrowserModel {
        BrowserModel(archive: Archive(listing: ArchiveListing(type: "zip", entries: [
            ListedEntry(path: "alpha.txt", isFolder: false, size: 14),
            ListedEntry(path: "beta.txt", isFolder: false, size: 13),
            ListedEntry(path: "Folder/inside.txt", isFolder: false, size: 16)
        ]), url: URL(filePath: "/tmp/TableDrag-\(UUID().uuidString).zip")))
    }

    private final class Hosted {
        let window: NSWindow
        let host: NSView
        init(_ window: NSWindow, _ host: NSView) { self.window = window; self.host = host }
        func close() { window.contentView = nil; window.orderOut(nil) }
    }

    private func glance(_ browser: BrowserModel) -> Hosted {
        let app = AppState()
        app.browser = browser
        app.glance.presentsWindow = false
        app.glance.closeMainWindow = {}
        app.glance.collapse(near: .zero, animated: false)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 560),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: GlanceView(model: browser, glance: app.glance).environment(app))
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        return Hosted(window, host)
    }

    private func waitForTable(in view: NSView, matching browser: BrowserModel) async throws -> NSOutlineView {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            view.layoutSubtreeIfNeeded()
            if let table = find(in: view), table.dataSource is ArchiveTableDragSource,
               table.numberOfRows == browser.visibleEntries.count { return table }
            try await Task.sleep(for: .milliseconds(20))
        }
        let found = find(in: view)
        throw EngineError(.failed, "No table with the drag source: \(String(describing: found.map { type(of: $0) })) \(String(describing: found?.dataSource.map { type(of: $0) })) rows \(found?.numberOfRows ?? -1) vs \(browser.visibleEntries.count)")
    }

    private func find(in view: NSView) -> NSOutlineView? {
        if let table = view as? NSOutlineView { return table }
        return view.subviews.lazy.compactMap(find).first
    }

    private func row(of path: String, in browser: BrowserModel) throws -> Int {
        try #require(browser.visibleEntries.firstIndex { $0.path == path })
    }

    @Test func tableKeepsItsRowsThroughNavigationWithTheDragSourceInFront() async throws {
        let browser = model()
        let hosted = glance(browser)
        defer { hosted.close() }
        var table = try await waitForTable(in: hosted.host, matching: browser)
        #expect(table.numberOfRows == 3)
        browser.navigate(to: "Folder")
        table = try await waitForTable(in: hosted.host, matching: browser)
        #expect(table.numberOfRows == 1)
        browser.navigate(to: "")
        table = try await waitForTable(in: hosted.host, matching: browser)
        #expect(table.numberOfRows == 3)
    }

    @Test func rowsBecomeFilePromisesExceptWhileRenaming() async throws {
        let browser = model()
        let hosted = glance(browser)
        defer { hosted.close() }
        let table = try await waitForTable(in: hosted.host, matching: browser)
        let source = try #require(table.dataSource as? ArchiveTableDragSource)
        let alpha = try #require(table.item(atRow: try row(of: "alpha.txt", in: browser)))
        let promise = try #require(source.outlineView(table, pasteboardWriterForItem: alpha) as? ArchiveDragPromise)
        #expect(promise.userInfo as? String == "alpha.txt")
        #expect(promise.transferToken != nil)
        let folder = try #require(table.item(atRow: try row(of: "Folder", in: browser)))
        let folderPromise = try #require(source.outlineView(table, pasteboardWriterForItem: folder) as? ArchiveDragPromise)
        #expect(folderPromise.fileType == "public.folder")
        browser.beginRename(try #require(browser.archive.entry(at: "beta.txt")))
        #expect(source.outlineView(table, pasteboardWriterForItem: alpha) == nil)
    }

    @Test func leavingTheWindowGivesSwiftUIItsDataSourceBack() async throws {
        let browser = model()
        let hosted = glance(browser)
        let table = try await waitForTable(in: hosted.host, matching: browser)
        hosted.close()
        #expect(!(table.dataSource is ArchiveTableDragSource))
    }

    @Test func anArchiveRefusesItsOwnItemsAndTakesAnothers() throws {
        let source = model(), other = model()
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally(); ArchiveTransfer.finish(nil) }
        let entry = try #require(source.archive.entry(at: "alpha.txt"))
        let token = UUID().uuidString
        ArchiveTransfer.register(token: token, source: source, entries: [entry])
        let promise = source.dragOut.promise(for: entry, token: token)
        #expect(pasteboard.writeObjects([promise]))
        ArchiveTransfer.began(token: token, on: pasteboard)
        #expect(!source.acceptsDrop())
        #expect(!source.acceptsDrop(from: pasteboard))
        #expect(other.acceptsDrop())
        #expect(other.acceptsDrop(from: pasteboard))
        ArchiveTransfer.finish(token)
        // Once the gesture is over its token is stale: nobody takes it.
        #expect(!other.acceptsDrop(from: pasteboard))
    }

    @Test func droppedFilesGoIntoTheFolderAsOneUndoStep() throws {
        let browser = model()
        let directory = FileManager.default.temporaryDirectory.appending(path: "TableDrop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = ["one.txt", "two.txt"].map { directory.appending(path: $0) }
        for file in files { try Data("x".utf8).write(to: file) }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        #expect(pasteboard.writeObjects(files as [NSURL]))
        #expect(browser.acceptsDrop(from: pasteboard))
        #expect(browser.acceptDrop(from: pasteboard, into: "Folder"))
        #expect(browser.archive.entry(at: "Folder/one.txt") != nil)
        #expect(browser.archive.entry(at: "Folder/two.txt") != nil)
        browser.editingUndoManager.undo()
        #expect(browser.archive.entry(at: "Folder/one.txt") == nil)
        #expect(browser.archive.entry(at: "Folder/two.txt") == nil)
    }
}
