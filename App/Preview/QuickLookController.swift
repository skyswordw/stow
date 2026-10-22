import AppKit
import Quartz

/// Drives the system Quick Look panel for a browser window. It sits in the window's responder
/// chain, so the panel finds it as its controller; items are extracted on demand. Until a file
/// arrives — or when there's none to show (a sample entry without a bundled file, a locked archive,
/// a failed extraction) — the panel shows a small page with the entry's icon, name and why, never
/// an empty file: Quick Look draws a zero-byte image or text file as a blank page.
///
/// With one item selected, the arrow keys move the browser's selection and the panel follows — like
/// Finder. With several selected, the panel pages through them itself.
final class QuickLookController: NSResponder, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    weak var model: BrowserModel?
    private weak var window: NSWindow?
    private var items: [Item] = []
    private var loads: Task<Void, Never>?
    private var pinned: [URL] = []

    nonisolated final class Item: NSObject, QLPreviewItem, @unchecked Sendable {
        let entry: ArchiveEntry
        var url: URL?
        /// Showing a status page while the real file is extracted.
        var isPending: Bool
        init(entry: ArchiveEntry, url: URL?, isPending: Bool = false) {
            self.entry = entry
            self.url = url
            self.isPending = isPending
        }
        var previewItemURL: URL! { url }
        var previewItemTitle: String! { entry.name }
    }

    /// Joins the window's responder chain (once). Glance and the full window share one browser, so
    /// moving to another window first leaves the previous one's chain as it was.
    func attach(to window: NSWindow) {
        guard self.window !== window else { return }
        if let previous = self.window, previous.nextResponder === self { previous.nextResponder = nextResponder }
        self.window = window
        nextResponder = window.nextResponder
        window.nextResponder = self
    }

    private var panel: QLPreviewPanel? { QLPreviewPanel.shared() }

    var isVisible: Bool {
        QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible
            && QLPreviewPanel.shared().dataSource === self
    }

    /// The entries shown: the selection in on-screen order, files and packages (folders show as a folder).
    var entries: [Item] { items }

    func show() {
        reload()
        guard !items.isEmpty, let panel else { return }
        if panel.dataSource !== self {
            panel.dataSource = self
            panel.delegate = self
        }
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData()
    }

    func close() {
        guard isVisible else { return }
        panel?.orderOut(nil)
    }

    /// The browser's selection changed while the panel is open.
    func selectionChanged() {
        guard isVisible else { return }
        reload()
        panel?.reloadData()
    }

    /// Rebuilds the items from the browser's selection and starts extracting what isn't on disk yet.
    func reload() {
        guard let model else { return }
        loads?.cancel()
        pinned.forEach { model.previews.cache.unpin($0) }
        pinned = []
        let order = Dictionary(model.visibleEntries.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        let selected = model.selectedEntries.sorted { (order[$0.id] ?? .max, $0.path) < (order[$1.id] ?? .max, $1.path) }
        let archive = model.archive
        let cache = model.previews.cache
        items = selected.map { entry in
            if let url = cache.cachedFile(for: entry, in: archive) { return Item(entry: entry, url: url) }
            if entry.isNavigable { return Item(entry: entry, url: Self.folderPlaceholder(for: entry)) }
            // The sample archive is only a listing: its real files are in the app (Resources/Sample),
            // and an entry without one says so rather than opening blank.
            if archive.source == nil {
                return Item(entry: entry, url: SampleContent.previewFile(for: entry)
                    ?? Self.statusPage(for: entry, status: String(localized: "This sample file has no content to preview.")))
            }
            return Item(entry: entry, url: Self.statusPage(for: entry, status: String(localized: "Extracting…")), isPending: true)
        }
        let wanted = items.filter(\.isPending)
        guard !wanted.isEmpty else { return }
        loads = Task { [weak self, weak model] in
            // The one being looked at first, then the rest.
            for item in wanted {
                guard let model, !Task.isCancelled else { return }
                let url: URL
                do throws(EngineError) {
                    url = try await model.previews.file(for: item.entry, in: archive)
                } catch {
                    guard !Task.isCancelled, let self else { return }
                    item.url = Self.statusPage(for: item.entry, status: Self.message(for: error))
                    item.isPending = false
                    if panel?.currentPreviewItem === item { panel?.refreshCurrentPreviewItem() }
                    continue
                }
                guard !Task.isCancelled, let self else { return }
                model.previews.cache.pin(url)
                pinned.append(url)
                item.url = url
                item.isPending = false
                if panel?.currentPreviewItem === item { panel?.refreshCurrentPreviewItem() }
            }
        }
    }

    static func message(for error: EngineError) -> String {
        error.failure == .passwordRequired || error.failure == .wrongPassword
            ? String(localized: "Locked — needs the archive’s password") : error.message
    }

    // MARK: - Placeholders

    private static let placeholders = FileManager.default.temporaryDirectory
        .appending(path: "Previews/Placeholders", directoryHint: .isDirectory)

    /// An empty folder with the entry's name: Quick Look shows a folder's icon and name.
    private static func folderPlaceholder(for entry: ArchiveEntry) -> URL {
        let folder = placeholders.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let url = folder.appending(path: entry.name, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A page Quick Look can draw: the entry's icon, name, kind and size, and `status`. The panel's
    /// title is still the entry's name (`previewItemTitle`).
    static func statusPage(for entry: ArchiveEntry, status: String) -> URL {
        let folder = placeholders.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let url = folder.appending(path: "Preview.html")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let icon = NSWorkspace.shared.icon(for: entry.contentType)
        icon.size = NSSize(width: 128, height: 128)
        let png = icon.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) }
        try? Data(statusHTML(name: entry.name, detail: "\(entry.kindDescription) · \(entry.size.bytes)",
                             status: status, iconPNG: png).utf8).write(to: url)
        return url
    }

    static func statusHTML(name: String, detail: String, status: String, iconPNG: Data?) -> String {
        func escaped(_ text: String) -> String {
            text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        }
        let image = iconPNG.map { "<img src=\"data:image/png;base64,\($0.base64EncodedString())\" width=\"128\" height=\"128\" alt=\"\">" } ?? ""
        return """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"><meta name="color-scheme" content="light dark">
        <style>
        html, body { height: 100%; margin: 0; }
        body { display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 6px;
               font: 13px -apple-system, system-ui, sans-serif; color: CanvasText; background: Canvas; text-align: center; padding: 0 24px; }
        .name { font-weight: 600; font-size: 15px; word-break: break-word; }
        .detail, .status { color: GrayText; }
        </style></head>
        <body>\(image)<div class="name">\(escaped(name))</div><div class="detail">\(escaped(detail))</div><div class="status">\(escaped(status))</div></body></html>
        """
    }

    // MARK: - Panel control (found through the responder chain)

    nonisolated override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    nonisolated override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        let panel = PanelBox(panel: panel)
        MainActor.assumeIsolated {
            panel.panel?.dataSource = self
            panel.panel?.delegate = self
        }
    }

    nonisolated override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        let panel = PanelBox(panel: panel)
        MainActor.assumeIsolated {
            loads?.cancel()
            if let model { pinned.forEach { model.previews.cache.unpin($0) } }
            pinned = []
            if let panel = panel.panel, panel.dataSource === self {
                panel.dataSource = nil
                panel.delegate = nil
            }
        }
    }

    // MARK: - QLPreviewPanelDataSource

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { items.count }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        MainActor.assumeIsolated { ItemBox(item: items.indices.contains(index) ? items[index] : nil) }.item
    }

    // MARK: - QLPreviewPanelDelegate

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown else { return false }
        let keyCode = event.keyCode
        let shift = event.modifierFlags.contains(.shift)
        return MainActor.assumeIsolated {
            guard let model else { return false }
            let direction: BrowserModel.Direction? = switch keyCode {
            case 123: .left
            case 124: .right
            case 125: .down
            case 126: .up
            default: nil
            }
            if keyCode == 49 { // Space closes, as it opened
                close()
                return true
            }
            guard let direction else { return false }
            // Several selected: the panel pages through them with ← →.
            if items.count > 1, direction == .left || direction == .right { return false }
            model.move(direction, extending: shift)
            reload()
            panel.reloadData()
            return true
        }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: (any QLPreviewItem)!) -> NSRect {
        .zero
    }
}

/// Quick Look calls back on the main thread; these only carry its objects through `assumeIsolated`.
private struct PanelBox: @unchecked Sendable {
    let panel: QLPreviewPanel?
}

private struct ItemBox: @unchecked Sendable {
    let item: QuickLookController.Item?
}
