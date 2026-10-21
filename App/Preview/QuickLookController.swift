import AppKit
import Quartz

/// Drives the system Quick Look panel for a browser window. It sits in the window's responder
/// chain, so the panel finds it as its controller; items are extracted on demand, and until a file
/// arrives the panel shows a placeholder of the same name and type (icon, name) instead of nothing.
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
        init(entry: ArchiveEntry, url: URL?) {
            self.entry = entry
            self.url = url
        }
        var previewItemURL: URL! { url }
        var previewItemTitle: String! { entry.name }
    }

    /// Joins the window's responder chain (once).
    func attach(to window: NSWindow) {
        guard self.window !== window else { return }
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

    private func reload() {
        guard let model else { return }
        loads?.cancel()
        pinned.forEach { model.previews.cache.unpin($0) }
        pinned = []
        let order = Dictionary(model.visibleEntries.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        let selected = model.selectedEntries.sorted { (order[$0.id] ?? .max, $0.path) < (order[$1.id] ?? .max, $1.path) }
        let archive = model.archive
        let cache = model.previews.cache
        items = selected.map { entry in
            Item(entry: entry, url: cache.cachedFile(for: entry, in: archive) ?? Self.placeholder(for: entry))
        }
        let wanted = items.filter { !$0.entry.isNavigable && $0.url?.path.hasPrefix(Self.placeholders.path) == true }
        guard !wanted.isEmpty else { return }
        loads = Task { [weak self, weak model] in
            // The one being looked at first, then the rest.
            for item in wanted {
                guard let model, !Task.isCancelled else { return }
                guard let url = try? await model.previews.file(for: item.entry, in: archive) else { continue }
                guard !Task.isCancelled, let self else { return }
                model.previews.cache.pin(url)
                pinned.append(url)
                item.url = url
                if panel?.currentPreviewItem === item { panel?.refreshCurrentPreviewItem() }
            }
        }
    }

    // MARK: - Placeholders

    private static let placeholders = FileManager.default.temporaryDirectory
        .appending(path: "Previews/Placeholders", directoryHint: .isDirectory)

    /// An empty file (or folder) with the entry's name: Quick Look shows its icon and name.
    private static func placeholder(for entry: ArchiveEntry) -> URL {
        let folder = placeholders.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let url = folder.appending(path: entry.name, directoryHint: entry.isFolder ? .isDirectory : .notDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if entry.isFolder {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } else {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        return url
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
