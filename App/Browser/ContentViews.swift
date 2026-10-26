import AppKit
import SwiftUI

// MARK: - Grid

/// Fixed-size tiles in computed rows, so every tile's frame is known without measuring: keyboard
/// Up/Down, the marquee and scroll-into-view are arithmetic, and a lazy stack of rows keeps
/// 100,000 entries smooth.
struct GridMetrics {
    static let minimumTile: CGFloat = 128
    static let maximumTile: CGFloat = 176
    static let tileHeight: CGFloat = 158
    static let spacing = Space.l
    static let inset = Space.xl

    let columns: Int
    let tileWidth: CGFloat

    init(width: CGFloat) {
        let usable = max(width - Self.inset * 2, Self.minimumTile)
        columns = max(1, Int((usable + Self.spacing) / (Self.minimumTile + Self.spacing)))
        tileWidth = min(Self.maximumTile, (usable - Self.spacing * CGFloat(columns - 1)) / CGFloat(columns))
    }

    func rows(for count: Int) -> Int { (count + columns - 1) / columns }

    func frame(of index: Int) -> CGRect {
        CGRect(x: Self.inset + CGFloat(index % columns) * (tileWidth + Self.spacing),
               y: Self.inset + CGFloat(index / columns) * (Self.tileHeight + Self.spacing),
               width: tileWidth, height: Self.tileHeight)
    }

    /// Tiles the rectangle touches, without visiting the ones it can't.
    func indices(in rect: CGRect, count: Int) -> [Int] {
        let rowSpan = Self.tileHeight + Self.spacing
        let first = max(0, Int((rect.minY - Self.inset) / rowSpan))
        let last = min(rows(for: count) - 1, Int((rect.maxY - Self.inset) / rowSpan))
        guard first <= last else { return [] }
        return (first...last).flatMap { row in
            (0..<columns).map { row * columns + $0 }.filter { $0 < count && frame(of: $0).intersects(rect) }
        }
    }
}

struct ContentGrid: View {
    @Bindable var model: BrowserModel
    var isSearchFocused: FocusState<Bool>.Binding
    @State private var hover = HoverPreviewModel()
    @State private var marquee: (start: CGPoint, current: CGPoint, base: Set<ArchiveEntry.ID>, toggling: Bool)?
    @FocusState private var isFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            let metrics = GridMetrics(width: proxy.size.width)
            let entries = model.visibleEntries
            ScrollViewReader { scroller in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: GridMetrics.spacing) {
                        ForEach(0..<metrics.rows(for: entries.count), id: \.self) { row in
                            HStack(alignment: .top, spacing: GridMetrics.spacing) {
                                ForEach(entries[row * metrics.columns..<min(entries.count, (row + 1) * metrics.columns)]) { entry in
                                    tile(entry)
                                        .frame(width: metrics.tileWidth, height: GridMetrics.tileHeight, alignment: .top)
                                }
                            }
                            .id(row)
                        }
                    }
                    .padding(GridMetrics.inset)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .topLeading)
                    .background { marqueeSurface(metrics, count: entries.count) }
                    .overlay(alignment: .topLeading) { marqueeRectangle }
                    .coordinateSpace(.named("grid"))
                }
                .onChange(of: model.scrollTarget) { _, target in
                    guard let target, let index = model.position(of: target) else { return }
                    // Keyboard-driven: no animation.
                    scroller.scrollTo(index / metrics.columns)
                    model.scrollTarget = nil
                }
            }
            .onAppear { model.gridColumns = metrics.columns }
            .onChange(of: metrics.columns) { _, columns in model.gridColumns = columns }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear { if !isSearchFocused.wrappedValue { isFocused = true } }
        .browserKeys(model)
        .onChange(of: model.demoHover, initial: true) { if let id = model.demoHover { hover.present(id) } }
    }

    private func tile(_ entry: ArchiveEntry) -> some View {
        GridTile(entry: entry, model: model,
                 isSelected: model.selection.contains(entry.id),
                 showsPath: model.isSearching)
            .onTapGesture(count: 2) { model.open(entry) }
            // Select immediately — don't make single clicks wait for double-click detection.
            .simultaneousGesture(TapGesture().onEnded {
                guard model.renamingPath == nil else { return }
                isFocused = true
                model.click(entry, modifiers: NSEvent.modifierFlags)
            })
            .hoverPreview(for: entry, model: hover, browser: model)
            .contextMenu { EntryMenu(model: model, entry: entry) }
            .archiveDrop(model: model, folder: entry.isNavigable ? entry.path : model.folder)
    }

    /// Clicking empty space clears the selection; dragging across it draws the marquee.
    private func marqueeSurface(_ metrics: GridMetrics, count: Int) -> some View {
        Color.clear
            .contentShape(.rect)
            .onTapGesture {
                isFocused = true
                model.select([])
            }
            .gesture(
                DragGesture(minimumDistance: 3, coordinateSpace: .named("grid"))
                    .onChanged { drag in
                        isFocused = true
                        if marquee == nil {
                            let flags = NSEvent.modifierFlags
                            let toggling = flags.contains(.command) || flags.contains(.shift)
                            marquee = (drag.startLocation, drag.location, toggling ? model.selection : [], toggling)
                        }
                        marquee?.current = drag.location
                        guard let marquee else { return }
                        let ids = metrics.indices(in: rectangle(marquee.start, marquee.current), count: count)
                            .map { model.visibleEntries[$0].id }
                        model.marquee(Set(ids), base: marquee.base, toggling: marquee.toggling)
                    }
                    .onEnded { _ in marquee = nil }
            )
    }

    @ViewBuilder
    private var marqueeRectangle: some View {
        if let marquee {
            let rect = rectangle(marquee.start, marquee.current)
            Rectangle()
                .fill(Color.accentColor.opacity(0.12))
                .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1)
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .allowsHitTesting(false)
        }
    }

    private func rectangle(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}

private struct GridTile: View {
    @Environment(\.colorSchemeContrast) private var contrast
    let entry: ArchiveEntry
    let model: BrowserModel
    let isSelected: Bool
    let showsPath: Bool

    var body: some View {
        VStack(spacing: Space.s) {
            LiveThumbnail(entry: entry, model: model)
                .frame(height: 84)
                .frame(maxWidth: .infinity)
                .padding(Space.s)
                .background(.primary.opacity(isSelected ? 0.08 : 0), in: .rect(cornerRadius: Radius.card))
                .overlay {
                    // Increase Contrast outlines the selection, so it reads by shape as well as by the
                    // tinted name; boxing every tile would make them all look selected.
                    RoundedRectangle(cornerRadius: Radius.card)
                        .strokeBorder(.primary.opacity(ContrastStyle.resolve(contrast).increased && isSelected ? 0.45 : 0))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .accessibilityHidden(true)
                .opacity(entry.isHelper ? 0.55 : 1)

            VStack(spacing: 2) {
                EditingName(model: model, entry: entry, showsState: false)
                    .font(.callout)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                    .background(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear),
                                in: .rect(cornerRadius: 5))
                detail
                    .font(.caption)
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.head)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(.rect)
        .archiveEntryAccessibility(entry: entry,
                                   isRenaming: model.renamingPath == entry.path) {
            model.select([entry.id])
            model.open(entry)
        }
    }

    /// Size (or where, while searching), then a staged edit's tag: "3.9 MB · Renamed".
    private var detail: Text {
        let base = Text(showsPath ? model.searchLocation(of: entry) : entry.size.bytes)
        guard let state = model.editSession.state(for: entry.path) else { return base }
        return Text("\(base) · \(Text(state).foregroundStyle(EditingTag.style(for: state)))")
    }
}

// MARK: - Keys

extension View {
    /// The browser's keyboard, shared by the icon grid and column view (the list's table brings
    /// its own arrows): arrows move (⇧ extends), Space is Quick Look, Return opens, letters jump.
    func browserKeys(_ model: BrowserModel) -> some View {
        self
            .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { press in
                guard press.modifiers.isDisjoint(with: [.command, .option, .control]) else { return .ignored }
                let direction: BrowserModel.Direction = switch press.key {
                case .upArrow: .up
                case .downArrow: .down
                case .leftArrow: .left
                default: .right
                }
                model.move(direction, extending: press.modifiers.contains(.shift))
                return .handled
            }
            .quickLookKeys(model)
            .onKeyPress(characters: .alphanumerics.union(.punctuationCharacters), phases: .down) { press in
                guard press.modifiers.isDisjoint(with: [.command, .option, .control]) else { return .ignored }
                guard model.renamingPath == nil else { return .ignored }
                model.typeSelect(press.characters)
                return .handled
            }
    }

    /// Space and Return, for every view mode.
    func quickLookKeys(_ model: BrowserModel) -> some View {
        self
            .onKeyPress(keys: [.delete], phases: .down) { press in
                guard model.renamingPath == nil, press.modifiers.isDisjoint(with: [.control, .option]), !model.selection.isEmpty else { return .ignored }
                model.editSession.delete(Array(model.selection))
                return .handled
            }
            .onKeyPress(.space) {
                guard model.renamingPath == nil else { return .ignored }
                model.toggleQuickLook()
                return .handled
            }
            .onKeyPress(.return) {
                guard model.renamingPath == nil else { return .ignored }
                let selected = model.selectedEntries
                guard selected.count == 1 else { return .ignored }
                model.open(selected[0])
                return .handled
            }
    }
}

// MARK: - List

struct ContentList: View {
    @Bindable var model: BrowserModel
    var isSearchFocused: FocusState<Bool>.Binding
    @State private var hover = HoverPreviewModel()
    /// Takes initial keyboard focus unless Search owns it: filtering can recreate this table
    /// while someone is typing (#177).
    @FocusState private var isFocused: Bool

    var body: some View {
        ScrollViewReader { scroller in
            Table(model.visibleEntries, selection: $model.selection) {
                TableColumn(String(localized: "Name")) { entry in
                    HStack(spacing: Space.s) {
                        RowIcon(entry: entry, model: model)
                            .accessibilityHidden(true)
                            .frame(width: 18, height: 18)
                        VStack(alignment: .leading, spacing: 0) {
                            EditingName(model: model, entry: entry).lineLimit(1)
                            if model.isSearching {
                                Text(model.searchLocation(of: entry))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .opacity(entry.isHelper ? 0.55 : 1)
                    .contentShape(.rect)
                    .archiveEntryAccessibility(entry: entry,
                                               isRenaming: model.renamingPath == entry.path) {
                        model.select([entry.id])
                        model.open(entry)
                    }
                    .hoverPreview(for: entry, model: hover, browser: model)
                    .archiveDrop(model: model, folder: entry.isNavigable ? entry.path : model.folder)
                }
                // The name takes whatever room the others leave; their maximums keep it that way.
                .width(min: 220, ideal: 320)

                TableColumn(String(localized: "Size")) { entry in
                    Text(entry.size.bytes)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .width(min: 70, ideal: 84, max: 110)
                .alignment(.trailing)

                TableColumn(String(localized: "Kind")) { entry in
                    Text(entry.kindDescription).foregroundStyle(.secondary).lineLimit(1)
                }
                .width(min: 80, ideal: 150, max: 220)

                TableColumn(String(localized: "Modified")) { entry in
                    Text(entry.modified, format: .dateTime.day().month(.abbreviated).year())
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .width(min: 90, ideal: 110, max: 140)
            }
            .contextMenu(forSelectionType: ArchiveEntry.ID.self) { ids in
                if let id = ids.first, let entry = model.archive.entry(at: id) {
                    EntryMenu(model: model, entry: entry)
                }
            } primaryAction: { ids in
                if ids.count == 1, let id = ids.first, let entry = model.archive.entry(at: id) {
                    model.open(entry)
                }
            }
            .alternatingRowBackgrounds(.disabled)
            .focused($isFocused)
            .onAppear { if !isSearchFocused.wrappedValue { isFocused = true } }
            .collapsesSelectionOnClick(model) { isSearchFocused.wrappedValue = false }
            .quickLookKeys(model)
            .onChange(of: model.selection) { model.selectionDidChange() }
            .onChange(of: model.demoHover, initial: true) { if let id = model.demoHover { hover.present(id) } }
            .onChange(of: model.scrollTarget) { _, target in
                guard let target else { return }
                scroller.scrollTo(target)
                model.scrollTarget = nil
            }
        }
    }
}

extension View {
    /// A plain click on one row of a multi-selection selects just that row, as in the grid (#169).
    /// Applied to a `Table` of `model.visibleEntries`.
    func collapsesSelectionOnClick(_ model: BrowserModel, onFocus: (() -> Void)? = nil) -> some View {
        background(TableClickSelection(model: model, onFocus: onFocus))
    }
}

/// SwiftUI's `Table` (macOS 27) loses this click: AppKit selects the row once the double-click
/// interval has passed, and SwiftUI writes an empty selection to the binding instead of that row.
/// Selecting the row through the model on mouse-up leaves AppKit's late change nothing to do.
/// Sits behind the table, so its frame says which clicks are the table's. Remove once #169's
/// steps keep the row without it.
struct TableClickSelection: NSViewRepresentable {
    let model: BrowserModel
    var onFocus: (() -> Void)?

    func makeNSView(context: Context) -> Watcher { Watcher(model: model, onFocus: onFocus) }
    func updateNSView(_ watcher: Watcher, context: Context) {
        watcher.model = model
        watcher.onFocus = onFocus
    }

    final class Watcher: NSView {
        var model: BrowserModel
        var onFocus: (() -> Void)?
        private var monitor: Any?
        /// The selected row a plain press landed on, while it can still become a click.
        private var press: (row: Int, point: NSPoint)?

        init(model: BrowserModel, onFocus: (() -> Void)? = nil) {
            self.model = model
            self.onFocus = onFocus
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
                // Local monitors run on the main thread, inside event dispatch.
                let box = TableEventBox(event: event)
                MainActor.assumeIsolated { self?.handle(box.event) }
                return event
            }
        }

        isolated deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }

        func handle(_ event: NSEvent) {
            guard let window, event.window === window else { return }
            guard event.type == .leftMouseDown else {
                guard let press else { return }
                self.press = nil
                // A drag (out of the window or across rows) isn't a click.
                let moved = hypot(event.locationInWindow.x - press.point.x, event.locationInWindow.y - press.point.y)
                let entries = model.visibleEntries
                guard moved <= 4, press.row < entries.count else { return }
                let id = entries[press.row].id
                // Once the table is done with this mouse-up.
                DispatchQueue.main.async { [model] in
                    guard model.renamingPath == nil, model.selection.count > 1, model.selection.contains(id) else { return }
                    model.select([id])
                }
                return
            }
            press = nil
            let entries = model.visibleEntries
            guard model.renamingPath == nil,
                  bounds.contains(convert(event.locationInWindow, from: nil)),
                  let table = table(at: event.locationInWindow, in: window) else { return }
            let row = table.row(at: table.convert(event.locationInWindow, from: nil))
            guard row >= 0 else { return }
            onFocus?()
            window.makeFirstResponder(table)
            guard event.clickCount == 1,
                  event.modifierFlags.isDisjoint(with: [.command, .shift, .option, .control]),
                  model.selection.count > 1,
                  // The rows are `visibleEntries`, in order, and the table shows the model's selection.
                  table.numberOfRows == entries.count,
                  table.selectedRowIndexes.count == model.selection.count,
                  table.selectedRowIndexes.allSatisfy({ model.selection.contains(entries[$0].id) }) else { return }
            guard table.selectedRowIndexes.contains(row) else { return }
            press = (row, event.locationInWindow)
        }

        private func table(at point: NSPoint, in window: NSWindow) -> NSTableView? {
            // The frame view has no superview, so window coordinates are its hit-test coordinates.
            var view = (window.contentView?.superview ?? window.contentView)?.hitTest(point)
            while let current = view, !(current is NSTableView) { view = current.superview }
            return view as? NSTableView
        }
    }
}

/// Events never leave the main thread here; the box only gets them through `assumeIsolated`.
private struct TableEventBox: @unchecked Sendable {
    let event: NSEvent
}

struct EntryMenu: View {
    let model: BrowserModel
    let entry: ArchiveEntry

    var body: some View {
        if let hit = model.nestedHits[entry.id] {
            // A search result inside an inner archive: go there first; nothing else reaches it.
            Button(String(localized: "Show in “\(hit.container.name)”"), systemImage: NextStep.openInside.symbol) {
                model.showNested(hit)
            }
            Divider()
            Button("Copy Name", systemImage: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.name, forType: .string)
            }
        } else {
            actions
        }
    }

    @ViewBuilder private var actions: some View {
        Button("Add Files…") { model.chooseAddFiles() }
            .disabled(model.editSession.format == nil || model.editSession.isSaving)
            .help(model.editSession.format == nil ? model.editSession.readOnlyReason : String(localized: "Add Files…"))
        Button("Rename") { model.beginRename(entry) }
            .disabled(model.editSession.format == nil || model.editSession.isSaving || model.editSession.refusal(for: [entry.path]) != nil)
            .help(model.editSession.refusal(for: [entry.path]) ?? (model.editSession.format == nil ? model.editSession.readOnlyReason : String(localized: "Rename")))
        Button("Replace…") { model.chooseReplacement(entry) }
            .disabled(entry.isFolder || model.editSession.format == nil || model.editSession.isSaving)
        Button("Delete") { model.editSession.delete(model.selection.contains(entry.id) ? Array(model.selection) : [entry.path]) }
            .disabled(model.editSession.format == nil || model.editSession.isSaving || model.editSession.refusal(for: [entry.path]) != nil)
            .help(model.editSession.refusal(for: [entry.path]) ?? (model.editSession.format == nil ? model.editSession.readOnlyReason : String(localized: "Delete")))
        Divider()
        let real = model.archive.source != nil
        if real, !entry.isFolder, entry.kind != .archive {
            Button("Open", systemImage: "arrow.up.forward.app") { model.openWithDefaultApp([entry]) }
        }
        if real, entry.isPackage || entry.kind == .archive || Self.zippedDocuments.contains((entry.name as NSString).pathExtension.lowercased()) {
            Button(entry.kind == .archive ? String(localized: "Open Inside") : String(localized: "Show Package Contents"), systemImage: "shippingbox") {
                model.showPackageContents(entry)
            }
        }
        if real {
            Button("Quick Look", systemImage: "eye") {
                if !model.selection.contains(entry.id) { model.select([entry.id]) }
                model.quickLook.show()
            }
            Divider()
        }
        let steps = NextStep.suggestions(for: [entry], dropTargets: model.archive.dropTargets).filter { !real || ($0 != .quickLook && $0 != .openInside) }
        ForEach(steps) { step in
            Button(step.title, systemImage: step.symbol) { model.run(step, on: [entry]) }
        }
        Divider()
        Button("Copy Name", systemImage: "doc.on.doc") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(entry.name, forType: .string)
        }
        if model.isSearching {
            Button("Show in Enclosing Folder", systemImage: "folder") {
                model.navigate(to: entry.parent, selecting: [entry.id])
            }
        }
    }

    /// Documents that are ZIP archives inside: their parts can be browsed like any archive.
    static let zippedDocuments: Set<String> = ["docx", "xlsx", "pptx", "epub", "odt", "ods", "odp", "pages", "key", "numbers"]
}
