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
    /// Something that went wrong, told inside the Tray (it has no window to hang a sheet on).
    var failure: Failure?
    /// The folder name being typed for Collect into a Folder; nil when not asking.
    var collectingName: String? { didSet { if collectingName != oldValue { collectProblem = nil } } }
    /// Why that name can't be used, said under the field so the question stays open.
    private(set) var collectProblem: String?
    /// Rows a drop (or Add Files…) just named — new ones and ones already on the Tray — so the
    /// view can point them out for a moment. Cleared by itself.
    private(set) var arrived: Set<UUID> = []
    @ObservationIgnored private var arrivalTask: Task<Void, Never>?
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
    @ObservationIgnored private var moveObserver: (any NSObjectProtocol)?
    /// Where people dragged the Tray to, if they did; it comes back out there until Stow quits.
    @ObservationIgnored private var placedFrame: CGRect?
    /// True while Stow itself positions the panel, so that move isn't taken as the person's.
    @ObservationIgnored private var isPlacing = false
    @ObservationIgnored private var press: (point: NSPoint, id: UUID)?
    @ObservationIgnored private var dragStarted = false
    /// The row under the pointer, as rows report it (multi-item drag out starts from here).
    @ObservationIgnored var hoveredRow: UUID?

    private let size = TrayView.size

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
        if !isShown { show(fromDrag: true) }
    }

    // MARK: - Showing

    func toggle() { isShown ? hide() : show() }

    /// Whether the Tray's content is showing; the view animates it in and out with
    /// `Motion.presence` (DESIGN.md › Motion), while the window itself just orders in and out.
    private(set) var isPresented = false
    /// The edge the Tray comes from and goes back to: the menu bar, or the screen's right edge.
    private(set) var edge: UnitPoint = .top

    /// A drag brings the Tray out without taking the keyboard from the app being dragged from;
    /// asking for it (menu-bar icon, toolbar, ⌥⌘T) makes it key, so its controls show as active.
    func show(fromDrag: Bool = false) {
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.border = SettingsKeys.trayBorder()
        isPlacing = true
        panel.setFrame(frame(), display: false)
        isPlacing = false
        // Moved by hand, it grows from its own middle; otherwise from the menu bar or screen edge.
        edge = placedFrame != nil ? .center : statusItem?.button?.window == nil ? .trailing : .top
        isShown = true
        touch()
        startIdleTimer()
        if fromDrag { panel.orderFrontRegardless() } else { panel.makeKeyAndOrderFront(nil) }
        // Nothing moves when ⌥⌘T brought it out. Decided now, while the key press is current.
        let animation = Motion.presence(true, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        guard let animation else {
            isPresented = true
            return
        }
        // The next turn, so the hidden state has been drawn once and there's something to animate from.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isShown else { return }
            withAnimation(animation) { self.isPresented = true }
        }
    }

    func hide() {
        guard let panel else { return }
        isShown = false
        idleTimer?.invalidate()
        idleTimer = nil
        collectingName = nil
        if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible { QLPreviewPanel.shared().orderOut(nil) }
        // Esc and ⌥⌘T: gone at once. Otherwise `Motion.exit`, quicker than it came.
        guard let animation = Motion.presence(false, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) else {
            isPresented = false
            panel.orderOut(nil)
            return
        }
        withAnimation(animation) { isPresented = false } completion: { [weak self] in
            // Brought back out while it was leaving: stay.
            if self?.isShown == false { panel.orderOut(nil) }
        }
    }

    /// Under the menu-bar icon when there is one, otherwise at the right edge of the screen; the
    /// window is larger by the margin its shadow is drawn in.
    private func frame() -> CGRect {
        if let placedFrame, let kept = Self.onScreen(placedFrame) { return kept }
        return contentFrame().insetBy(dx: -TrayView.shadowMargin, dy: -TrayView.shadowMargin)
    }

    /// The frame pulled back inside the screen it's mostly on (its shadow margin may overhang);
    /// nil when that screen has gone.
    private static func onScreen(_ frame: CGRect) -> CGRect? {
        guard let visible = NSScreen.screens.first(where: { $0.visibleFrame.intersects(frame) })?.visibleFrame else { return nil }
        let margin = TrayView.shadowMargin
        var kept = frame
        kept.origin.x = min(max(kept.minX, visible.minX - margin), visible.maxX - kept.width + margin)
        kept.origin.y = min(max(kept.minY, visible.minY - margin), visible.maxY - kept.height + margin)
        return kept
    }

    private func contentFrame() -> CGRect {
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
        pointOut(TrayRules.matching(urls, in: items), added: fresh.count)
    }

    /// Marks the rows that just arrived and lets them go after a moment, fading out like any
    /// status change (DESIGN.md › Motion). Rows dropped a second time are marked too: that is
    /// the answer to "did it go in?" when nothing new was added.
    private func pointOut(_ ids: Set<UUID>, added: Int) {
        guard !ids.isEmpty else { return }
        arrived = ids
        let already = ids.count - added
        let announcement = switch (added, already) {
        case (0, _): String(localized: "Already on the Tray")
        case (_, 0): String(localized: "Added \(added) items to the Tray")
        default: String(localized: "Added \(added) items to the Tray, \(already) already there")
        }
        AccessibilityNotification.Announcement(announcement).post()
        arrivalTask?.cancel()
        arrivalTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled, let self else { return }
            withAnimation(Motion.current(Motion.status)) { self.arrived = [] }
        }
    }

    /// Design review: rows pointed out as if just dropped, held until the scene is captured.
    func showArrivalForDemo(_ ids: Set<UUID>) { arrived = ids }

    /// Design review: the folder-name question answered with a name that's taken.
    func showCollectProblemForDemo(_ name: String) {
        collectingName = name
        collectProblem = String(localized: "This folder already has an item named “\(name)”.")
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

    /// Asks for the folder's name inside the Tray, starting from "New Folder" (or the first free variant).
    func beginCollecting() {
        guard let parent = TrayRules.collectionParent(for: targetURLs) else { return }
        failure = nil
        collectingName = TrayRules.freeName(String(localized: "New Folder"), in: parent)
        panel?.makeKey()
        touch()
    }

    /// Where the new folder goes, for the question's wording.
    var collectionNeighbour: String? { targets.first?.name }

    /// Copies the items into a new folder beside the first one, named by people, and puts that
    /// folder on the Tray in their place. Copies, never moves: the originals stay where they were.
    func collectIntoFolder() async {
        guard let typed = collectingName else { return }
        let chosen = targets.filter { $0.url != nil }
        let urls = chosen.compactMap(\.url)
        guard let parent = TrayRules.collectionParent(for: urls) else { collectingName = nil; return }
        let name = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        // A name that can't be used is answered under the field, which keeps what was typed.
        guard !name.isEmpty, !name.contains("/") else {
            collectProblem = String(localized: "Enter a name without a slash.")
            return
        }
        guard !FileManager.default.fileExists(atPath: parent.appending(path: name).path) else {
            collectProblem = String(localized: "This folder already has an item named “\(name)”.")
            return
        }
        collectingName = nil
        guard let folder = await FolderAccess.shared.writableFolder(
            parent, for: .explained(String(localized: "Stow needs access to this folder to collect the Tray’s items into it.")))
        else { return }
        let destination = folder.appending(path: name, directoryHint: .isDirectory)
        do {
            // Only knowable once the folder is readable: ask again, with what was typed.
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                collectingName = typed
                collectProblem = String(localized: "This folder already has an item named “\(name)”.")
                return
            }
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
            for url in urls {
                try FileManager.default.copyItem(at: url, to: destination.appending(path: TrayRules.freeName(url.lastPathComponent, in: destination)))
            }
        } catch {
            failure = Failure(EngineError(error).message)
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
        let panel = TrayPanel(contentRect: frame(),
                              styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: true)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        // The view draws the shadow: the window server's follows the square frame once the panel is
        // key, which showed as square corners behind the rounded panel.
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        let host = NSHostingView(rootView: TrayView(tray: self).environment(app ?? AppState()))
        host.sizingOptions = []
        panel.contentView = host
        installRowDrag(in: panel)
        moveObserver = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel,
                                                              queue: .main) { [weak self, weak panel] _ in
            MainActor.assumeIsolated {
                guard let self, let panel, !self.isPlacing else { return }
                self.placedFrame = panel.frame
            }
        }
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

/// Glance's arrangement in a smaller frame: the controls on the glass, the files on a solid card
/// (DESIGN.md › "Content is the hero"). Radii are concentric: panel 20 ⊃ card 12 (8 in) ⊃ rows 8 (4 in).
struct TrayView: View {
    let tray: TrayController
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SettingsKeys.trayBorder) private var borderName = TrayBorder.accent.rawValue
    @State private var isTargeted = false
    @FocusState private var focusedRow: UUID?

    static let radius = Radius.card + Space.s
    static let size = CGSize(width: 300, height: 440)
    /// Room around the panel for its shadow.
    static let shadowMargin: CGFloat = 24
    private var border: TrayBorder { TrayBorder(rawValue: borderName) ?? .accent }
    private var isEmpty: Bool { tray.visibleItems.isEmpty }
    private var hasFooter: Bool { tray.failure != nil || tray.collectingName != nil || !tray.items.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            header
            card
                .padding(.horizontal, Space.s)
                // Same 8 below the card as beside it when there's no footer.
                .padding(.bottom, hasFooter ? 0 : Space.s)
            if hasFooter { footer }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        // The whole panel takes the drop, so letting go over the header or footer still lands;
        // the card is what lights up.
        .dropDestination(for: URL.self) { urls, _ in
            tray.add(urls)
            return true
        } isTargeted: { isTargeted = $0; tray.touch() }
        .accessibleGlass(in: RoundedRectangle(cornerRadius: Self.radius))
        .overlay {
            RoundedRectangle(cornerRadius: Self.radius)
                .strokeBorder(border.color.opacity(0.45), lineWidth: 1)
        }
        .background {
            RoundedRectangle(cornerRadius: Self.radius)
                .fill(.black.opacity(0.001))
                .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
        }
        // In from its edge and back out to it: a slight scale and a fade, a fade alone under Reduce Motion.
        .scaleEffect(tray.isPresented || reduceMotion ? 1 : 0.96, anchor: tray.edge)
        .opacity(tray.isPresented ? 1 : 0)
        .padding(Self.shadowMargin)
        .onHover { tray.isHovered = $0 }
        .onKeyPress(.space) { tray.quickLook(); return .handled }
        .onKeyPress(.delete) { tray.removeSelected(); return .handled }
    }


    // MARK: Header

    private var header: some View {
        HStack(spacing: Space.s) {
            if let title = tray.folderTitle {
                Button("Back", systemImage: "chevron.left") { tray.goBack() }
                    .accessibilityLabel(String(localized: "Back"))
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Back to the Tray")
                Text(title).font(.headline).lineLimit(1).truncationMode(.middle).accessibilityAddTraits(.isHeader)
            } else {
                Text("Tray").font(.headline).accessibilityAddTraits(.isHeader)
                if !tray.items.isEmpty {
                    Text("\(tray.items.count)")
                        .font(.caption.weight(.semibold))
                        .liveNumber()
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: .capsule)
                }
            }
            Spacer(minLength: Space.s)
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
                .help("Close")
                // While a folder name is being typed, Escape cancels that instead.
                .keyboardShortcut(tray.collectingName == nil ? .cancelAction : nil)
        }
        .padding(.horizontal, Space.l)
        .padding(.top, Space.m)
        .padding(.bottom, Space.s)
        // The header is the Tray's title bar: drag it to move the panel. The buttons in it keep
        // their clicks. (SwiftUI never passes a background drag to AppKit, so
        // `isMovableByWindowBackground` alone doesn't move it.)
        .contentShape(.rect)
        .gesture(WindowDragGesture())
        .allowsWindowActivationEvents(true)
    }

    // MARK: Card

    /// The solid card is the drop target, the same way the welcome window's is: a dashed edge
    /// while empty, the border colour and a light tint while something is held over it.
    private var card: some View {
        Group {
            if isEmpty { empty } else { list }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .overlay {
            if isTargeted { Rectangle().fill(border.color.opacity(0.08)).allowsHitTesting(false) }
        }
        .clipShape(.rect(cornerRadius: Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card)
                .strokeBorder(isTargeted ? AnyShapeStyle(border.color) : AnyShapeStyle(.separator),
                              style: StrokeStyle(lineWidth: isTargeted ? 2 : (isEmpty ? 1.5 : 1),
                                                 dash: isEmpty && !isTargeted ? [7, 6] : []))
        }
        .scaleEffect(isTargeted && !reduceMotion ? 1.015 : 1)
        .animation(Motion.resolved(Motion.target, reduceMotion: reduceMotion), value: isTargeted)
    }

    private var empty: some View {
        VStack(spacing: Space.m) {
            Image(systemName: tray.folderTitle == nil ? "tray.and.arrow.down" : "folder")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            if tray.folderTitle == nil {
                VStack(spacing: Space.xs) {
                    Text(isTargeted ? String(localized: "Let go to add") : String(localized: "Drop files here to gather them"))
                        .font(.headline)
                        .contentTransition(.opacity)
                    Text("Collect from different folders, then pack or drag them out together.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.center)
                Button("Add Files…") { chooseFiles() }
                    .controlSize(.large)
                    .padding(.top, Space.xs)
            } else {
                Text("This folder is empty").font(.headline)
            }
        }
        .padding(Space.xl)
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
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(tray.visibleItems) { item in
                        TrayRow(tray: tray, item: item, isSelected: tray.selection.contains(item.id),
                                hasArrived: tray.arrived.contains(item.id),
                                canRemove: tray.folderTitle == nil, focusedRow: $focusedRow)
                    }
                }
                .padding(Space.xs)
            }
            // What a drop added may be below the fold: bring the last of it into view.
            .onChange(of: tray.arrived) { _, arrived in
                guard let last = tray.visibleItems.last(where: { arrived.contains($0.id) }) else { return }
                // Scrolling is movement: none under Reduce Motion.
                withAnimation(reduceMotion ? nil : Motion.current(Motion.status)) { proxy.scrollTo(last.id) }
            }
        }
        .contextMenu { actionsMenu }
    }

    @ViewBuilder private var actionsMenu: some View {
        Button("Quick Look") { tray.quickLook() }
        Divider()
        Button("Pack…") { tray.pack() }
        Button("Extract Here") { tray.extract() }.disabled(!tray.canExtract)
        Button("Collect into a Folder…") { tray.beginCollecting() }
            .disabled(tray.targetURLs.isEmpty)
        Divider()
        Button("Share…") { tray.share(from: nil) }
        Button("Show in Finder") { tray.reveal() }
        Button("Send to Main Window") { tray.sendToMainWindow() }
    }

    // MARK: Footer

    /// One thing at a time under the card: a failure, the folder-name question, or the summary
    /// with Pack — the Tray's one obvious next step.
    @ViewBuilder
    private var footer: some View {
        Group {
            if let failure = tray.failure {
                ActivityLabel(phase: .failed(failure), title: failure.title, dismiss: { tray.failure = nil })
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if tray.collectingName != nil {
                collectForm
            } else {
                summary
            }
        }
        .padding(.horizontal, Space.l)
        .padding(.top, Space.m)
        .padding(.bottom, Space.m)
        // A failure turning up is a status change; the rest follow clicks and keys, and don't move.
        .animation(tray.failure == nil ? nil : Motion.resolved(Motion.status, reduceMotion: reduceMotion), value: tray.failure)
    }

    private var summary: some View {
        HStack(spacing: Space.s) {
            VStack(alignment: .leading, spacing: 0) {
                Group {
                    if tray.selection.isEmpty {
                        Text("\(tray.visibleItems.count) items")
                    } else {
                        Text("\(tray.selection.count) selected")
                    }
                }
                .font(.callout.weight(.medium))
                .liveNumber()
                Text(tray.targets.reduce(Int64(0)) { $0 + $1.size }.bytes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .liveNumber()
            }
            .lineLimit(1)
            Spacer(minLength: Space.s)
            Menu {
                actionsMenu
                Divider()
                Button("Clear Tray") { tray.clear() }
            } label: {
                Label("More", systemImage: "ellipsis")
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .labelStyle(.iconOnly)
            .accessibilityLabel(String(localized: "More"))
            .fixedSize()
            .help("More things to do with these items")
            // Inside the glass, so the buttons can't take a glass style of their own.
            Button {
                tray.pack()
            } label: {
                Label("Pack", systemImage: "archivebox")
            }
            .accessibilityLabel(String(localized: "Pack"))
            .buttonStyle(.borderedProminent)
            .help("Pack these into an archive")
        }
        .controlSize(.large)
    }

    private var collectForm: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Collect into a Folder").font(.headline)
                if let neighbour = tray.collectionNeighbour {
                    Text("Copies go in a new folder beside “\(neighbour)”. The originals stay put.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            TextField("Folder name", text: Binding(get: { tray.collectingName ?? "" }, set: { tray.collectingName = $0 }))
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await tray.collectIntoFolder() } }
            // Right under the field it is about, like the password sheet's.
            if let problem = tray.collectProblem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Space.s) {
                Spacer(minLength: 0)
                Button("Cancel", role: .cancel) { tray.collectingName = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Collect") { Task { await tray.collectIntoFolder() } }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled((tray.collectingName ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}

private struct TrayRow: View {
    @Environment(\.colorSchemeContrast) private var contrast
    private var contrastStyle: ContrastStyle { .resolve(contrast) }
    let tray: TrayController
    let item: TrayItem
    let isSelected: Bool
    /// Just dropped (or dropped again): ringed in the accent for a moment.
    let hasArrived: Bool
    let canRemove: Bool
    @State private var isHovering = false
    var focusedRow: FocusState<UUID?>.Binding
    private var isFocused: Bool { focusedRow.wrappedValue == item.id }

    var body: some View {
        HStack(spacing: Space.s) {
            TrayThumbnail(item: item)
                .accessibilityHidden(true)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.name).lineLimit(1).truncationMode(.middle)
                Text(item.isFolder ? String(localized: "Folder") : item.size.bytes)
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer(minLength: 0)
            // Shown on hover and for the focused row, so the keyboard reaches it too.
            if canRemove, isHovering || isFocused {
                Button("Remove from Tray", systemImage: "xmark.circle.fill") { tray.remove(item) }
                    .accessibilityLabel(String(localized: "Remove"))
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(contrastStyle.metadata)
                    .help("Remove from the Tray — the file stays where it is")
            } else if item.isFolder {
                Image(systemName: "chevron.right").accessibilityHidden(true).font(.caption).foregroundStyle(contrastStyle.metadata)
            }
        }
        .padding(.horizontal, Space.s)
        .padding(.vertical, 6)
        .background(isSelected ? AnyShapeStyle(.tint.opacity(0.2))
                        : hasArrived ? AnyShapeStyle(.tint.opacity(0.08))
                        : AnyShapeStyle(.primary.opacity(isHovering ? 0.05 : 0)),
                    in: .rect(cornerRadius: Radius.chip))
        // A ring rather than a fill, so it never reads as a selection.
        .overlay {
            RoundedRectangle(cornerRadius: Radius.chip)
                .strokeBorder(.tint, lineWidth: 1.5)
                .opacity(hasArrived ? 1 : 0)
                .allowsHitTesting(false)
        }
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

/// A picture or video's Finder thumbnail; every other real file's Finder icon; the type's icon for samples.
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
            guard let url = item.url else { return }
            // At 28 pt only a picture or a video says anything as a preview; a page of text or a PDF
            // is a white square. Everything else gets its Finder icon: the type's badge, an app's
            // own icon, a folder's custom icon.
            guard !item.isFolder, item.contentType.conforms(to: .image) || item.contentType.conforms(to: .movie) else {
                image = NSWorkspace.shared.icon(forFile: url.path)
                return
            }
            // Decorated as Finder draws it, with an edge and shadow around the picture.
            let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 28, height: 28),
                                                       scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .all)
            request.iconMode = true
            if let thumbnail = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
                image = thumbnail.nsImage
            }
        }
    }
}
