import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A new archive that isn't written yet (#293), in the Browser's workspace (#302), as ArcZip's
/// new archive is its browser with nothing in it yet: the name and format where the Browser names
/// its archive; Search, the view modes and Delete · Pack… where the Browser has Search, the view
/// modes and Delete · Save; the path capsule with Back, Forward and Up; Icons, List and Columns;
/// Add Files… where Extract All floats; and Details beside the files with the real sources'
/// facts — never a packed size or a password before Pack has made them. Nothing on disk changes
/// until the pack succeeds; the originals never do. DESIGN.md › New archive draft.
struct ArchiveDraftView: View {
    @Bindable var draft: ArchiveDraft
    @Environment(AppState.self) private var app
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.reducesMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var delegate = CreationWindowDelegate()
    /// The planned contents as a tree, rebuilt only when the files change (not on every selection).
    @State private var tree: [DraftNode] = []
    /// Top-level items an add (or an Undo) just brought in: ringed in the accent for a moment, as
    /// in the Tray.
    @State private var arrived: Set<String> = []
    @State private var isTargeted = false
    @State private var isPromiseTargeted = false
    /// The list takes the keyboard when it appears, as the Browser's files do.
    @FocusState private var listFocused: Bool
    /// Search in the title bar, as the Browser keeps it (`BrowserView`).
    @State private var isSearchFocused = false
    @State private var isSearchExpanded = false
    @State private var searchFocusRequest = 0
    @State private var windowWidth: CGFloat = 980

    private var browsing: DraftBrowsing { draft.browsing }
    private var isSearchOpen: Bool { isSearchExpanded || isSearchFocused || !browsing.query.isEmpty }
    private var titleBar: TitleBarLayout {
        TitleBarLayout(windowWidth: windowWidth, isSearchOpen: isSearchOpen, saveShowsTitle: !isEmpty)
    }

    private var contrastStyle: ContrastStyle { .resolve(contrast) }
    private var highlighted: Bool { isTargeted || isPromiseTargeted }
    private var isEmpty: Bool { draft.files.isEmpty }
    private var isBusy: Bool { draft.isImporting || draft.isSaving }
    private var canAdd: Bool { !draft.isImporting && !draft.isChoosingSources && !draft.isSaving }

    var body: some View {
        files
            .frame(minWidth: BrowserView.minFilesWidth)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    DraftNavigation(browsing: browsing, archiveName: draft.fileName)
                        .disabled(isEmpty)
                    banner
                }
            }
            // Room for the floating glass, so the last row scrolls clear of it.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear
                    .frame(height: isEmpty && !draft.isSaving ? 0 : Self.floatingHeight)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .overlay(alignment: .bottom) { floatingControls }
            // The whole files column takes drops, the path and the floating glass included; the
            // list's table takes its own (see `list`).
            .dropDestination(for: URL.self) { urls, _ in
                guard canAdd else { return false }
                Task { await draft.add(urls) }
                return true
            } isTargeted: { isTargeted = $0 }
            // Details is part of the window, as in the Browser: no toggle, no close button.
            .inspector(isPresented: .constant(true)) {
                DraftDetails(draft: draft)
                    .accessibilitySortPriority(1)
                    .inspectorColumnWidth(min: 250, ideal: DetailsPane.idealWidth, max: 400)
            }
            // The window keeps its title for the Window menu and Mission Control; the title bar
            // shows the editable name instead.
            .navigationTitle(draft.name.isEmpty ? String(localized: "Untitled Archive") : draft.name)
            .toolbar(removing: .title)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .toolbar { toolbar }
            .animation(Motion.byKeyboard ? nil : Motion.resolved(Motion.status, reduceMotion: reduceMotion), value: isEmpty)
            .animation(Motion.presence(draft.isSaving, reduceMotion: reduceMotion), value: draft.isSaving)
            // Drags that only promise a file (Mail, Photos, chat apps) land anywhere in the window.
            .onDrop(of: OtherAppFiles.promisedTypes, isTargeted: $isPromiseTargeted) { providers in
                guard canAdd else { return false }
                draft.receivePromises(providers)
                return true
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { windowWidth = $0 }
            .onChange(of: browsing.searchFocusRequest) { activateSearch() }
            .onChange(of: isSearchFocused) { _, focused in if !focused { isSearchExpanded = false } }
            .onKeyPress(.escape) {
                if browsing.isSearching {
                    browsing.query = ""
                    return .handled
                }
                guard !draft.selection.isEmpty else { return .ignored }
                draft.selection = []
                return .handled
            }
            .onChange(of: draft.files, initial: true) { old, new in
                tree = browsing.roots
                DraftFacts.invalidate(for: old + new)
                noteArrivals(old: old, new: new)
            }
            .background {
                WindowReader { window in
                    delegate.attach(window, draft: draft) {
                        if app.archiveDraft === draft { app.archiveDraft = nil }
                    }
                }
            }
            .sheet(item: $draft.packRequest, onDismiss: {
                if !draft.isSaving { draft.quitAfterSave = false }
            }) { request in
                PackSheet(request: request, draft: draft) { urls in
                    let quitting = draft.quitAfterSave
                    dismissWindow(id: "creation")
                    if app.archiveDraft === draft { app.archiveDraft = nil }
                    if quitting { NSApp.terminate(nil) }
                    else if let first = urls.first {
                        app.open(first)
                        app.showMainWindow()
                    }
                }.environment(app)
            }
    }

    /// The floating row's height and the gaps around it, as the Browser reserves under its files.
    private static let floatingHeight = FloatingGlass.barHeight + Space.s + FloatingGlass.edgeInset

    // MARK: Title bar

    /// The Browser's arrangement: the archive itself on the leading side, editing at the trailing
    /// end. Remove · Pack… share one capsule as Delete · Save do, and Pack takes the accent and its
    /// name once there's something to pack, as Save does once there's something to save.
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            DraftTitle(draft: draft, subtitle: subtitle)
                .disabled(draft.isSaving)
        }
        .sharedBackgroundVisibility(.hidden)

        ToolbarSpacer(.flexible)

        ToolbarItem {
            ToolbarSearchField(query: Bindable(browsing).query, prompt: String(localized: "Search \(tree.isEmpty ? 0 : browsing.nodes.count) files"),
                               isFocused: $isSearchFocused, focusRequest: searchFocusRequest,
                               width: titleBar.searchWidth, isOpen: isSearchOpen, activate: activateSearch, close: {
                                   browsing.query = ""
                                   isSearchFocused = false
                                   isSearchExpanded = false
                               })
                .disabled(isEmpty)
        }

        ToolbarSpacer(.fixed)

        ToolbarItem {
            Picker("View", selection: Bindable(browsing).viewMode) {
                Label("Icons", systemImage: "square.grid.2x2").tag(BrowserModel.ViewMode.grid)
                Label("List", systemImage: "list.bullet").tag(BrowserModel.ViewMode.list)
                Label("Columns", systemImage: "rectangle.split.3x1").tag(BrowserModel.ViewMode.columns)
            }
            .pickerStyle(.segmented)
        }

        ToolbarSpacer(.fixed)

        // Delete · Pack…, in the Browser's Delete · Save capsule. Delete takes items out of the plan
        // (Edit › Delete, ⌘⌫); the originals are never touched, and Undo puts them back.
        ToolbarItemGroup {
            Button {
                draft.removeSelection()
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(draft.selection.isEmpty || isBusy)
            .help(draft.selection.isEmpty ? String(localized: "Select files to take them out of this archive")
                  : String(localized: "Take the selection out of this archive. The originals stay where they are."))
            .accessibilityLabel(String(localized: "Delete"))

            Group {
                if isEmpty {
                    packButton.disabled(true)
                } else {
                    // Says its name once there's something to pack: an icon alone in a filled
                    // circle reads as a pressed button.
                    packButton
                        .labelStyle(.titleAndIcon)
                        .buttonStyle(.borderedProminent)
                        .disabled(!draft.canSave || app.packing.isRunning)
                }
            }
            .help(isEmpty ? String(localized: "Add files to pack this archive")
                  : String(localized: "Choose how to pack it and where to put it"))
            .accessibilityLabel(String(localized: "Pack…"))
        }
    }

    /// Opens Search, then gives it the keyboard once the field exists (as the Browser does).
    private func activateSearch() {
        guard !isEmpty else { return }
        withAnimation(Motion.current(Motion.appear)) { isSearchExpanded = true }
        Task { @MainActor in
            await Task.yield()
            isSearchFocused = true
            searchFocusRequest += 1
        }
    }

    /// Tray's Pack glyph: a box the files go into.
    private var packButton: some View {
        Button {
            draft.prepareSave()
        } label: {
            Label("Pack…", systemImage: "archivebox")
        }
    }

    /// Never a final size: these are the originals, before compression. The archive's own size is
    /// known only once it's packed.
    private var subtitle: String {
        if draft.isImporting { return String(localized: "Adding files…") }
        let unpacked = String(localized: "Not packed yet")
        guard !isEmpty else { return unpacked }
        let bytes = draft.files.reduce(Int64(0)) { $0 + ($1.isFolder ? 0 : $1.size) }
        return unpacked + " · " + DraftSummary.text(items: tree.count, bytes: bytes)
    }

    // MARK: Problem

    /// An add or a pack that went wrong, where the Browser shows its notices: under the title bar,
    /// over the files.
    @ViewBuilder private var banner: some View {
        if let problem = draft.problem {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .accessibilityHidden(true)
                Text(verbatim: problem)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Dismiss", systemImage: "xmark") {
                    withAnimation(Motion.presence(false, reduceMotion: reduceMotion)) { draft.problem = nil }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(contrastStyle.metadata)
            }
            .font(.callout)
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.s)
            .background(.yellow.opacity(0.12), in: .rect(cornerRadius: Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card)
                    .strokeBorder(.yellow.opacity(contrastStyle.increased ? 0.8 : 0.3))
            }
            .accessibilityElement(children: .contain)
            .padding(.horizontal, FloatingGlass.edgeInset)
            .padding(.top, FloatingGlass.topInset)
            .padding(.bottom, Space.s)
            .transition(.opacity.animation(Motion.byKeyboard ? nil : Motion.resolved(Motion.status, reduceMotion: reduceMotion)))
        }
    }

    // MARK: Files

    /// The files area. While something is held over the files column, an accent edge inset as far
    /// as Details is, with a light tint, says where it lands.
    private var files: some View {
        ZStack {
            if isEmpty {
                empty.transition(.opacity)
            } else if browsing.isSearching, browsing.visible.isEmpty {
                ContentUnavailableView.search(text: browsing.query)
            } else {
                // View-mode switches are keyboard-speed: no animation. Search lists its results,
                // as the Browser's Columns do.
                switch browsing.isSearching && browsing.viewMode == .columns ? .list : browsing.viewMode {
                case .grid: DraftGrid(draft: draft, browsing: browsing, arrived: arrived)
                        .takesKeyboard($listFocused, isSearchFocused: $isSearchFocused).draftKeys(draft)
                case .list: list
                case .columns: DraftColumns(draft: draft, browsing: browsing, arrived: arrived)
                        .takesKeyboard($listFocused, isSearchFocused: $isSearchFocused).draftKeys(draft)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            let shape = RoundedRectangle(cornerRadius: Radius.windowPanel, style: .continuous)
            shape.fill(.tint.opacity(0.06))
                .overlay { shape.strokeBorder(.tint, lineWidth: 2) }
                .padding(Radius.windowInset)
                .opacity(highlighted ? 1 : 0)
                .allowsHitTesting(false)
                .animation(Motion.resolved(Motion.target, reduceMotion: reduceMotion), value: highlighted)
        }
    }

    /// Nothing planned yet. A dashed edge where the files will be, the same shape and inset as
    /// Details beside it, says the space takes a drop; Add Files… is the window's one prominent
    /// button until there's something to pack.
    private var empty: some View {
        ContentUnavailableView {
            Label {
                Text(highlighted ? String(localized: "Let go to add") : String(localized: "Drop files and folders here"))
                    .contentTransition(.opacity)
            } icon: {
                Image(systemName: "archivebox")
            }
        } description: {
            Text("Or add them from anywhere on your Mac. Nothing is written until you pack, and the originals stay where they are.")
        } actions: {
            Button("Add Files…") { draft.chooseSources() }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(!canAdd)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: Radius.windowPanel, style: .continuous)
                .strokeBorder(contrastStyle.increased ? AnyShapeStyle(.secondary) : AnyShapeStyle(.separator),
                              style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
                .opacity(highlighted ? 0 : 1)
                .padding(.horizontal, Radius.windowInset)
                .padding(.top, FloatingGlass.topInset)
                .padding(.bottom, Radius.windowInset)
                .accessibilityHidden(true)
        }
    }

    /// The Browser's list and columns for the folder you're in — Name, Size, Kind and Modified, read
    /// from the real originals. A double-click opens a folder; while searching, each name says where
    /// it is.
    private var list: some View {
        ScrollViewReader { proxy in
            Table(of: DraftNode.self, selection: $draft.selection) {
                TableColumn(String(localized: "Name")) { node in
                    VStack(alignment: .leading, spacing: 0) {
                        DraftNameCell(node: node, hasArrived: arrived.contains(node.id), contrastStyle: contrastStyle)
                        if browsing.isSearching {
                            Text(verbatim: DraftDetails.location(of: node.file, archiveName: draft.fileName))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .padding(.leading, 18 + Space.s)
                        }
                    }
                    .id(node.id)
                }
                .width(min: 130, ideal: 320)

                TableColumn(String(localized: "Size")) { node in
                    Text(node.bytes.bytes)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .width(min: 70, ideal: 84, max: 110)
                .alignment(.trailing)

                TableColumn(String(localized: "Kind")) { node in
                    Text(DraftFacts.of(node.file).kind)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .width(min: 64, ideal: 150, max: 220)

                TableColumn(String(localized: "Modified")) { node in
                    if let modified = DraftFacts.of(node.file).modified {
                        Text(modified, format: .dateTime.day().month(.abbreviated).year())
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .width(min: ContentList.modifiedWidth, ideal: max(110, ContentList.modifiedWidth), max: 140)
            } rows: {
                // The table is its own AppKit view, so the window's drop target never sees drags over
                // it; files dropped on the list come through the table itself (checked with a real
                // drag from Finder). They join the top of the archive wherever they land.
                ForEach(browsing.visible) { TableRow($0) }
                    .dropDestination(for: URL.self) { _, urls in
                        guard canAdd else { return }
                        Task { await draft.add(urls) }
                    }
            }
            .alternatingRowBackgrounds(.disabled)
            .contextMenu(forSelectionType: String.self) { paths in
                DraftItemMenu(draft: draft, paths: paths)
            } primaryAction: { paths in
                if paths.count == 1, let path = paths.first, let node = browsing.nodes[path] {
                    draft.open(node)
                }
            }
            .disabled(isBusy)
            .focused($listFocused)
            .onAppear { if !isSearchFocused { listFocused = true } }
            // The files hold the keyboard, not the name or Search, when the window opens (#215).
            .filesTakeKeyboard($listFocused, isSearchFocused: $isSearchFocused)
            .draftKeys(draft, handlesArrows: false)
            // What an add brought in may be below the fold: bring the last of it into view.
            .onChange(of: arrived) { _, arrived in
                guard let last = browsing.visible.last(where: { arrived.contains($0.id) }) else { return }
                withAnimation(reduceMotion ? nil : Motion.current(Motion.status)) { proxy.scrollTo(last.id) }
            }
        }
    }

    /// The glass along the bottom, as in the Browser: adding more at the leading corner, where the
    /// Browser's Extract All is, and packing's progress at the trailing one, where its activity
    /// shows. While the draft is empty the centred Add Files… is the only one.
    private var floatingControls: some View {
        HStack(alignment: .bottom, spacing: Space.s) {
            if !isEmpty {
                Button {
                    draft.chooseSources()
                } label: {
                    Label("Add Files…", systemImage: "plus")
                }
                .buttonStyle(ActionButtonStyle())
                .disabled(!canAdd)
                .help(String(localized: "Add more files and folders. You can also drop them on the list."))
                .padding(ActionButtonStyle.inset)
                .accessibleGlass(in: .capsule)
                .fixedSize()
                .transition(.opacity)
            }
            Spacer(minLength: 0)
            ZStack {
                if draft.isSaving, app.packing.activity != nil {
                    PackActivityBar(packing: app.packing)
                        .transition(.rise(reduceMotion: reduceMotion))
                }
            }
        }
        .padding(.horizontal, FloatingGlass.edgeInset)
        .padding(.top, Space.s)
        .padding(.bottom, FloatingGlass.edgeInset)
    }

    /// New top-level rows, from an add or from Undo putting a removal back. The ring comes at once
    /// and fades after 1.2 s (DESIGN.md › Motion, as the Tray's rows do).
    private func noteArrivals(old: [PackFile], new: [PackFile]) {
        let before = Set(old.lazy.filter { !$0.path.contains("/") }.map(\.path))
        let added = Set(new.lazy.filter { !$0.path.contains("/") }.map(\.path)).subtracting(before)
        guard !added.isEmpty else { return }
        // Adds land at the top of the archive: go there so they're seen arriving.
        if !browsing.folder.isEmpty || browsing.isSearching {
            browsing.query = ""
            browsing.go(to: "")
        }
        arrived = added
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard arrived == added else { return }
            withAnimation(Motion.resolved(Motion.status, reduceMotion: reduceMotion)) { arrived = [] }
        }
    }
}

/// The title bar's title for a draft, where the Browser names its archive: the name, which reads
/// as the title until it's clicked and then is a field; the format as the Pack sentence's token,
/// any format there and then, carried into Pack unchanged; and what's planned underneath, in the
/// Browser's subtitle place.
private struct DraftTitle: View {
    @Bindable var draft: ArchiveDraft
    let subtitle: String
    @Environment(\.reducesMotion) private var reduceMotion
    @FocusState private var nameFocused: Bool
    @State private var isHoveringName = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                nameField
                Token(title: "." + draft.format.fileExtension) {
                    ForEach(PackFormat.allCases) { format in
                        Button(format.displayName) { draft.format = format }
                    }
                }
                .accessibilityLabel(String(localized: "Archive Format"))
                .accessibilityValue(draft.format.displayName)
                .help(String(localized: "Choose the archive’s format. Pack starts with it."))
            }
            .font(.headline)
            HStack(spacing: Space.xs) {
                if draft.isImporting { ProgressView().controlSize(.mini) }
                Text(subtitle).liveNumber()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .animation(Motion.byKeyboard ? nil : Motion.resolved(Motion.token, reduceMotion: reduceMotion), value: draft.format)
    }

    /// As wide as the name (up to the Browser title's width), so the format follows straight after it.
    private var nameField: some View {
        let placeholder = String(localized: "Untitled Archive")
        return Text(verbatim: draft.name.isEmpty ? placeholder : draft.name)
            .lineLimit(1)
            .hidden()
            // Its ideal width is the name's, held between these; a longer name scrolls in the field.
            .frame(minWidth: 60, maxWidth: TitleBarLayout.titleMaximum - 80, alignment: .leading)
            .fixedSize(horizontal: true, vertical: false)
            .overlay {
                TextField("Archive Name", text: $draft.name, prompt: Text(placeholder))
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    // A title-bar field draws its text dimmed by default; this is the window's title.
                    .foregroundStyle(.primary)
                    .focused($nameFocused)
                    .onSubmit { nameFocused = false }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background {
                // Hover and editing show it's a field; at rest it's the window's title.
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(nameFocused ? AnyShapeStyle(.background) : AnyShapeStyle(.primary.opacity(isHoveringName ? 0.06 : 0)))
            }
            .focusRing(in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .onHover { isHoveringName = $0 }
            .padding(.leading, -4)
            .help(String(localized: "Rename the archive"))
    }
}

/// A planned item's name: the real file's Finder icon, its name, and a link's arrow.
private struct DraftNameCell: View {
    let node: DraftNode
    let hasArrived: Bool
    let contrastStyle: ContrastStyle

    var body: some View {
        HStack(spacing: Space.s) {
            DraftIcon(file: node.file)
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
            Text(verbatim: node.name)
                .lineLimit(1)
                .truncationMode(.middle)
            if node.file.isLink {
                Image(systemName: "arrow.turn.up.right")
                    .font(.caption)
                    .foregroundStyle(contrastStyle.metadata)
                    .help(String(localized: "Symbolic link"))
                    .accessibilityLabel(String(localized: "Symbolic link"))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 3)
        .background(hasArrived ? AnyShapeStyle(.tint.opacity(0.08)) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 5))
        .overlay {
            // A ring rather than a fill, so it never reads as the selection.
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(.tint, lineWidth: 1.5)
                .opacity(hasArrived ? 1 : 0)
                .allowsHitTesting(false)
        }
        .padding(.horizontal, -3)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// The file's own Finder icon, read once per path.
struct DraftIcon: View {
    let file: PackFile
    @MainActor private static var cache: [String: NSImage] = [:]

    var body: some View {
        if let url = file.source {
            Image(nsImage: Self.icon(for: url))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            NativeIcon(type: file.isFolder ? .folder : .data)
        }
    }

    private static func icon(for url: URL) -> NSImage {
        if let hit = cache[url.path] { return hit }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache[url.path] = icon
        return icon
    }
}

/// What Finder says about a planned item's original: its kind and when it last changed. Read once
/// per path, when a row or Details first shows it.
enum DraftFacts {
    struct Facts {
        var kind: String
        var modified: Date?
    }
    @MainActor private static var cache: [String: Facts] = [:]

    /// A new import or Undo can refer to changed originals at a previously displayed path.
    @MainActor static func invalidate(for files: [PackFile]) {
        for file in files { if let source = file.source { cache.removeValue(forKey: source.path) } }
    }

    @MainActor static func of(_ file: PackFile) -> Facts {
        guard let url = file.source else {
            return Facts(kind: file.isFolder ? String(localized: "Folder") : "")
        }
        if let hit = cache[url.path] { return hit }
        let values = try? url.resourceValues(forKeys: [.localizedTypeDescriptionKey, .contentModificationDateKey])
        let facts = Facts(kind: values?.localizedTypeDescription ?? (file.isFolder ? String(localized: "Folder") : ""),
                          modified: values?.contentModificationDate)
        cache[url.path] = facts
        return facts
    }
}

/// "4 items · 12.4 MB before compression": what a draft plans to pack, never what it will weigh.
enum DraftSummary {
    static func text(items: Int, bytes: Int64) -> String {
        String(localized: "\(items) items") + " · " + String(localized: "\(bytes.bytes) before compression")
    }
}

/// An item in the draft's planned contents, with what's inside it.
struct DraftNode: Identifiable {
    let file: PackFile
    var children: [DraftNode]?
    /// Everything inside a folder, at any depth.
    var count = 0
    /// The originals' size before compression: a file's own, or everything inside a folder.
    var bytes: Int64 = 0
    var id: String { file.path }
    var name: String { file.path.split(separator: "/").last.map(String.init) ?? file.path }

    /// Folders come before what's in them (the draft lists them that way); top-level items keep
    /// the order they were added in, and the inside of a folder sorts as Finder does by name.
    static func tree(from files: [PackFile]) -> [DraftNode] {
        final class Builder {
            let file: PackFile
            var children: [Builder] = []
            init(_ file: PackFile) { self.file = file }
            func node() -> DraftNode {
                guard file.isFolder else { return DraftNode(file: file, bytes: file.size) }
                let nodes = children.map { $0.node() }
                    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                return DraftNode(file: file, children: nodes.isEmpty ? nil : nodes,
                                 count: nodes.reduce(nodes.count) { $0 + $1.count },
                                 bytes: nodes.reduce(Int64(0)) { $0 + $1.bytes })
            }
        }
        var byPath: [String: Builder] = [:]
        var roots: [Builder] = []
        for file in files {
            let builder = Builder(file)
            byPath[file.path] = builder
            if let slash = file.path.lastIndex(of: "/"), let parent = byPath[String(file.path[..<slash])] {
                parent.children.append(builder)
            } else {
                roots.append(builder)
            }
        }
        return roots.map { $0.node() }
    }
}

extension PackFormat {
    /// The type Finder draws this format's documents with (the last part of a double extension).
    var contentType: UTType {
        let last = fileExtension.split(separator: ".").last.map(String.init) ?? fileExtension
        return UTType(filenameExtension: last) ?? .archive
    }
}

final class CreationWindowDelegate: NSObject, NSWindowDelegate {
    weak var draft: ArchiveDraft?
    private weak var window: NSWindow?
    private var original: (any NSWindowDelegate)?
    private var didClose: () -> Void = {}

    func attach(_ window: NSWindow, draft: ArchiveDraft, didClose: @escaping () -> Void) {
        self.draft = draft
        self.didClose = didClose
        window.isDocumentEdited = draft.isEdited
        if let previous = self.window, previous !== window, previous.delegate === self {
            previous.delegate = original
        }
        self.window = window
        if window.delegate !== self {
            original = (window.delegate as? CreationWindowDelegate)?.original ?? window.delegate
            window.delegate = self
        }
    }

    isolated deinit {
        if let window, window.delegate === self { window.delegate = original }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let draft else { return true }
        guard !draft.isSaving, sender.attachedSheet == nil else { return false }
        return draft.allowDiscardOrSave()
    }

    func windowWillClose(_ notification: Notification) {
        draft?.close()
        didClose()
        original?.windowWillClose?(notification)
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { draft?.undoManager }

    nonisolated override func responds(to selector: Selector!) -> Bool {
        if super.responds(to: selector) { return true }
        return MainActor.assumeIsolated { original?.responds(to: selector) == true }
    }
    private nonisolated struct DelegateBox: @unchecked Sendable { let delegate: (any NSWindowDelegate)? }
    nonisolated override func forwardingTarget(for selector: Selector!) -> Any? {
        MainActor.assumeIsolated { DelegateBox(delegate: original) }.delegate
    }
}

private extension View {
    /// Icons and Columns hold the keyboard as the list does, so the window doesn't open with the
    /// name field or Search taking it (`filesTakeKeyboard`).
    func takesKeyboard(_ focus: FocusState<Bool>.Binding, isSearchFocused: Binding<Bool>) -> some View {
        focusable()
            .focusEffectDisabled()
            .focused(focus)
            .onAppear { if !isSearchFocused.wrappedValue { focus.wrappedValue = true } }
            .filesTakeKeyboard(focus, isSearchFocused: isSearchFocused)
    }
}
