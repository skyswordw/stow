import AppKit
import Testing
@testable import Stow

@MainActor
@Suite("Drag-out lifecycle", .serialized)
struct DragOutTests {
    @Test func restoresMultiSelectionAfterTableClearsOrNarrowsIt() async throws {
        let model = makeModel()
        model.select(["alpha.txt", "beta.txt"])
        #expect(model.dragOut.prepareDrag(from: "alpha.txt").map(\.path) == ["alpha.txt", "beta.txt"])
        model.selection = []
        await nextTurn()
        #expect(model.selection == ["alpha.txt", "beta.txt"])
        model.selection = ["alpha.txt"]
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        model.dragOut.finishDrag(pasteboard: pasteboard, operation: [])
        #expect(model.selection == ["alpha.txt", "beta.txt"])
        model.selection = []
        await nextTurn()
        #expect(model.selection == ["alpha.txt", "beta.txt"])
    }

    @Test func draggingAnUnselectedRowSelectsOnlyThatRow() async {
        let model = makeModel()
        model.select(["alpha.txt"])
        #expect(model.dragOut.prepareDrag(from: "beta.txt").map(\.path) == ["beta.txt"])
        model.selection = []
        await nextTurn()
        #expect(model.selection == ["beta.txt"])
    }

    @Test func cancelledDragClearsOnlyItsPasteboardAndResetsEventRouting() throws {
        let model = makeModel()
        let pasteboard = NSPasteboard.withUniqueName()
        let other = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally(); other.releaseGlobally() }
        let provider = NSFilePromiseProvider(fileType: "public.plain-text", delegate: model.dragOut)
        provider.userInfo = "alpha.txt"
        #expect(pasteboard.writeObjects([provider]))
        other.setString("untouched", forType: .string)
        _ = model.dragOut.prepareDrag(from: "alpha.txt")
        let event = try #require(NSEvent.mouseEvent(with: .leftMouseDragged, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1))
        #expect(model.dragOut.handle(event) === event)
        model.dragOut.finishDrag(pasteboard: pasteboard, operation: [])
        #expect(pasteboard.pasteboardItems?.isEmpty != false)
        #expect(other.string(forType: .string) == "untouched")
        #expect(model.dragOut.handle(event) === event)
    }

    @Test func successfulDropKeepsPromisesForAnAsynchronousReceiver() {
        let model = makeModel()
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let provider = NSFilePromiseProvider(fileType: "public.plain-text", delegate: model.dragOut)
        provider.userInfo = "alpha.txt"
        #expect(pasteboard.writeObjects([provider]))
        let changeCount = pasteboard.changeCount
        _ = model.dragOut.prepareDrag(from: "alpha.txt")
        model.dragOut.finishDrag(pasteboard: pasteboard, operation: .copy)
        #expect(pasteboard.changeCount == changeCount)
        #expect(pasteboard.pasteboardItems?.isEmpty == false)
    }

    @Test func aNewDragSupersedesQueuedRestoration() async {
        let model = makeModel()
        _ = model.dragOut.prepareDrag(from: "alpha.txt")
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        model.dragOut.finishDrag(pasteboard: pasteboard, operation: [])
        _ = model.dragOut.prepareDrag(from: "beta.txt")
        model.selection = []
        await nextTurn()
        #expect(model.selection == ["beta.txt"])
    }

    @Test func navigationDoesNotRestoreSelectionFromAnotherFolder() async {
        let model = makeModel()
        _ = model.dragOut.prepareDrag(from: "alpha.txt")
        model.navigate(to: "Docs")
        await nextTurn()
        #expect(model.selection.isEmpty)
    }

    @Test func finishedDragDoesNotOverrideLaterSelection() async {
        let model = makeModel()
        _ = model.dragOut.prepareDrag(from: "alpha.txt")
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        model.dragOut.finishDrag(pasteboard: pasteboard, operation: [])
        await nextTurn()
        model.select(["beta.txt"])
        await nextTurn()
        #expect(model.selection == ["beta.txt"])
    }

    @Test func retainedBrowserAndGlanceBothRouteDragEvents() throws {
        let model = sourceModel()
        let browser = NSWindow(), glance = NSWindow()
        model.dragOut.install(in: browser)
        model.dragOut.install(in: glance)
        // No reinstallation or new view attachment when either retained window returns.
        for window in [browser, glance, browser, glance] {
            model.dragOut.hovered = "alpha.txt"
            #expect(model.dragOut.dragCandidate(for: try mouse(.leftMouseDown, in: window)) == nil)
            #expect(model.dragOut.dragCandidate(for: try mouse(.leftMouseDragged, in: window, x: 2)) == nil)
            #expect(model.dragOut.dragCandidate(for: try mouse(.leftMouseDragged, in: window, x: 12)) == "alpha.txt")
            _ = model.dragOut.dragCandidate(for: try mouse(.leftMouseUp, in: window, x: 12))
            #expect(model.dragOut.dragCandidate(for: try mouse(.leftMouseDragged, in: window, x: 20)) == nil)
        }
    }

    @Test func anotherWindowCannotContinueOrReuseAPress() throws {
        let model = sourceModel()
        let browser = NSWindow(), glance = NSWindow(), other = NSWindow()
        model.dragOut.install(in: browser)
        model.dragOut.install(in: glance)
        model.dragOut.hovered = "alpha.txt"
        _ = model.dragOut.dragCandidate(for: try mouse(.leftMouseDown, in: browser))
        #expect(model.dragOut.dragCandidate(for: try mouse(.leftMouseDragged, in: glance, x: 12)) == nil)
        #expect(model.dragOut.dragCandidate(for: try mouse(.leftMouseDragged, in: other, x: 12)) == nil)
        _ = model.dragOut.dragCandidate(for: try mouse(.leftMouseDown, in: other))
        #expect(model.dragOut.dragCandidate(for: try mouse(.leftMouseDragged, in: browser, x: 12)) == nil)
    }

    @Test func reusedWindowOnlyRoutesToItsCurrentArchive() throws {
        let old = sourceModel(), current = sourceModel(), window = NSWindow()
        old.dragOut.install(in: window)
        old.dragOut.hovered = "alpha.txt"
        current.dragOut.install(in: window)
        current.dragOut.hovered = "alpha.txt"
        let down = try mouse(.leftMouseDown, in: window)
        let drag = try mouse(.leftMouseDragged, in: window, x: 12)
        _ = old.dragOut.dragCandidate(for: down)
        _ = current.dragOut.dragCandidate(for: down)
        #expect(old.dragOut.dragCandidate(for: drag) == nil)
        #expect(current.dragOut.dragCandidate(for: drag) == "alpha.txt")
    }

    @Test func renamingDoesNotStartAnArchiveDrag() throws {
        let model = sourceModel(), window = NSWindow()
        model.dragOut.install(in: window)
        model.dragOut.hovered = "alpha.txt"
        model.beginRename(try #require(model.archive.entry(at: "alpha.txt")))
        _ = model.dragOut.dragCandidate(for: try mouse(.leftMouseDown, in: window))
        #expect(model.dragOut.dragCandidate(for: try mouse(.leftMouseDragged, in: window, x: 12)) == nil)
    }

    @Test func nativeTablePressResolvesRowWithoutHoverAcrossColumns() throws {
        let model = sourceModel()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 240),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let table = NSTableView(frame: NSRect(x: 0, y: 0, width: 400, height: 240))
        let data = TableRows(count: model.visibleEntries.count)
        table.dataSource = data
        for name in ["Name", "Size"] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(name))
            column.width = 180
            table.addTableColumn(column)
        }
        let scroll = NSScrollView(frame: table.frame)
        scroll.documentView = table
        window.contentView = scroll
        table.reloadData()
        model.dragOut.install(in: window)
        defer { window.contentView = nil }
        // No hover callback has run, as on a direct press after window activation.
        for column in [0, 1] {
            model.dragOut.hovered = nil
            let rect = table.frameOfCell(atColumn: column, row: 0)
            let point = table.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil)
            _ = model.dragOut.dragCandidate(for: try mouse(.leftMouseDown, in: window, x: point.x, y: point.y))
            #expect(model.dragOut.dragCandidate(for: try mouse(.leftMouseDragged, in: window,
                x: point.x + 12, y: point.y)) == model.visibleEntries[0].id)
        }
        // A stale hover from another row cannot override the actual pressed row.
        model.dragOut.hovered = "stale.txt"
        let row = table.rect(ofRow: 0)
        let point = table.convert(NSPoint(x: row.midX, y: row.midY), to: nil)
        _ = model.dragOut.dragCandidate(for: try mouse(.leftMouseDown, in: window, x: point.x, y: point.y))
        #expect(model.dragOut.dragCandidate(for: try mouse(.leftMouseDragged, in: window,
            x: point.x + 12, y: point.y)) == model.visibleEntries[0].id)
        // Empty table space must not drag that stale hover either.
        let blank = scroll.contentView.convert(NSPoint(x: 40, y: 180), to: nil)
        _ = model.dragOut.dragCandidate(for: try mouse(.leftMouseDown, in: window, x: blank.x, y: blank.y))
        #expect(model.dragOut.dragCandidate(for: try mouse(.leftMouseDragged, in: window,
            x: blank.x + 12, y: blank.y)) == nil)
    }

    private final class TableRows: NSObject, NSTableViewDataSource {
        let count: Int
        init(count: Int) { self.count = count }
        func numberOfRows(in tableView: NSTableView) -> Int { count }
        func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? { "Row \(row)" }
    }

    @Test func nativeGestureAttachmentReplacesStaleHostsWithoutChangingTheDataSource() {
        let table = NSTableView(), model = sourceModel()
        let data = TableRows(count: 1)
        table.dataSource = data
        let old = TableDragGesture(), current = TableDragGesture()
        old.attach(table, model: model)
        current.attach(table, model: model)
        current.attach(table, model: model)
        #expect(table.dataSource === data)
        #expect(table.gestureRecognizers.filter { $0 is TableDragGesture }.count == 1)
        #expect(old.view == nil)
        old.detach()
        #expect(current.view === table)
        current.detach()
        #expect(!table.gestureRecognizers.contains { $0 is TableDragGesture })
    }

    @Test func replacingTheArchiveInvalidatesANativePress() throws {
        let first = sourceModel(), second = sourceModel()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 240),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let table = NSTableView(frame: NSRect(x: 0, y: 0, width: 400, height: 240))
        let data = TableRows(count: 1)
        table.dataSource = data
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Name")))
        window.contentView = table
        table.reloadData()
        let gesture = TableDragGesture()
        gesture.attach(table, model: first)
        defer { gesture.detach(); window.contentView = nil }
        let row = table.rect(ofRow: 0)
        let point = table.convert(NSPoint(x: row.midX, y: row.midY), to: nil)
        gesture.mouseDown(with: try mouse(.leftMouseDown, in: window, x: point.x, y: point.y))
        gesture.attach(table, model: second)
        gesture.mouseDragged(with: try mouse(.leftMouseDragged, in: window, x: point.x + 12, y: point.y))
        #expect(first.selection.isEmpty && second.selection.isEmpty)
    }

    @Test func consecutiveNativeDragsDoNotBecomeRangeSelection() async throws {
        let fixture = GestureFixture()
        defer { fixture.close() }
        fixture.select([0])
        for count in 1...3 {
            try fixture.press(row: 0)
            try fixture.move(from: 0, to: 2)
            try await fixture.wait { fixture.starts.count == count }
            #expect(fixture.starts.count == count)
            #expect(fixture.starts.last == ["alpha.txt"])
            #expect(fixture.table.selectedRowIndexes == IndexSet(integer: 0))
            fixture.finish()
            try await fixture.wait { fixture.gesture.state == .possible }
            #expect(fixture.gesture.state == .possible)
        }
        fixture.select([0, 1])
        try fixture.press(row: 1)
        try fixture.move(from: 1, to: 2)
        try await fixture.wait { fixture.starts.count == 4 }
        #expect(fixture.starts.last == ["alpha.txt", "beta.txt"])
        fixture.finish()
        await nextTurn()
    }

    @Test func releasingBeforeTheGestureActionCannotStartALateSession() async throws {
        let fixture = GestureFixture()
        defer { fixture.close() }
        fixture.select([0])
        // Deliver release before AppKit gets to the queued action, rather than an
        // already-running native session (whose mouse-up belongs to AppKit).
        fixture.gesture.mouseDown(with: try fixture.event(.leftMouseDown, row: 0))
        fixture.gesture.mouseDragged(with: try fixture.event(.leftMouseDragged, row: 2, dx: 20))
        fixture.gesture.mouseUp(with: try fixture.event(.leftMouseUp, row: 2, dx: 20))
        NSApp.sendAction(try #require(fixture.gesture.action), to: fixture.gesture.target, from: fixture.gesture)
        await nextTurn()
        #expect(fixture.starts.isEmpty)
    }

    @Test func refusedSessionAllowsTheNextNativeDrag() async throws {
        let fixture = GestureFixture()
        defer { fixture.close() }
        fixture.select([0])
        fixture.acceptsSession = false
        try fixture.press(row: 0)
        try fixture.move(from: 0, to: 2)
        try await fixture.wait { fixture.starts.count == 1 && fixture.gesture.state == .possible }
        #expect(fixture.starts.count == 1)
        #expect(fixture.gesture.state == .possible)
        fixture.acceptsSession = true
        try fixture.press(row: 0)
        try fixture.move(from: 0, to: 2)
        try await fixture.wait { fixture.starts.count == 2 }
        #expect(fixture.starts.count == 2)
        fixture.finish()
        await nextTurn()
    }

    private final class GestureFixture {
        let model = BrowserModel(archive: Archive(listing: ArchiveListing(type: "zip", entries:
            ["alpha.txt", "beta.txt", "gamma.txt"].map { ListedEntry(path: $0, isFolder: false, size: 1) }
        ), url: URL(filePath: "/tmp/Gesture-\(UUID().uuidString).zip")))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 240),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let table = NSTableView(frame: NSRect(x: 0, y: 0, width: 400, height: 240))
        let data = TableRows(count: 3)
        var gesture: TableDragGesture!
        var starts: [[String]] = []
        var acceptsSession = true

        init() {
            table.dataSource = data
            table.allowsMultipleSelection = true
            table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Name")))
            window.contentView = table
            table.reloadData()
            gesture = TableDragGesture { [weak self] id, _, _ in
                guard let self else { return false }
                self.starts.append(self.model.dragOut.prepareDrag(from: id).map(\.id))
                if !self.acceptsSession { self.model.dragOut.finishDrag(pasteboard: nil, operation: []) }
                return self.acceptsSession
            }
            gesture.attach(table, model: model)
            window.makeKeyAndOrderFront(nil)
        }

        func wait(_ predicate: () -> Bool) async throws {
            let deadline = ContinuousClock.now + .seconds(2)
            while !predicate(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
            try #require(predicate())
        }

        func select(_ rows: IndexSet) {
            table.selectRowIndexes(rows, byExtendingSelection: false)
            model.select(Set(rows.map { model.visibleEntries[$0].id }))
        }

        func press(row: Int) throws { try send(.leftMouseDown, row: row) }
        func move(from: Int, to: Int) throws { try send(.leftMouseDragged, row: to, dx: 20) }
        func release(row: Int) throws { try send(.leftMouseUp, row: row, dx: 20) }

        private func send(_ type: NSEvent.EventType, row: Int, dx: CGFloat = 0) throws {
            NSApp.sendEvent(try event(type, row: row, dx: dx))
        }

        func event(_ type: NSEvent.EventType, row: Int, dx: CGFloat = 0) throws -> NSEvent {
            let rect = table.rect(ofRow: row)
            let point = table.convert(NSPoint(x: 30 + dx, y: rect.midY), to: nil)
            return try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1))
        }

        func finish() {
            model.dragOut.finishDrag(pasteboard: nil, operation: .copy)
            gesture.nativeSessionEnded()
        }

        func close() {
            finish()
            gesture.detach()
            window.orderOut(nil)
            window.contentView = nil
        }
    }

    private func sourceModel() -> BrowserModel {
        BrowserModel(archive: Archive(listing: ArchiveListing(type: "zip", entries: [
            ListedEntry(path: "alpha.txt", isFolder: false, size: 1)
        ]), url: URL(filePath: "/tmp/Drag-\(UUID().uuidString).zip")))
    }

    private func mouse(_ type: NSEvent.EventType, in window: NSWindow, x: CGFloat = 0, y: CGFloat = 0) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: y),
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1))
    }

    private func makeModel() -> BrowserModel {
        BrowserModel(archive: Archive(name: "Drag.zip", format: .zip, files:
            ["alpha.txt", "beta.txt", "Docs/note.txt"].map {
                ArchiveEntry(path: $0, isFolder: false, size: 1, packedSize: 1, modified: .now)
            }))
    }

    private func nextTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
