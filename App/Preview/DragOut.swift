import AppKit
import UniformTypeIdentifiers

/// Drag entries out of the browser into Finder (or any app that takes files). Each item is an
/// `NSFilePromiseProvider`: nothing is extracted while dragging; when it's dropped, the receiver
/// names a folder and the entry is extracted there through the usual engine → staging → no-clobber
/// path, with progress in the Next Steps capsule.
///
/// Two ways in. The list and Glance are SwiftUI tables, which are `NSOutlineView`s with their own
/// gestures: `ArchiveTableDragSource` lets the table start the drag itself, as Finder's list does.
/// The icon grid and columns are plain SwiftUI views, so a local event monitor starts an AppKit
/// session when a press on an entry (tiles and rows report the one under the pointer) turns into
/// a drag; SwiftUI's own drag modifiers hand over one item provider per gesture, not a selection.
final class DragOutController: NSObject, NSFilePromiseProviderDelegate, NSDraggingSource {
    weak var model: BrowserModel?
    /// The entry under the pointer, as tiles and rows report it.
    var hovered: ArchiveEntry.ID?
    /// Browser and Glance retain their view trees across switches and share one model, so each
    /// window remembers which controller it belongs to rather than the controller remembering
    /// only the last window. A reused window can also take a new archive while the old model
    /// finishes its work.
    private static let owners = NSMapTable<NSWindow, DragOutController>.weakToWeakObjects()
    private var monitor: Any?
    private var press: (point: NSPoint, entry: ArchiveEntry.ID, windowNumber: Int)?
    private(set) var started = false
    private var transferToken: String?
    private var selectionSnapshot: SelectionSnapshot?

    private struct SelectionSnapshot {
        let token = UUID()
        let ids: Set<ArchiveEntry.ID>
        let level: UUID
        let folder: String
        let query: String
    }

    func install(in window: NSWindow) {
        Self.owners.setObject(self, forKey: window)
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            // Local monitors run on the main thread, inside event dispatch.
            let box = EventBox(event: event)
            return MainActor.assumeIsolated {
                guard let self else { return box }
                return EventBox(event: self.handle(box.event))
            }.event
        }
    }

    isolated deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    func handle(_ event: NSEvent?) -> NSEvent? {
        guard let event else { return nil }
        // AppKit starts a requested session during event dispatch; swallowing the drag events
        // that follow would hold it back until mouse-up.
        if started { return event }
        if let entry = dragCandidate(for: event) { _ = beginDrag(from: entry, event: event) }
        return event
    }

    /// Follows a press through the drag threshold. Events from another document never turn
    /// this document's press into a drag, and tables start their own drags.
    func dragCandidate(for event: NSEvent) -> ArchiveEntry.ID? {
        guard let window = event.window, Self.owners.object(forKey: window) === self, model?.archive.source != nil else {
            if event.type == .leftMouseDown { press = nil }
            return nil
        }
        switch event.type {
        case .leftMouseDown:
            selectionSnapshot = nil
            started = false
            press = model?.renamingPath == nil && !Self.isOverArchiveTable(event.locationInWindow, in: window)
                ? hovered.map { (event.locationInWindow, $0, window.windowNumber) } : nil
        case .leftMouseDragged:
            guard let press, !started, press.windowNumber == window.windowNumber else { return nil }
            let moved = hypot(event.locationInWindow.x - press.point.x, event.locationInWindow.y - press.point.y)
            return moved > 4 ? press.entry : nil
        default:
            press = nil
            started = false
        }
        return nil
    }

    /// A press on a list or Glance table: the table decides between a drag and a selection.
    private static func isOverArchiveTable(_ point: NSPoint, in window: NSWindow) -> Bool {
        // The frame view has no superview, so window coordinates are its hit-test coordinates.
        var view = (window.contentView?.superview ?? window.contentView)?.hitTest(point)
        while let current = view {
            if let table = current as? NSTableView { return table.dataSource is ArchiveTableDragSource }
            view = current.superview
        }
        return false
    }

    func prepareDrag(from id: ArchiveEntry.ID) -> [ArchiveEntry] {
        guard let model else { return [] }
        if !model.selection.contains(id) { model.select([id]) }
        let entries = Self.draggable(model.selectedEntries)
        // Results inside other archives aren't in this one to drag out.
        guard !entries.isEmpty else { return [] }
        snapshotSelection()
        started = true
        dragging = entries.map(\.path)
        return entries
    }

    /// Entries inside a folder that's also dragged go with the folder.
    static func draggable(_ entries: [ArchiveEntry]) -> [ArchiveEntry] {
        let folders = entries.filter(\.isFolder).map { $0.path + "/" }
        return entries.filter { entry in !folders.contains { entry.path.hasPrefix($0) } }
    }

    /// SwiftUI can write an empty or narrowed selection back while a drag starts (#171).
    private func snapshotSelection() {
        guard let model else { return }
        selectionSnapshot = SelectionSnapshot(ids: model.selection, level: model.level.id,
                                              folder: model.folder, query: model.query)
        let token = selectionSnapshot?.token
        DispatchQueue.main.async { [weak self] in self?.restoreSelection(token: token) }
    }

    func promise(for entry: ArchiveEntry, token: String?) -> ArchiveDragPromise {
        let provider = ArchiveDragPromise(fileType: Self.dragType(entry).identifier, delegate: self)
        provider.transferToken = token
        provider.userInfo = entry.path
        return provider
    }

    static func dragType(_ entry: ArchiveEntry) -> UTType {
        entry.isNavigable ? .folder : entry.contentType
    }

    /// The row's own icon, as the list draws it: a thumbnail where it has one, else the type's.
    func icon(for entry: ArchiveEntry) -> NSImage {
        if let model, RowIcon.showsThumbnail(entry),
           let thumbnail = model.previews.cachedThumbnail(for: entry, in: model.archive, side: 96) { return thumbnail }
        return NSWorkspace.shared.icon(for: Self.dragType(entry))
    }

    private func beginDrag(from id: ArchiveEntry.ID, event: NSEvent) -> Bool {
        guard !started, let model, let view = event.window?.contentView else { return false }
        let entries = prepareDrag(from: id)
        guard !entries.isEmpty else { return false }
        let point = view.convert(event.locationInWindow, from: nil)
        transferToken = ArchiveTransfer.register(source: model, entries: entries)
        // Columns are rows, so they travel as the list's do: icon and name, one per line. The
        // grid's tiles travel as Finder's icon view's: a pile of their pictures.
        let asRows = model.viewMode == .columns
        let items = entries.enumerated().map { index, entry in
            let item = NSDraggingItem(pasteboardWriter: promise(for: entry, token: transferToken))
            if asRows {
                DragImage.dress(item, icon: icon(for: entry), name: entry.name, maxWidth: 280,
                                rowHeight: 20, at: NSPoint(x: point.x - 9, y: point.y - 10), appearance: view.effectiveAppearance)
                return item
            }
            let picture = model.previews.cachedThumbnail(for: entry, in: model.archive, side: 96)
                ?? NSWorkspace.shared.icon(for: Self.dragType(entry))
            let offset = CGFloat(min(index, 4)) * 6
            item.setDraggingFrame(NSRect(x: point.x - 32 + offset, y: point.y - 32 - offset, width: 64, height: 64),
                                  contents: picture)
            return item
        }
        model.quickLook.close()
        DragActivity.began(self)
        let session = view.beginDraggingSession(with: items, event: event, source: self)
        session.draggingFormation = asRows ? .list : .pile
        return true
    }

    /// A table started dragging these rows (see `ArchiveTableDragSource`).
    func tableDragBegan(_ entries: [ArchiveEntry], token: String, on pasteboard: NSPasteboard) {
        guard let model else { return }
        started = true
        press = nil
        DragActivity.began(self)
        snapshotSelection()
        transferToken = token
        ArchiveTransfer.register(token: token, source: model, entries: entries)
        ArchiveTransfer.began(token: token, on: pasteboard)
        dragging = entries.map(\.path)
        model.quickLook.close()
        onBegin?(dragging)
    }

    private func restoreSelection(token: UUID?) {
        guard let snapshot = selectionSnapshot, snapshot.token == token, let model,
              model.level.id == snapshot.level, model.folder == snapshot.folder,
              model.query == snapshot.query else { return }
        let ids = snapshot.ids.filter { model.archive.entry(at: $0) != nil }
        if model.selection != ids { model.select(ids) }
    }

    func finishDrag(pasteboard: NSPasteboard?, operation: NSDragOperation) {
        DragActivity.ended(self)
        ArchiveTransfer.finish(transferToken)
        transferToken = nil
        if operation.isEmpty { pasteboard?.clearContents() }
        let token = selectionSnapshot?.token
        restoreSelection(token: token)
        dragging = []
        press = nil
        started = false
        DispatchQueue.main.async { [weak self] in
            guard let self, self.selectionSnapshot?.token == token else { return }
            self.restoreSelection(token: token)
            self.selectionSnapshot = nil
        }
    }

    /// Design review and verification runs: told what a drag carries when it starts.
    var onBegin: (([String]) -> Void)?

    // MARK: - NSDraggingSource

    private var dragging: [String] = []

    nonisolated func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        nonisolated(unsafe) let session = session
        MainActor.assumeIsolated {
            ArchiveTransfer.began(token: transferToken, on: session.draggingPasteboard)
            onBegin?(dragging)
        }
    }

    nonisolated func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint,
                                     operation: NSDragOperation) {
        // AppKit ends the session on the main thread. Mark the session unsafe so we can read its
        // MainActor pasteboard inside assumeIsolated without RegionIsolation on the capture.
        nonisolated(unsafe) let session = session
        let endedOperation = operation
        MainActor.assumeIsolated {
            finishDrag(pasteboard: session.draggingPasteboard, operation: endedOperation)
        }
    }

    nonisolated func draggingSession(_ session: NSDraggingSession,
                                     sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    // MARK: - NSFilePromiseProviderDelegate

    nonisolated func filePromiseProvider(_ provider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        ((provider.userInfo as? String ?? "") as NSString).lastPathComponent
    }

    nonisolated func filePromiseProvider(_ provider: NSFilePromiseProvider, writePromiseTo url: URL,
                                         completionHandler: @escaping @Sendable ((any Error)?) -> Void) {
        let path = provider.userInfo as? String ?? ""
        Task { @MainActor [weak self] in
            guard let model = self?.model, let entry = model.archive.entry(at: path) else {
                completionHandler(EngineError(.failed, String(localized: "That item is no longer in the archive.")))
                return
            }
            do {
                _ = try await model.extractForDrop([entry], into: url.deletingLastPathComponent())
                completionHandler(nil)
            } catch {
                completionHandler(error)
            }
        }
    }
}

/// Whether files are being dragged over Stow's windows, or were a moment ago. Hover previews
/// wait for the pointer to settle after a drag: a drop isn't a look.
enum DragActivity {
    private static var lastSeen: ContinuousClock.Instant?
    /// Stow's own sessions in flight, by their source.
    private static var sessions: Set<ObjectIdentifier> = []
    /// How long after a drag a hover still belongs to it.
    static let settle = Duration.milliseconds(600)

    static func began(_ source: AnyObject) { sessions.insert(ObjectIdentifier(source)); touch() }
    static func ended(_ source: AnyObject) { sessions.remove(ObjectIdentifier(source)); touch() }
    /// A drag from elsewhere passed over a window or dropped on it.
    static func touch() { lastSeen = .now }

    static var isRecent: Bool {
        !sessions.isEmpty || lastSeen.map { ContinuousClock.now - $0 < settle } ?? false
    }
}

/// Events never leave the main thread here; the box only gets them through `assumeIsolated`.
private struct EventBox: @unchecked Sendable {
    let event: NSEvent?
}

// MARK: - Tables

/// SwiftUI's `Table` is an `NSOutlineView`. Its own gestures decide, as a press moves, whether
/// the rows are being dragged or the selection extended, and they drag only when the data
/// source hands over a pasteboard writer, which SwiftUI's doesn't. Watching the mouse beside
/// them (#318, #320) raced those gestures, so a second drag could turn into a range selection.
///
/// This data source stands in front of SwiftUI's, forwards everything it doesn't answer, and
/// gives the table file promises and drops. Dragging then works as in Finder's list: from a
/// selected row the whole selection goes, from any other row just that row; the table draws the
/// drag, slides it back when it's refused, and shows where a drop will land — a folder's row,
/// or the whole list for the folder on show.
final class ArchiveTableDragSource: NSObject, NSOutlineViewDataSource {
    weak var model: BrowserModel?
    /// SwiftUI's coordinator. Held strongly so forwarding never reaches a freed object; given
    /// back when the table leaves its window.
    nonisolated(unsafe) private let original: NSObject
    private weak var table: NSOutlineView?
    /// One per gesture: the promises carry it before the session says it has begun.
    private var token = UUID().uuidString

    private init(original: NSObject, model: BrowserModel, table: NSOutlineView) {
        self.original = original
        self.model = model
        self.table = table
    }

    nonisolated(unsafe) private static var key: UInt8 = 0

    /// Puts the drag source in front of the table's data source, or points it at a new model.
    static func install(on table: NSTableView, model: BrowserModel) {
        guard let outline = table as? NSOutlineView else { return }
        if let current = outline.dataSource as? ArchiveTableDragSource {
            current.model = model
            return
        }
        guard let original = outline.dataSource as? NSObject else { return }
        let source = ArchiveTableDragSource(original: original, model: model, table: outline)
        objc_setAssociatedObject(outline, &key, source, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        outline.dataSource = source
        outline.setDraggingSourceOperationMask(.copy, forLocal: true)
        outline.setDraggingSourceOperationMask(.copy, forLocal: false)
        outline.registerForDraggedTypes([.fileURL, NSPasteboard.PasteboardType(ArchiveTransfer.typeIdentifier)])
        outline.draggingDestinationFeedbackStyle = .regular
    }

    /// Hands SwiftUI's data source back, so nothing outlives the table.
    static func uninstall(from table: NSTableView) {
        guard let outline = table as? NSOutlineView,
              let source = outline.dataSource as? ArchiveTableDragSource else { return }
        outline.dataSource = source.original as? NSOutlineViewDataSource
        outline.unregisterDraggedTypes()
        objc_setAssociatedObject(outline, &key, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    // MARK: Forwarding

    // The runtime asks these from wherever it dispatches; both only read the immutable `original`.
    nonisolated override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || original.responds(to: selector)
    }

    nonisolated override func forwardingTarget(for selector: Selector!) -> Any? {
        return original.responds(to: selector) ? original : nil
    }

    // MARK: Rows

    /// The entry a row shows, while the table and the model agree on the rows.
    private func entry(for item: Any?, in outline: NSOutlineView) -> ArchiveEntry? {
        guard let item, let model else { return nil }
        return entry(atRow: outline.row(forItem: item), in: outline, model: model)
    }

    private func entry(atRow row: Int, in outline: NSOutlineView, model: BrowserModel) -> ArchiveEntry? {
        guard outline.numberOfRows == model.visibleEntries.count,
              model.visibleEntries.indices.contains(row) else { return nil }
        return model.visibleEntries[row]
    }

    // MARK: Dragging out

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> (any NSPasteboardWriting)? {
        guard let model, model.archive.source != nil, model.renamingPath == nil,
              let entry = entry(for: item, in: outlineView), model.archive.entry(at: entry.id) != nil else { return nil }
        // Inside a folder that's also selected: the folder brings it.
        if model.selection.contains(entry.id), model.selectedEntries.contains(where: {
            $0.isFolder && entry.path.hasPrefix($0.path + "/")
        }) { return nil }
        return model.dragOut.promise(for: entry, token: token)
    }

    func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession,
                     willBeginAt screenPoint: NSPoint, forItems draggedItems: [Any]) {
        guard let model else { return }
        let rows = draggedItems.compactMap { item -> (row: Int, entry: ArchiveEntry)? in
            let row = outlineView.row(forItem: item)
            return self.entry(atRow: row, in: outlineView, model: model).map { (row, $0) }
        }
        let entries = DragOutController.draggable(rows.map(\.entry))
        // A drag from a row outside the selection is that row alone, and it says so.
        if let first = rows.first, rows.count == 1, !model.selection.contains(first.entry.id) {
            model.select([first.entry.id])
        }
        model.dragOut.tableDragBegan(entries, token: token, on: session.draggingPasteboard)
        let dragged = rows.filter { row in entries.contains { $0.id == row.entry.id } }
        // One line per item under the pointer, so every name stays readable; the system's
        // default piles them and the names print over each other.
        session.draggingFormation = .list
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.enumerateDraggingItems(options: [.clearNonenumeratedImages], for: outlineView,
                                       classes: [NSPasteboardItem.self], searchOptions: [:]) { item, index, _ in
            guard dragged.indices.contains(index) else { return }
            self.dress(item, as: dragged[index].entry, row: dragged[index].row, in: outlineView)
        }
    }

    func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession,
                     endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        token = UUID().uuidString
        model?.dragOut.finishDrag(pasteboard: session.draggingPasteboard, operation: operation)
    }

    /// Finder's list drag: the row's icon and name, lifted from where they sit in the row. The
    /// other columns stay behind; a selection travels as a list of its names.
    private func dress(_ item: NSDraggingItem, as entry: ArchiveEntry, row: Int, in outline: NSOutlineView) {
        guard let icon = model?.dragOut.icon(for: entry) else { return }
        let cell = outline.frameOfCell(atColumn: 0, row: row)
        DragImage.dress(item, icon: icon, name: entry.name, maxWidth: max(80, cell.width - 34),
                        rowHeight: cell.height, at: NSPoint(x: cell.minX + 6, y: cell.minY),
                        appearance: outline.effectiveAppearance)
    }

    // MARK: Dropping in

    func outlineView(_ outlineView: NSOutlineView, validateDrop info: any NSDraggingInfo,
                     proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        DragActivity.touch()
        guard let model, model.acceptsDrop(from: info.draggingPasteboard) else { return [] }
        // Anywhere on a folder's row is into that folder, as in Finder; anywhere else is the
        // folder on show, and the whole list says so.
        let point = outlineView.convert(info.draggingLocation, from: nil)
        let row = outlineView.row(at: point)
        if let entry = entry(atRow: row, in: outlineView, model: model), entry.isNavigable {
            outlineView.setDropItem(outlineView.item(atRow: row), dropChildIndex: NSOutlineViewDropOnItemIndex)
        } else {
            outlineView.setDropItem(nil, dropChildIndex: NSOutlineViewDropOnItemIndex)
        }
        return .copy
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: any NSDraggingInfo,
                     item: Any?, childIndex index: Int) -> Bool {
        DragActivity.touch()
        guard let model else { return false }
        let folder = entry(for: item, in: outlineView).flatMap { $0.isNavigable ? $0.path : nil } ?? model.folder
        return model.acceptDrop(from: info.draggingPasteboard, into: folder)
    }
}

/// A row's drag image: its icon and name, as Finder's list lifts them.
enum DragImage {
    static let iconSide: CGFloat = 18

    /// `origin` is where the icon's row starts, in the dragging view's coordinates.
    static func dress(_ item: NSDraggingItem, icon: NSImage, name: String, maxWidth: CGFloat,
                      rowHeight: CGFloat, at origin: NSPoint, appearance: NSAppearance) {
        let label = DragLabel.image(name, maxWidth: maxWidth, appearance: appearance)
        let frame = NSRect(x: origin.x, y: origin.y, width: iconSide + Space.s + label.size.width, height: rowHeight)
        item.draggingFrame = frame
        item.imageComponentsProvider = {
            let iconComponent = NSDraggingImageComponent(key: .icon)
            iconComponent.contents = icon
            iconComponent.frame = NSRect(x: 0, y: (frame.height - iconSide) / 2, width: iconSide, height: iconSide)
            let labelComponent = NSDraggingImageComponent(key: .label)
            labelComponent.contents = label
            labelComponent.frame = NSRect(x: iconSide + Space.s, y: (frame.height - label.size.height) / 2,
                                          width: label.size.width, height: label.size.height)
            return [iconComponent, labelComponent]
        }
    }
}

/// A drag image's name: the system font in the label colour, cut short in the middle.
enum DragLabel {
    static func image(_ name: String, maxWidth: CGFloat, appearance: NSAppearance) -> NSImage {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingMiddle
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: style,
        ]
        let text = NSAttributedString(string: name, attributes: attributes)
        let size = NSSize(width: min(maxWidth, ceil(text.size().width)), height: ceil(text.size().height))
        // Drawn when AppKit renders the drag, in the list's light or dark, not whatever is current then.
        return NSImage(size: size, flipped: false) { rect in
            appearance.performAsCurrentDrawingAppearance {
                text.draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            }
            return true
        }
    }
}
