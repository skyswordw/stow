import AppKit
import UniformTypeIdentifiers

/// Drag entries out of the browser into Finder (or any app that takes files). Each item is an
/// `NSFilePromiseProvider`: nothing is extracted while dragging; when it's dropped, the receiver
/// names a folder and the entry is extracted there through the usual engine → staging → no-clobber
/// path, with progress in the Next Steps capsule.
///
/// SwiftUI's drag modifiers hand over one item provider per gesture; promises for a whole selection
/// need an AppKit dragging session, so a local event monitor starts one when a press on an entry
/// (tiles and rows report the one under the pointer) turns into a drag.
final class DragOutController: NSObject, NSFilePromiseProviderDelegate, NSDraggingSource {
    weak var model: BrowserModel?
    /// The entry under the pointer, as tiles and rows report it.
    var hovered: ArchiveEntry.ID?
    private weak var window: NSWindow?
    private var monitor: Any?
    private var press: (point: NSPoint, entry: ArchiveEntry.ID, selection: Set<ArchiveEntry.ID>)?
    private var started = false
    private(set) var isDragging = false
    private var preservedSelection: (archive: UUID, folder: String, ids: Set<ArchiveEntry.ID>)?

    func install(in window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            // Local monitors run on the main thread, inside event dispatch.
            let box = EventBox(event: event)
            return MainActor.assumeIsolated {
                guard let self else { return box }
                // Preserve nil: our file-promise session already owns this drag. Starting a
                // second NSTableView gesture can clear selection and orphan the promises.
                return EventBox(event: self.handle(box.event))
            }.event
        }
    }

    isolated deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    private func handle(_ event: NSEvent?) -> NSEvent? {
        guard let event, event.window === window, model?.archive.source != nil else { return event }
        switch event.type {
        case .leftMouseDown:
            let id = tableEntry(at: event) ?? hovered
            press = id.map { (event.locationInWindow, $0, model?.selection ?? []) }
            started = false
        case .leftMouseDragged:
            guard let press, !started else { return started ? nil : event }
            let moved = hypot(event.locationInWindow.x - press.point.x, event.locationInWindow.y - press.point.y)
            guard moved > 4 else { return event }
            started = true
            if let model, press.selection.contains(press.entry) { model.select(press.selection) }
            beginDrag(from: press.entry, event: event)
            return nil
        default:
            finishSelectionPreservation()
            press = nil
            started = false
        }
        return event
    }

    /// A table can begin its native gesture before SwiftUI's hover callback runs. Resolve the
    /// actual pressed row in both full and compact lists instead of depending on hover timing.
    private func tableEntry(at event: NSEvent) -> ArchiveEntry.ID? {
        guard let model, let window else { return nil }
        var view = (window.contentView?.superview ?? window.contentView)?.hitTest(event.locationInWindow)
        while let current = view, !(current is NSTableView) { view = current.superview }
        guard let table = view as? NSTableView, table.numberOfRows == model.visibleEntries.count else { return nil }
        let row = table.row(at: table.convert(event.locationInWindow, from: nil))
        guard model.visibleEntries.indices.contains(row) else { return nil }
        return model.visibleEntries[row].id
    }

    private func beginDrag(from id: ArchiveEntry.ID, event: NSEvent) {
        guard let model, let view = window?.contentView else { return }
        if !model.selection.contains(id) { model.select([id]) }
        let selected = model.selectedEntries
        let folders = selected.filter(\.isFolder).map { $0.path + "/" }
        let entries = selected.filter { entry in !folders.contains { entry.path.hasPrefix($0) } }
        // Results inside other archives aren't in this one to drag out.
        guard !entries.isEmpty else { return }
        let point = view.convert(event.locationInWindow, from: nil)
        let items = entries.enumerated().map { index, entry in
            let type = entry.isFolder && !entry.isPackage ? UTType.folder : entry.contentType
            let provider = NSFilePromiseProvider(fileType: type.identifier, delegate: self)
            provider.userInfo = entry.path
            let item = NSDraggingItem(pasteboardWriter: provider)
            let icon = model.previews.cachedThumbnail(for: entry, in: model.archive, side: 96)
                ?? NSWorkspace.shared.icon(for: type)
            let offset = CGFloat(min(index, 4)) * 6
            item.setDraggingFrame(NSRect(x: point.x - 32 + offset, y: point.y - 32 - offset, width: 64, height: 64),
                                  contents: icon)
            return item
        }
        guard !items.isEmpty else { return }
        dragging = entries.map(\.path)
        preserveSelection()
        model.quickLook.close()
        view.beginDraggingSession(with: items, event: event, source: self)
    }

    /// Design review and verification runs: told what a drag carries when it starts.
    var onBegin: (([String]) -> Void)?

    // MARK: - NSDraggingSource

    private var dragging: [String] = []

    nonisolated func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        MainActor.assumeIsolated { onBegin?(dragging) }
    }

    nonisolated func draggingSession(_ session: NSDraggingSession,
                                     sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }

    nonisolated func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint,
                                     operation: NSDragOperation) {
        let box = DragSessionBox(session: session)
        MainActor.assumeIsolated {
            // Cancelled drags have no receiver. Leaving file promises on the drag pasteboard
            // makes AppKit try to materialize them during termination, which can hang Quit.
            if operation.isEmpty { box.session.draggingPasteboard.clearContents() }
            finishSelectionPreservation()
            started = false
            press = nil
        }
    }

    func preserveSelection() {
        guard let model else { return }
        preservedSelection = (model.archive.id, model.folder, model.selection)
        isDragging = true
    }

    func finishSelectionPreservation() {
        isDragging = false
        defer { preservedSelection = nil }
        guard let model, let saved = preservedSelection,
              model.archive.id == saved.archive, model.folder == saved.folder else { return }
        model.select(saved.ids)
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

/// Events never leave the main thread here; the box only gets them through `assumeIsolated`.
private struct EventBox: @unchecked Sendable {
    let event: NSEvent?
}

/// AppKit invokes this delegate on its event thread; the session never crosses threads.
private nonisolated struct DragSessionBox: @unchecked Sendable {
    let session: NSDraggingSession
}
