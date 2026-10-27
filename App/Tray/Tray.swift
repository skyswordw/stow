import AppKit
import Quartz
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

/// The Tray: a shelf that lives in the menu bar and collects files from anywhere. It comes out
/// when files are dragged to it, tucks itself away after an idle time unless pinned (or as soon as
/// a drag that brought it out ends with nothing dropped), and enters and leaves along the same edge.
@Observable
final class TrayController {
    /// What was dropped on the Tray (the top level).
    var items: [TrayItem] = [] { didSet { touch() } }
    /// Folders browsed into, outermost first; empty at the top level.
    private(set) var path: [TrayItem] = []
    var selection: Set<UUID> = []
    private(set) var anchor: UUID?
    private(set) var isShown = false
    var isHovered = false {
        didSet {
            touch()
            // The pointer on it after a drag means people turned to it: it stays like any Tray.
            if isHovered, !isDragging { revealedByDrag = false }
        }
    }
    var isPinned = SettingsKeys.flag(SettingsKeys.trayPinned) {
        didSet { UserDefaults.standard.set(isPinned, forKey: SettingsKeys.trayPinned); touch() }
    }
    /// Something that went wrong, told inside the Tray (it has no window to hang a sheet on).
    var failure: Failure?
    /// The folder name being typed for Collect into a Folder; nil when not asking.
    var collectingName: String? { didSet { if collectingName != oldValue { collectProblem = nil } } }
    /// Why that name can't be used, said under the field so the question stays open.
    private(set) var collectProblem: String?
    /// The folder the new folder goes in, shown in the question's Where menu. Defaults to the
    /// app-managed temporary root (#179); a Where choice keeps the folder after packing.
    private(set) var collectDestination: URL?
    /// True while Collect's Where is the temporary root (default for #179).
    var isCollectingTemporarily: Bool {
        guard let collectDestination else { return false }
        return TrayTemporaryGroups.isOwned(collectDestination)
    }
    /// The folder Collect just made, so the summary can say where it went; cleared by the next action.
    private(set) var collected: URL?
    /// Rows a drop (or Add Files…) just named — new ones and ones already on the Tray — so the
    /// view can point them out for a moment. Cleared by itself.
    private(set) var arrived: Set<UUID> = []
    @ObservationIgnored private var arrivalTask: Task<Void, Never>?
    /// The Tray's own history: Remove and Clear Tray can be undone (⌘Z) while the Tray is in front.
    /// Its own, so ⌘Z in the Tray never reaches an archive's staged edits.
    /// Each removal is one step, grouped here rather than by event, so two quick removals never undo together.
    let undoManager: UndoManager = {
        let manager = UndoManager()
        manager.groupsByEvent = false
        return manager
    }()
    weak var app: AppState?

    @ObservationIgnored private var panel: TrayPanel?
    @ObservationIgnored private var statusItem: NSStatusItem?
    @ObservationIgnored private var dragMonitor: Any?
    @ObservationIgnored private var dragEndMonitor: Any?
    @ObservationIgnored private var dragChangeCount = NSPasteboard(name: .drag).changeCount
    /// Files are being dragged in another app, from the drag's first move to the button coming up.
    @ObservationIgnored private var isDragging = false
    /// A drag of files brought the Tray out and nothing has been dropped on it yet: it goes back
    /// once the drag ends. A drop, the pointer on it or opening it by hand clears this.
    @ObservationIgnored private var revealedByDrag = false
    @ObservationIgnored private var tuckTask: Task<Void, Never>?
    /// Shows where the Tray comes out while files are dragged, when that isn't the menu-bar icon.
    @ObservationIgnored private var hint: TrayHint?
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
        item.button?.image = Self.statusImage(receiving: false)
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

    /// The menu-bar icon; while files are dragged it shows the tray taking something in.
    private static func statusImage(receiving: Bool) -> NSImage? {
        NSImage(systemSymbolName: receiving ? "tray.and.arrow.down" : "tray",
                accessibilityDescription: String(localized: "Tray"))
    }

    // MARK: - Drags (#180)

    /// Dragging files only brings the Tray out once the drag comes to where it lives: under its
    /// menu-bar icon, at the screen's edge, or where people put it (`TrayRules.approachZone`).
    /// Until then the icon, or a small hint at that edge, shows where to go. Mouse-drag monitors
    /// need no Accessibility permission; the drag pasteboard's change count tells a new drag from
    /// an old one.
    private func startWatchingDrags() {
        guard dragMonitor == nil else { return }
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseDragged() }
        }
        dragEndMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseUp() }
        }
    }

    private func stopWatchingDrags() {
        if let dragMonitor { NSEvent.removeMonitor(dragMonitor) }
        if let dragEndMonitor { NSEvent.removeMonitor(dragEndMonitor) }
        dragMonitor = nil
        dragEndMonitor = nil
        if isDragging { mouseUp() }
    }

    private func mouseDragged() {
        let pasteboard = NSPasteboard(name: .drag)
        if pasteboard.changeCount != dragChangeCount {
            dragChangeCount = pasteboard.changeCount
            // A new drag. Only files count; text or a window being moved never shows the Tray, and
            // ends anything a missed mouse-up left behind.
            guard pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) else {
                if isDragging { mouseUp() }
                return
            }
            isDragging = true
            touch()
            if !isShown { showHint(true) }
        }
        guard isDragging, !isShown, approachZone().contains(NSEvent.mouseLocation) else { return }
        showHint(false)
        show(fromDrag: true)
    }

    private func mouseUp() {
        let ended = isDragging
        isDragging = false
        touch()
        guard ended else { return }
        showHint(false)
        // Let go over the Tray: people brought the files to it, and a drop of promised files can
        // take a while to arrive. It stays like any Tray.
        if isShown, contentFrameShown().contains(NSEvent.mouseLocation) { revealedByDrag = false }
        guard revealedByDrag else { return }
        // A drop lands on mouse-up too: give it a moment to arrive before deciding nothing came.
        tuckTask?.cancel()
        tuckTask = Task { [weak self] in
            try? await Task.sleep(for: TrayRules.unusedDragGrace)
            guard let self, !Task.isCancelled, self.isShown else { return }
            if TrayRules.shouldTuckAfterDrag(revealedByDrag: self.revealedByDrag, isDragging: self.isDragging,
                                             pinned: self.isPinned, isHovered: self.isHovered) {
                self.hide()
            }
        }
    }

    /// The menu-bar icon shows the tray taking something in; without one, a small hint comes out
    /// where the Tray will.
    private func showHint(_ visible: Bool) {
        let home = home
        if let button = statusItem?.button {
            button.image = Self.statusImage(receiving: visible && home == .menuBar)
        }
        guard visible, home != .menuBar else {
            hint?.dismiss()
            return
        }
        let hint = hint ?? TrayHint()
        self.hint = hint
        hint.present(at: TrayRules.hintCenter(home: home, tray: contentFrameShown(), hintSize: TrayHint.size),
                     border: SettingsKeys.trayBorder())
    }

    /// Where the Tray lives right now.
    private var home: TrayHome {
        if let placedFrame, Self.onScreen(placedFrame) != nil { return .placed }
        return statusItem?.button?.window?.screen == nil ? .screenEdge : .menuBar
    }

    /// The Tray's frame as it comes out, without the margin its shadow is drawn in.
    private func contentFrameShown() -> CGRect {
        frame().insetBy(dx: TrayView.shadowMargin, dy: TrayView.shadowMargin)
    }

    private func approachZone() -> CGRect {
        let tray = contentFrameShown()
        let screen = NSScreen.screens.first { $0.frame.intersects(tray) } ?? NSScreen.main
        guard let screen else { return tray }
        return TrayRules.approachZone(home: home, tray: tray, screen: screen.frame, visible: screen.visibleFrame)
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
        let home = home
        edge = switch home {
        case .placed: .center
        case .menuBar: .top
        case .screenEdge: .trailing
        }
        revealedByDrag = fromDrag
        tuckTask?.cancel()
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
        revealedByDrag = false
        tuckTask?.cancel()
        idleTimer?.invalidate()
        idleTimer = nil
        collectingName = nil
        collected = nil
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
        // Something was dropped on it (or added by hand): it stays out like any Tray.
        revealedByDrag = false
        let fresh = TrayRules.newURLs(urls, existing: items.compactMap(\.url))
        items += fresh.map(TrayItem.init(url:))
        if !path.isEmpty { path = [] }
        collected = nil
        pointOut(TrayRules.matching(urls, in: items), added: fresh.count)
    }

    /// Marks the rows that just arrived and lets them go after a moment, fading out like any
    /// status change (DESIGN.md › Motion). Rows dropped a second time are marked too: that is
    /// the answer to "did it go in?" when nothing new was added.
    private func pointOut(_ ids: Set<UUID>, added: Int) {
        guard !ids.isEmpty else { return }
        let already = ids.count - added
        let announcement = switch (added, already) {
        case (0, _): String(localized: "Already on the Tray")
        case (_, 0): String(localized: "Added \(added) items to the Tray")
        default: String(localized: "Added \(added) items to the Tray, \(already) already there")
        }
        mark(ids, announcing: announcement)
    }

    private func mark(_ ids: Set<UUID>, announcing announcement: String) {
        arrived = ids
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

    /// A row's own ⓧ: that row only, whatever else is selected.
    func remove(_ item: TrayItem) {
        takeOff([item.id], actionName: String(localized: "Remove from Tray"))
    }

    /// Remove from Tray (right-click and More menus): everything selected. Nothing selected, nothing removed (Clear
    /// Tray is for all of it). The files themselves never move.
    func removeSelected() {
        guard path.isEmpty, !selection.isEmpty else { return }
        takeOff(selection, actionName: String(localized: "Remove from Tray"))
    }

    func clear() {
        path = []
        takeOff(Set(items.map(\.id)), actionName: String(localized: "Clear Tray"))
    }

    /// Takes rows off the Tray and registers putting them back, so ⌘Z restores them in place.
    /// Owned temporary groups (#179) are deleted from disk when their row leaves; Undo only
    /// restores the row when the folder is still present.
    private func takeOff(_ ids: Set<UUID>, actionName: String) {
        let removed = items.enumerated().filter { ids.contains($0.element.id) }.map { (index: $0.offset, item: $0.element) }
        guard !removed.isEmpty else { return }
        let selected = selection
        items.removeAll { ids.contains($0.id) }
        selection.subtract(ids)
        collected = nil
        for entry in removed where entry.item.isTemporaryGroup {
            if let url = entry.item.url, TrayTemporaryGroups.isOwned(url) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        registerUndo(actionName) { tray in
            tray.putBack(removed, selection: selected.intersection(ids), actionName: actionName)
        }
    }

    /// Drops a temporary group row after successful pack cleanup without deleting again.
    func removeCleanedTemporaryGroup(at url: URL) {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        let ids = Set(items.filter {
            $0.isTemporaryGroup && $0.url?.resolvingSymlinksInPath().standardizedFileURL.path == path
        }.map(\.id))
        guard !ids.isEmpty else { return }
        items.removeAll { ids.contains($0.id) }
        selection.subtract(ids)
        if let collected, collected.resolvingSymlinksInPath().standardizedFileURL.path == path {
            self.collected = nil
        }
        touch()
    }

    /// One undo step. While undoing or redoing, the manager is already collecting the inverse step.
    private func registerUndo(_ actionName: String, _ handler: @escaping (TrayController) -> Void) {
        let grouping = !undoManager.isUndoing && !undoManager.isRedoing
        if grouping { undoManager.beginUndoGrouping() }
        undoManager.registerUndo(withTarget: self, handler: handler)
        undoManager.setActionName(actionName)
        if grouping { undoManager.endUndoGrouping() }
    }

    /// Undo: the rows return where they were (a file dropped again since isn't doubled), ringed
    /// like a drop, and the step can be redone.
    private func putBack(_ removed: [(index: Int, item: TrayItem)], selection restored: Set<UUID>, actionName: String) {
        let present = Set(items.compactMap { $0.url?.standardizedFileURL.path })
        var back: [TrayItem] = []
        for entry in removed.sorted(by: { $0.index < $1.index }) {
            if let path = entry.item.url?.standardizedFileURL.path, present.contains(path) { continue }
            // Temporary groups deleted on takeOff cannot return unless the folder was restored.
            if entry.item.isTemporaryGroup, let url = entry.item.url,
               !FileManager.default.fileExists(atPath: url.path) { continue }
            items.insert(entry.item, at: min(entry.index, items.count))
            back.append(entry.item)
        }
        let ids = Set(back.map(\.id))
        selection = restored.intersection(ids)
        registerUndo(actionName) { tray in tray.takeOff(ids, actionName: actionName) }
        guard !ids.isEmpty else { return }
        mark(ids, announcing: String(localized: "Put back on the Tray"))
    }

    /// Right-click or ⌃-click on a row: the menu acts on that row. Selected already, the whole
    /// selection stays; otherwise the row becomes the selection first, as in Finder.
    func selectForMenu(_ id: UUID) {
        guard !selection.contains(id) else { return }
        selection = [id]
        anchor = id
        collected = nil
    }

    func click(_ item: TrayItem, command: Bool, shift: Bool) {
        let result = TrayRules.select(item.id, in: visibleItems.map(\.id), current: selection, anchor: anchor,
                                      command: command, shift: shift)
        collected = nil
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
            // Only top-level owned temporary groups: packing their children must not delete the parent.
            let cleanup = path.isEmpty
                ? targets.filter(\.isTemporaryGroup).compactMap(\.url).filter { TrayTemporaryGroups.isOwned($0) }
                : []
            app?.pack(urls, cleanupTemporaryGroups: cleanup)
        }
        NSApp.activate()
    }

    var canExtract: Bool { targets.contains { $0.isArchive && $0.url != nil } }

    func extract() {
        let archives = targets.filter(\.isArchive).compactMap(\.url)
        guard !archives.isEmpty else { return }
        app?.system.perform(.extractHere, on: archives)
    }

    /// Asks for the folder's name inside the Tray. Defaults to an app-managed temporary group
    /// (#179); Where remains available to Keep / save the group somewhere persistent.
    func beginCollecting(remembered: URL? = GatherDestination.remembered()) {
        let urls = targetURLs
        guard !urls.isEmpty else { return }
        failure = nil
        collected = nil
        // remembered still feeds collectPlaces; the default destination is temporary.
        _ = remembered
        collectDestination = TrayTemporaryGroups.root()
        collectingName = suggestedName(in: collectDestination)
        panel?.makeKey()
        touch()
    }

    /// "New Folder", or the first free variant once there's a folder to check.
    private func suggestedName(in folder: URL?) -> String {
        let base = String(localized: "New Folder")
        return folder.map { TrayRules.freeName(base, in: $0) } ?? base
    }

    /// The folders the items come from, for the Where menu.
    var collectSources: [GatherDestination.Source] { GatherDestination.sources(of: targetURLs) }

    /// Other places offered in the Where menu: the folder last chosen for a mix, Desktop and
    /// Downloads, leaving out any already listed as a source.
    var collectPlaces: [URL] {
        let listed = Set(collectSources.map(\.folder.standardizedFileURL.path))
        var seen = listed
        let home = FolderAccess.home
        let candidates = [GatherDestination.remembered(), home.appending(path: "Desktop", directoryHint: .isDirectory),
                          home.appending(path: "Downloads", directoryHint: .isDirectory)].compactMap { $0 }
        return candidates.filter {
            !TrayTemporaryGroups.isOwned($0) && seen.insert($0.standardizedFileURL.path).inserted
        }
    }

    var collectsFromSeveralFolders: Bool { collectSources.count > 1 }

    /// Picks where the new folder goes. A name Stow suggested follows the folder ("New Folder 2"
    /// if that one has a "New Folder"); a name people typed stays.
    func chooseCollectDestination(_ folder: URL) {
        let typed = collectingName
        let suggested = typed == suggestedName(in: collectDestination)
        collectDestination = folder
        if suggested { collectingName = suggestedName(in: folder) }
        collectProblem = nil
        touch()
    }

    /// The Where menu's Other…: any folder, from an Open panel (which also lets Stow write there).
    func chooseOtherCollectDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = collectDestination
        panel.prompt = String(localized: "Choose")
        panel.message = String(localized: "Choose where the new folder goes.")
        NSApp.activate()
        if panel.runModal() == .OK, let url = panel.url { chooseCollectDestination(url) }
        self.panel?.makeKey()
    }

    /// Copies the items into a new folder where people chose, named by them, and puts that
    /// folder on the Tray in their place. Copies, never moves: the originals stay where they were.
    func collectIntoFolder() async {
        guard let typed = collectingName else { return }
        let chosen = targets.filter { $0.url != nil }
        let urls = chosen.compactMap(\.url)
        guard !urls.isEmpty else { collectingName = nil; return }
        // Return in the name field before a folder was chosen: say what's missing, keep the question.
        guard let parent = collectDestination else {
            collectProblem = String(localized: "Choose where the new folder goes.")
            return
        }
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
                collectDestination = folder
                collectProblem = String(localized: "This folder already has an item named “\(name)”.")
                return
            }
            _ = try TrayCollection.copy(urls, named: name, into: folder)
        } catch let retained as TrayCollection.RetainedCopies {
            failure = Failure(String(localized: "Couldn’t collect the files."),
                              advice: String(localized: "Partial copies remain in “\(retained.folder.path)”. Remove that folder before trying again."),
                              code: ErrorCode(.copy, .unknown))
            failure?.diagnostic = String(describing: retained.copyError) + "\nCleanup: " + String(describing: retained.cleanupError)
            return
        } catch let recursive as TrayCollection.RecursiveDestination {
            collectingName = typed
            collectDestination = folder
            collectProblem = recursive.localizedDescription
            return
        } catch {
            failure = Failure(error, .copy, name: name, destination: folder)
            return
        }
        // Remember mix destinations only for persistent folders — never the temporary root (#179).
        let temporary = TrayTemporaryGroups.isOwned(folder)
        if !temporary {
            GatherDestination.remember(folder, for: urls)
        }
        let ids = Set(chosen.map(\.id))
        let absorbedTemps = chosen.filter(\.isTemporaryGroup).compactMap(\.url)
        path = []
        items.removeAll { ids.contains($0.id) }
        // Inputs that were themselves owned temps are disposable once copied into the new folder.
        for url in absorbedTemps where TrayTemporaryGroups.isOwned(url) {
            try? FileManager.default.removeItem(at: url)
        }
        let made = TrayItem(url: destination, isTemporaryGroup: temporary)
        items.append(made)
        selection = []
        withAnimation(Motion.current(Motion.status)) { collected = destination }
        mark([made.id], announcing: Self.collectedTitle(destination, temporary: temporary))
    }

    /// "Collected in “Desktop”", or a temporary note when the group is app-owned (#179).
    static func collectedTitle(_ made: URL, temporary: Bool = false) -> String {
        if temporary {
            return String(localized: "Collected for packing")
        }
        return String(localized: "Collected in “\(FileManager.default.displayName(atPath: made.deletingLastPathComponent().path))”")
    }

    func revealCollected() {
        guard let collected else { return }
        NSWorkspace.shared.activateFileViewerSelecting([collected])
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
        let host = TrayHostingView(rootView: TrayView(tray: self).environment(app ?? AppState()))
        host.sizingOptions = []
        host.trayUndoManager = undoManager
        panel.contentView = host
        panel.trayUndoManager = undoManager
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
        rowMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown]) { [weak self, weak panel] event in
            let box = TrayEventBox(event: event)
            return MainActor.assumeIsolated {
                TrayEventBox(event: self?.handleRow(box.event, in: panel) ?? box.event)
            }.event
        }
    }

    private func handleRow(_ event: NSEvent?, in panel: TrayPanel?) -> NSEvent? {
        guard let event, let panel, event.window === panel else { return event }
        switch event.type {
        case .rightMouseDown:
            if let hoveredRow { selectForMenu(hoveredRow) }
        case .leftMouseDown where event.modifierFlags.contains(.control):
            if let hoveredRow { selectForMenu(hoveredRow) }
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
    var trayUndoManager: UndoManager?

    override var canBecomeKey: Bool { true }
    override var undoManager: UndoManager? { trayUndoManager ?? super.undoManager }

    private var editingText: NSTextView? {
        (firstResponder as? NSTextView).flatMap { $0.isEditable ? $0 : nil }
    }

    /// ⌘Z and ⇧⌘Z go straight to the Tray's own history (outside a text field), whichever
    /// responder SwiftUI has made first.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if editingText == nil, event.charactersIgnoringModifiers?.lowercased() == "z", let undo = trayUndoManager {
            if modifiers == .command { if undo.canUndo { undo.undo() }; return true }
            if modifiers == [.command, .shift] { if undo.canRedo { undo.redo() }; return true }
        }
        return super.performKeyEquivalent(with: event)
    }

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

/// The Tray's content view hands Edit › Undo the Tray's history, so the menu reads
/// "Undo Remove from Tray" while the Tray is in front.
final class TrayHostingView<Content: View>: NSHostingView<Content> {
    var trayUndoManager: UndoManager?
    override var undoManager: UndoManager? { trayUndoManager ?? super.undoManager }
}

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
        .contextMenu {
            actionsMenu
            Divider()
            // No count here: the menu can be built before a right-click's new selection is drawn.
            removeButton(counted: false)
        }
    }

    /// Removes the selection from the Tray (the files stay). A menu command, with no key of its own.
    private func removeButton(counted: Bool) -> some View {
        let count = tray.selection.count
        return Button(counted && count > 1 ? String(localized: "Remove \(count) Items from Tray") : String(localized: "Remove from Tray")) {
            tray.removeSelected()
        }
        .disabled(tray.selection.isEmpty || tray.folderTitle != nil)
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
        VStack(alignment: .leading, spacing: Space.s) {
            if let made = tray.collected {
                collectedNote(made).transition(.opacity)
            }
            summaryRow
        }
    }

    private var summaryRow: some View {
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
                removeButton(counted: true)
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
                Text(tray.isCollectingTemporarily
                     ? "Stow copies into a temporary folder for packing. Choose Where to keep it."
                     : "Stow puts copies in a new folder. The originals stay where they are.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Name, then Where, as a Save dialog asks them.
            Grid(alignment: .leading, horizontalSpacing: Space.s, verticalSpacing: Space.s) {
                GridRow {
                    Text("Name").font(.callout).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                    TextField("Folder name", text: Binding(get: { tray.collectingName ?? "" }, set: { tray.collectingName = $0 }))
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(String(localized: "Folder name"))
                        .onSubmit { Task { await tray.collectIntoFolder() } }
                }
                GridRow {
                    Text("Where").font(.callout).foregroundStyle(.secondary)
                    whereMenu
                }
            }
            // Items from several folders and nothing chosen yet: say why Stow is asking.
            if tray.collectDestination == nil, tray.collectsFromSeveralFolders {
                Text("These come from \(tray.collectSources.count) folders. Choose where the new folder goes.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if tray.isCollectingTemporarily, tray.collectsFromSeveralFolders {
                Text("These come from \(tray.collectSources.count) folders. Temporary keeps them together for packing.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Right under the fields it is about, like the password sheet's.
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
                    .disabled((tray.collectingName ?? "").trimmingCharacters(in: .whitespaces).isEmpty
                              || tray.collectDestination == nil)
            }
        }
    }

    /// The folders the items come from first (with how many each), then other likely places,
    /// then any folder. The chosen one is ticked; each shows its path, so two "Photos" differ.
    private var whereMenu: some View {
        Menu {
            Section {
                destinationChoice(TrayTemporaryGroups.root(), detail: String(localized: "Deleted after packing"),
                                  title: String(localized: "Temporary"))
            }
            Section {
                ForEach(tray.collectSources, id: \.folder) { source in
                    destinationChoice(source.folder, detail: String(localized: "\(source.count) items"))
                }
            }
            if !tray.collectPlaces.isEmpty {
                Section {
                    ForEach(tray.collectPlaces, id: \.self) { folder in destinationChoice(folder, detail: nil) }
                }
            }
            Divider()
            Button("Other…") { tray.chooseOtherCollectDestination() }
        } label: {
            Label(tray.isCollectingTemporarily
                  ? String(localized: "Temporary")
                  : (tray.collectDestination.map(Self.folderName) ?? String(localized: "Choose a Folder…")),
                  systemImage: tray.isCollectingTemporarily ? "clock" : "folder")
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(tray.collectDestination.map(GatherDestination.abbreviated) ?? "")
        .accessibilityLabel(String(localized: "Where"))
        .accessibilityValue(tray.collectDestination.map(Self.folderName) ?? String(localized: "Not chosen"))
    }

    private func destinationChoice(_ folder: URL, detail: String?, title: String? = nil) -> some View {
        let chosen = tray.collectDestination?.standardizedFileURL.path == folder.standardizedFileURL.path
        let path = GatherDestination.abbreviated(folder)
        return Toggle(isOn: Binding(get: { chosen }, set: { _ in tray.chooseCollectDestination(folder) })) {
            Text(title ?? Self.folderName(folder))
            Text(detail.map { title == nil ? "\(path) · \($0)" : $0 } ?? path)
        }
    }

    private static func folderName(_ folder: URL) -> String {
        FileManager.default.displayName(atPath: folder.path)
    }

    /// After Collect: where the new folder went, and a way to see it. Gone with the next action.
    private func collectedNote(_ made: URL) -> some View {
        HStack(spacing: Space.s) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text(TrayController.collectedTitle(made, temporary: TrayTemporaryGroups.isOwned(made)))
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: Space.xs)
            Button("Show in Finder") { tray.revealCollected() }
                .buttonStyle(.link)
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
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
                // A selected row already stands out; a ring on top of the fill is one edge too many.
                .opacity(hasArrived && !isSelected ? 1 : 0)
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
        // The selection shows which row the keyboard is on, as in Finder's lists. The system ring
        // also landed on every clicked row, a heavy second outline around the selection.
        .focusEffectDisabled()
        .focused(focusedRow, equals: item.id)
        .onChange(of: isFocused) { _, focused in
            // Tab onto a row selects it. A click selects through the tap gesture below, which knows
            // about ⌘ and ⇧; selecting here as well turned every ⌘-click back into a plain click.
            guard focused, Motion.byKeyboard, !tray.selection.contains(item.id) else { return }
            tray.click(item, command: false, shift: false)
        }
        .onKeyPress(keys: [.upArrow, .downArrow]) { press in
            guard let index = tray.visibleItems.firstIndex(where: { $0.id == item.id }) else { return .ignored }
            let next = tray.visibleItems[min(max(index + (press.key == .upArrow ? -1 : 1), 0), tray.visibleItems.count - 1)]
            // Arrows select the next row, and ⇧-arrows extend the selection to it, as in Finder.
            tray.click(next, command: false, shift: press.modifiers.contains(.shift))
            focusedRow.wrappedValue = next.id
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
