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
    private var press: (point: NSPoint, entry: ArchiveEntry.ID)?
    private var started = false

    func install(in window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            // Local monitors run on the main thread, inside event dispatch.
            let box = EventBox(event: event)
            return MainActor.assumeIsolated { EventBox(event: self?.handle(box.event) ?? box.event) }.event
        }
    }

    isolated deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    private func handle(_ event: NSEvent?) -> NSEvent? {
        guard let event, event.window === window, model?.archive.source != nil else { return event }
        switch event.type {
        case .leftMouseDown:
            press = hovered.map { (event.locationInWindow, $0) }
            started = false
        case .leftMouseDragged:
            guard let press, !started else { return started ? nil : event }
            let moved = hypot(event.locationInWindow.x - press.point.x, event.locationInWindow.y - press.point.y)
            guard moved > 4 else { return event }
            started = true
            beginDrag(from: press.entry, event: event)
            return nil
        default:
            press = nil
            started = false
        }
        return event
    }

    private func beginDrag(from id: ArchiveEntry.ID, event: NSEvent) {
        guard let model, let view = window?.contentView else { return }
        if !model.selection.contains(id) { model.select([id]) }
        let selected = model.selectedEntries
        let folders = selected.filter(\.isFolder).map { $0.path + "/" }
        let entries = selected.filter { entry in !folders.contains { entry.path.hasPrefix($0) } }
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

    // MARK: - NSFilePromiseProviderDelegate

    nonisolated func filePromiseProvider(_ provider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        ((provider.userInfo as? String ?? "") as NSString).lastPathComponent
    }

    nonisolated func filePromiseProvider(_ provider: NSFilePromiseProvider, writePromiseTo url: URL,
                                         completionHandler: @escaping @Sendable ((any Error)?) -> Void) {
        let path = provider.userInfo as? String ?? ""
        Task { @MainActor [weak self] in
            guard let model = self?.model, let entry = model.archive.entry(at: path) else {
                completionHandler(EngineError(.failed, "That item is no longer in the archive."))
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
