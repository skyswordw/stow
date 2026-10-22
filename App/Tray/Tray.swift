import AppKit
import Quartz
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

/// The Tray: a shelf that lives in the menu bar and collects files from anywhere. It comes out
/// while something is dragged, tucks itself away after an idle time unless pinned, and enters and
/// leaves along the same edge.
@Observable
final class TrayController {
    /// What was dropped on the Tray (the top level).
    var items: [TrayItem] = [] { didSet { touch() } }
    /// Folders browsed into, outermost first; empty at the top level.
    private(set) var path: [TrayItem] = []
    var selection: Set<UUID> = []
    private(set) var anchor: UUID?
    private(set) var isShown = false
    var isHovered = false { didSet { touch() } }
    var isPinned = SettingsKeys.flag(SettingsKeys.trayPinned) {
        didSet { UserDefaults.standard.set(isPinned, forKey: SettingsKeys.trayPinned); touch() }
    }
    var message: String?
    weak var app: AppState?

    @ObservationIgnored private var panel: TrayPanel?
    @ObservationIgnored private var statusItem: NSStatusItem?
    @ObservationIgnored private var dragMonitor: Any?
    @ObservationIgnored private var dragEndMonitor: Any?
    @ObservationIgnored private var dragChangeCount = NSPasteboard(name: .drag).changeCount
    @ObservationIgnored private var isDragging = false
    @ObservationIgnored private var idleTimer: Timer?
    @ObservationIgnored private var lastActivity = Date()
    @ObservationIgnored private var rowMonitor: Any?
    @ObservationIgnored private var press: (point: NSPoint, id: UUID)?
    @ObservationIgnored private var dragStarted = false
    /// The row under the pointer, as rows report it (multi-item drag out starts from here).
    @ObservationIgnored var hoveredRow: UUID?

    private let size = CGSize(width: 300, height: 440)

    // MARK: - Menu bar

    /// Installs or removes the menu-bar icon and the drag watcher to match Settings.
    func applySettings() {
        if defaultsObserver == nil {
            defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil,
                                                                      queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.applySettings() }
            }
        }
        // Installing a status item writes its own defaults, which posts didChange again: only act
        // when a Tray setting really changed, and never re-entrantly.
        let wanted = (icon: SettingsKeys.flag(SettingsKeys.trayMenuBarIcon),
                      drags: SettingsKeys.flag(SettingsKeys.trayShowWhileDragging),
                      border: SettingsKeys.trayBorder())
        guard !isApplying, applied.map({ $0 != wanted }) ?? true else { return }
        isApplying = true
        defer { isApplying = false }
        applied = wanted
        if wanted.icon { installStatusItem() } else { removeStatusItem() }
        if wanted.drags { startWatchingDrags() } else { stopWatchingDrags() }
        panel?.border = wanted.border
    }
    @ObservationIgnored private var isApplying = false
    @ObservationIgnored private var applied: (icon: Bool, drags: Bool, border: TrayBorder)?

    private func installStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "tray", accessibilityDescription: String(localized: "Tray"))
        item.button?.toolTip = String(localized: "Tray — gather files from anywhere")
        item.button?.action = #selector(StatusTarget.toggleTray)
        let target = StatusTarget(tray: self)
        item.button?.target = target
        statusTarget = target
        statusItem = item
    }

    @ObservationIgnored private var statusTarget: StatusTarget?
    @ObservationIgnored private var defaultsObserver: (any NSObjectProtocol)?

    private func removeStatusItem() {
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
        statusTarget = nil
    }

    var hasMenuBarIcon: Bool { statusItem != nil }

    /// A drag of files anywhere on screen brings the Tray out. Mouse-drag monitors need no
    /// Accessibility permission; the drag pasteboard's change count tells a new drag from an old one.
    private func startWatchingDrags() {
        guard dragMonitor == nil else { return }
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseDragged() }
        }
        dragEndMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isDragging = false
                self?.touch()
            }
        }
    }

    private func stopWatchingDrags() {
        if let dragMonitor { NSEvent.removeMonitor(dragMonitor) }
        if let dragEndMonitor { NSEvent.removeMonitor(dragEndMonitor) }
        dragMonitor = nil
        dragEndMonitor = nil
    }

    private func mouseDragged() {
        let pasteboard = NSPasteboard(name: .drag)
        guard pasteboard.changeCount != dragChangeCount else { return }
        dragChangeCount = pasteboard.changeCount
        guard pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) else { return }
        isDragging = true
        touch()
        if !isShown { show() }
    }

    // MARK: - Showing

    func toggle() { isShown ? hide() : show() }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.border = SettingsKeys.trayBorder()
        let final = frame()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.setFrame(reduceMotion || Motion.byKeyboard ? final : final.offsetBy(dx: 0, dy: 16), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        isShown = true
        touch()
        startIdleTimer()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.byKeyboard ? 0 : reduceMotion ? 0.15 : 0.28
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1) // strong ease-out
            panel.animator().setFrame(final, display: true)
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel else { return }
        isShown = false
        idleTimer?.invalidate()
        idleTimer = nil
        if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible { QLPreviewPanel.shared().orderOut(nil) }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.byKeyboard ? 0 : reduceMotion ? 0.1 : 0.18 // leaving is faster than arriving
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
            if !reduceMotion && !Motion.byKeyboard { panel.animator().setFrame(panel.frame.offsetBy(dx: 0, dy: 16), display: true) }
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
        }
    }

    /// Under the menu-bar icon when there is one, otherwise at the right edge of the screen.
    private func frame() -> CGRect {
        if let button = statusItem?.button, let window = button.window, let screen = window.screen {
            let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
            let visible = screen.visibleFrame
            let x = min(max(anchor.midX - size.width / 2, visible.minX + 8), visible.maxX - size.width - 8)
            return CGRect(x: x, y: visible.maxY - size.height - 8, width: size.width, height: size.height)
        }
        let screen = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        return CGRect(x: screen.maxX - size.width - 16, y: screen.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    // MARK: - Idle

    /// Anything people do with the Tray counts as activity.
    func touch() { lastActivity = Date() }

    private func startIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIdle() }
        }
    }

    private func checkIdle() {
        guard isShown else { return }
        if TrayRules.shouldHide(lastActivity: lastActivity, now: Date(), idleSeconds: SettingsKeys.trayIdleSeconds(),
                                pinned: isPinned, isDragging: isDragging, isHovered: isHovered) {
            hide()
        }
    }

    // MARK: - Items

    /// What the Tray shows right now: the top level, or the children of the folder browsed into.
    var visibleItems: [TrayItem] {
        guard let folder = path.last?.url else { return items }
        return browsed[folder] ?? []
    }
    @ObservationIgnored private var browsed: [URL: [TrayItem]] = [:]

    var folderTitle: String? { path.last?.name }

    func add(_ urls: [URL]) {
        let fresh = TrayRules.newURLs(urls, existing: items.compactMap(\.url))
        items += fresh.map(TrayItem.init(url:))
        if !path.isEmpty { path = [] }
    }

    func remove(_ item: TrayItem) {
        items.removeAll { $0.id == item.id }
        selection.remove(item.id)
    }

    func removeSelected() {
        guard path.isEmpty else { return }
        items.removeAll { selection.contains($0.id) }
        selection = []
    }

    func clear() {
        items = []
        path = []
        selection = []
    }

    func click(_ item: TrayItem, command: Bool, shift: Bool) {
        let result = TrayRules.select(item.id, in: visibleItems.map(\.id), current: selection, anchor: anchor,
                                      command: command, shift: shift)
        selection = result.selection
        anchor = result.anchor
        touch()
    }

    func open(_ item: TrayItem) {
        touch()
        if item.isFolder, let url = item.url {
            browsed[url] = TrayRules.children(of: url)
            path.append(item)
            selection = []
            anchor = nil
        } else if item.isArchive, let url = item.url {
            app?.showMainWindow()
            app?.open(url)
        } else if let url = item.url {
            NSWorkspace.shared.open(url)
        }
    }

    func goBack() {
        guard !path.isEmpty else { return }
        path.removeLast()
        selection = []
        anchor = nil
        touch()
    }

    /// The selection, or everything shown when nothing is selected.
    var targets: [TrayItem] {
        let chosen = visibleItems.filter { selection.contains($0.id) }
        return chosen.isEmpty ? visibleItems : chosen
    }
    var targetURLs: [URL] { targets.compactMap(\.url) }

    // MARK: - Actions

    func pack() {
        let urls = targetURLs
        if urls.isEmpty { // sample items
            app?.packRequest = PackRequest(files: targets.map { PackFile(path: $0.name, size: $0.size) })
        } else {
            app?.pack(urls)
        }
        NSApp.activate()
    }

    var canExtract: Bool { targets.contains { $0.isArchive && $0.url != nil } }

    func extract() {
        let archives = targets.filter(\.isArchive).compactMap(\.url)
        guard !archives.isEmpty else { return }
        app?.system.perform(.extractHere, on: archives)
    }

    /// Copies the items into a new folder beside the first one, named by people, and puts that
    /// folder on the Tray in their place. Copies, never moves: the originals stay where they were.
    func collectIntoFolder() async {
        let chosen = targets.filter { $0.url != nil }
        let urls = chosen.compactMap(\.url)
        guard let parent = TrayRules.collectionParent(for: urls) else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Collect into a Folder")
        alert.informativeText = String(localized: "Stow copies the items into a new folder beside “\(urls[0].lastPathComponent)”.")
        let field = NSTextField(string: TrayRules.freeName(String(localized: "New Folder"), in: parent))
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "Collect"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        NSApp.activate()
        let response: NSApplication.ModalResponse
        if let panel { response = await alert.beginSheetModal(for: panel) } else { response = alert.runModal() }
        guard response == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/") else { message = String(localized: "Enter a name without a slash."); return }
        guard let folder = await FolderAccess.shared.writableFolder(
            parent, for: .explained(String(localized: "Stow needs access to this folder to collect the Tray’s items into it.")))
        else { return }
        let destination = folder.appending(path: name, directoryHint: .isDirectory)
        do {
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                message = String(localized: "This folder already has an item named “\(name)”.")
                return
            }
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
            for url in urls {
                try FileManager.default.copyItem(at: url, to: destination.appending(path: TrayRules.freeName(url.lastPathComponent, in: destination)))
            }
        } catch {
            message = EngineError(error).message
            return
        }
        let ids = Set(chosen.map(\.id))
        path = []
        items.removeAll { ids.contains($0.id) }
        items.append(TrayItem(url: destination))
        selection = []
    }

    func share(from view: NSView?) {
        let urls = targetURLs
        guard !urls.isEmpty, let view = view ?? panel?.contentView else { return }
        let picker = NSSharingServicePicker(items: urls)
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    func reveal() {
        let urls = targetURLs
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    /// One archive opens in the browser; anything else becomes a Pack sentence in the main window.
    func sendToMainWindow() {
        let urls = targetURLs
        guard !urls.isEmpty else { return }
        app?.showMainWindow()
        if urls.count == 1, ArchiveTypes.type(forFileName: urls[0].lastPathComponent) != nil {
            app?.open(urls[0])
        } else {
            app?.pack(urls)
        }
        NSApp.activate()
    }

    func quickLook() {
        let urls = targetURLs
        guard !urls.isEmpty, let panel else { return }
        panel.previewURLs = urls
        panel.makeKey()
        let preview = QLPreviewPanel.shared()!
        if preview.isVisible { preview.reloadData() } else { preview.makeKeyAndOrderFront(nil) }
    }

    // MARK: - Panel

    private func makePanel() -> TrayPanel {
        let panel = TrayPanel(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: true)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        let host = NSHostingView(rootView: TrayView(tray: self).environment(app ?? AppState()))
        host.sizingOptions = []
        panel.contentView = host
        installRowDrag(in: panel)
        return panel
    }

    /// Dragging any selected row drags every selected item out (files are real, so plain URLs).
    private func installRowDrag(in panel: TrayPanel) {
        rowMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self, weak panel] event in
            let box = TrayEventBox(event: event)
            return MainActor.assumeIsolated {
                TrayEventBox(event: self?.handleRow(box.event, in: panel) ?? box.event)
            }.event
        }
    }

    private func handleRow(_ event: NSEvent?, in panel: TrayPanel?) -> NSEvent? {
        guard let event, let panel, event.window === panel else { return event }
        switch event.type {
        case .leftMouseDown:
            press = hoveredRow.map { (event.locationInWindow, $0) }
            dragStarted = false
        case .leftMouseDragged:
            guard let press, !dragStarted else { return dragStarted ? nil : event }
            let moved = hypot(event.locationInWindow.x - press.point.x, event.locationInWindow.y - press.point.y)
            guard moved > 4 else { return event }
            if !selection.contains(press.id) { selection = [press.id]; anchor = press.id }
            let urls = visibleItems.filter { selection.contains($0.id) }.compactMap(\.url)
            guard !urls.isEmpty, let view = panel.contentView else { return event }
            dragStarted = true
            touch()
            let point = view.convert(event.locationInWindow, from: nil)
            let dragItems = urls.enumerated().map { index, url in
                let item = NSDraggingItem(pasteboardWriter: url as NSURL)
                let offset = CGFloat(min(index, 4)) * 6
                item.setDraggingFrame(NSRect(x: point.x - 24 + offset, y: point.y - 24 - offset, width: 48, height: 48),
                                      contents: NSWorkspace.shared.icon(forFile: url.path))
                return item
            }
            view.beginDraggingSession(with: dragItems, event: event, source: panel)
            return nil
        default:
            press = nil
            dragStarted = false
        }
        return event
    }
}

private struct TrayEventBox: @unchecked Sendable { let event: NSEvent? }

/// Holds the status item's action (NSStatusBarButton needs an Objective-C target).
private final class StatusTarget: NSObject {
    weak var tray: TrayController?
    init(tray: TrayController) { self.tray = tray }
    @objc func toggleTray() { tray?.toggle() }
}

/// The Tray's window: can take the keyboard, drives Quick Look for real files, and is the drag source.
final class TrayPanel: NSPanel, QLPreviewPanelDataSource, NSDraggingSource {
    nonisolated(unsafe) var previewURLs: [URL] = []
    var border: TrayBorder = .accent

    override var canBecomeKey: Bool { true }

    nonisolated override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }
    nonisolated override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        let box = TrayPreviewBox(panel: panel)
        MainActor.assumeIsolated { box.panel?.dataSource = self }
    }
    nonisolated override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        let box = TrayPreviewBox(panel: panel)
        MainActor.assumeIsolated {
            if let panel = box.panel, panel.dataSource === self { panel.dataSource = nil }
        }
    }
    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { previewURLs.count }
    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        previewURLs.indices.contains(index) ? previewURLs[index] as NSURL : nil
    }

    nonisolated func draggingSession(_ session: NSDraggingSession,
                                     sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .move, .link] : .copy
    }
}

private struct TrayPreviewBox: @unchecked Sendable { let panel: QLPreviewPanel? }

// MARK: - View

struct TrayView: View {
    let tray: TrayController
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SettingsKeys.trayBorder) private var borderName = TrayBorder.accent.rawValue
    @State private var isTargeted = false
    @FocusState private var focusedRow: UUID?

    private var border: TrayBorder { TrayBorder(rawValue: borderName) ?? .accent }

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                if tray.visibleItems.isEmpty { empty } else { list }
            }
            .frame(maxHeight: .infinity)
            if !tray.items.isEmpty { footer }
        }
        .frame(width: 300, height: 440)
        .accessibleGlass(in: .rect(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(border.color.opacity(isTargeted ? 1 : 0.45), lineWidth: isTargeted ? 2 : 1)
        }
        .dropDestination(for: URL.self) { urls, _ in
            tray.add(urls)
            return true
        } isTargeted: { isTargeted = $0; tray.touch() }
        .animation(Motion.resolved(Motion.target, reduceMotion: reduceMotion), value: isTargeted)
        .onHover { tray.isHovered = $0 }
        .onKeyPress(.space) { tray.quickLook(); return .handled }
        .onKeyPress(.delete) { tray.removeSelected(); return .handled }
        .alert("Tray", isPresented: Binding(get: { tray.message != nil }, set: { if !$0 { tray.message = nil } })) {
            Button("OK", role: .cancel) { tray.message = nil }
        } message: { Text(tray.message ?? "") }
    }

    private var header: some View {
        HStack(spacing: Space.s) {
            if let title = tray.folderTitle {
                Button("Back", systemImage: "chevron.left") { tray.goBack() }
                    .accessibilityLabel(String(localized: "Back"))
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("See the previous place")
                Text(title).font(.headline).lineLimit(1).truncationMode(.middle).accessibilityAddTraits(.isHeader)
            } else {
                Text("Tray").font(.headline).accessibilityAddTraits(.isHeader)
                if !tray.items.isEmpty {
                    Text("\(tray.items.count)")
                        .font(.caption.weight(.semibold))
                        .liveNumber()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.tint.opacity(0.15), in: .capsule)
                        .foregroundStyle(.tint)
                }
            }
            Spacer()
            Toggle(isOn: Binding(get: { tray.isPinned }, set: { tray.isPinned = $0 })) {
                Label("Keep Tray Open", systemImage: tray.isPinned ? "pin.fill" : "pin")
            }
            .toggleStyle(.button)
            .accessibilityLabel(String(localized: "Keep Tray Open"))
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help(tray.isPinned ? String(localized: "The Tray stays open") : String(localized: "Keep the Tray open"))
            Button("Close", systemImage: "xmark") { tray.hide() }
                .accessibilityLabel(String(localized: "Close"))
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                .help("Close")
        }
        .padding(.horizontal, Space.l)
        .padding(.top, Space.l)
        .padding(.bottom, Space.s)
    }

    private var empty: some View {
        VStack(spacing: Space.s) {
            Image(systemName: "tray.and.arrow.down").accessibilityHidden(true)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
            Text(tray.folderTitle == nil ? LocalizedStringKey("Drop files here to gather them") : LocalizedStringKey("This folder is empty"))
                .font(.callout.weight(.medium))
            if tray.folderTitle == nil {
                Text("Collect from different folders, then pack or drag them out together.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Add Files…") { chooseFiles() }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .padding(.top, Space.s)
            }
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: Radius.panel)
                .strokeBorder(.separator, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                .padding(Space.m)
        }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "Add to Tray")
        NSApp.activate()
        if panel.runModal() == .OK { tray.add(panel.urls) }
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: Space.xs) {
                ForEach(tray.visibleItems) { item in
                    TrayRow(tray: tray, item: item, isSelected: tray.selection.contains(item.id),
                            canRemove: tray.folderTitle == nil, focusedRow: $focusedRow)
                }
            }
            .padding(.horizontal, Space.s)
        }
        .contextMenu { actionsMenu }
    }

    @ViewBuilder private var actionsMenu: some View {
        Button("Quick Look") { tray.quickLook() }
        Divider()
        Button("Pack…") { tray.pack() }
        Button("Extract Here") { tray.extract() }.disabled(!tray.canExtract)
        Button("Collect into a Folder…") { Task { await tray.collectIntoFolder() } }
        Divider()
        Button("Share…") { tray.share(from: nil) }
        Button("Show in Finder") { tray.reveal() }
        Button("Send to Main Window") { tray.sendToMainWindow() }
    }

    private var footer: some View {
        HStack(spacing: Space.s) {
            VStack(alignment: .leading, spacing: 0) {
                Text(tray.selection.isEmpty ? String(localized: "All items") : String(localized: "\(tray.selection.count) selected"))
                    .font(.caption.weight(.medium))
                Text(tray.targets.reduce(Int64(0)) { $0 + $1.size }.bytes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .liveNumber()
            }
            Spacer()
            Menu {
                actionsMenu
                Divider()
                Button("Clear Tray") { tray.clear() }
            } label: {
                Label("More", systemImage: "ellipsis")
            }
            .menuStyle(.button)
            .buttonStyle(.glass)
            .labelStyle(.iconOnly)
            .accessibilityLabel(String(localized: "More"))
            .help("More")
            .fixedSize()
            Button("Pack", systemImage: "archivebox") { tray.pack() }
                .accessibilityLabel(String(localized: "Pack"))
                .buttonStyle(.glassProminent)
        }
        .controlSize(.large)
        .padding(Space.m)
    }
}

private struct TrayRow: View {
    @Environment(\.colorSchemeContrast) private var contrast
    private var contrastStyle: ContrastStyle { .resolve(contrast) }
    let tray: TrayController
    let item: TrayItem
    let isSelected: Bool
    let canRemove: Bool
    @State private var isHovering = false
    var focusedRow: FocusState<UUID?>.Binding
    private var isFocused: Bool { focusedRow.wrappedValue == item.id }

    var body: some View {
        HStack(spacing: Space.s) {
            TrayThumbnail(item: item)
                .accessibilityHidden(true)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.name).font(.callout).lineLimit(1).truncationMode(.middle)
                Text(item.isFolder ? String(localized: "Folder") : item.size.bytes)
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer(minLength: 0)
            if item.isFolder {
                Image(systemName: "chevron.right").accessibilityHidden(true).font(.caption).foregroundStyle(contrastStyle.metadata)
            }
            if canRemove {
                Button("Remove", systemImage: "minus.circle.fill") { tray.remove(item) }
                    .accessibilityLabel(String(localized: "Remove"))
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .opacity(isHovering || isFocused ? 1 : 0)
                    .help("Remove")
            }
        }
        .padding(Space.s)
        .background(isSelected ? AnyShapeStyle(.tint.opacity(0.22)) : AnyShapeStyle(.primary.opacity(isHovering ? 0.06 : 0)),
                    in: .rect(cornerRadius: Radius.card))
        .contentShape(.rect)
        .onHover { hovering in
            isHovering = hovering
            if hovering { tray.hoveredRow = item.id } else if tray.hoveredRow == item.id { tray.hoveredRow = nil }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel([item.name, item.isFolder ? String(localized: "Folder") : item.size.bytes].joined(separator: ", "))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction { tray.open(item) }
        // The hover-only Remove button is invisible to VoiceOver until hovered; offer it as an action.
        .accessibilityActions {
            if canRemove { Button("Remove") { tray.remove(item) } }
        }
        .focusable()
        .focused(focusedRow, equals: item.id)
        .onChange(of: isFocused) { _, focused in
            if focused { tray.click(item, command: false, shift: false) }
        }
        .onKeyPress(keys: [.upArrow, .downArrow]) { press in
            guard let index = tray.visibleItems.firstIndex(where: { $0.id == item.id }) else { return .ignored }
            let next = min(max(index + (press.key == .upArrow ? -1 : 1), 0), tray.visibleItems.count - 1)
            focusedRow.wrappedValue = tray.visibleItems[next].id
            return .handled
        }
        .onKeyPress(.return) { tray.open(item); return .handled }
        .onKeyPress(.space) { tray.quickLook(); return .handled }
        .onTapGesture(count: 2) { tray.open(item) }
        .simultaneousGesture(TapGesture().onEnded {
            let flags = NSEvent.modifierFlags
            tray.click(item, command: flags.contains(.command), shift: flags.contains(.shift))
        })
    }
}

/// A real file's Finder thumbnail when one exists, its icon otherwise.
private struct TrayThumbnail: View {
    let item: TrayItem
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                NativeIcon(type: item.contentType)
            }
        }
        .task(id: item.url) {
            guard let url = item.url, !item.isFolder else { return }
            let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 60, height: 60),
                                                       scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
            if let thumbnail = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
                image = thumbnail.nsImage
            }
        }
    }
}
