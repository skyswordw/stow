import SwiftUI

/// The Browser (#160): the archive's files and, beside them, Details, which is always there. The
/// title bar holds the archive identity and password access on the leading side, and at the
/// trailing end Search, the view modes and editing (Delete, Save) (#242).
/// Floating glass controls sit over the files: navigation above them, and the archive controls below
/// (Glance, Extract All) on the leading side and Actions on the trailing side: the selection's, or
/// with nothing selected, installing an archive that's one app.
/// There is no folder pane: the files, the path, Back, Forward, Up and Search get you everywhere.
struct BrowserView: View {
    @Bindable var model: BrowserModel
    @State private var editingDelegate = EditingWindowDelegate()
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SettingsKeys.nextStepsShown) private var showsNextSteps = true
    @AppStorage(SettingsKeys.nextStepsHidden) private var hiddenSteps = NextStepsSettings.encode(NextStepsSettings.defaultHidden)
    /// Whether Search has the keyboard. The field lives in the toolbar, which SwiftUI hosts apart
    /// from this view, so the field keeps its own focus state and mirrors it here (#231).
    @State private var isSearchFocused = false
    /// Archive Info, reachable from the title menu regardless of selection.
    @State private var showsArchiveInfo = false
    /// How tall the floating controls are (taller while a failure card shows), so the files keep
    /// exactly that much room below their last row.
    @State private var floatingHeight: CGFloat = 62
    /// The window's width, which the title bar shares between the archive's name and Search.
    @State private var windowWidth: CGFloat = 1100
    /// Search opened by its button or ⌘F; it closes again when it lets go of the keyboard empty.
    @State private var isSearchExpanded = false
    @State private var searchFocusRequest = 0
    /// Search's width as drawn: `titleBar.searchWidth`, stepped there while Search opens or closes.
    @State private var shownSearchWidth = TitleBarLayout.buttonWidth
    @State private var searchWasOpen = false
    @State private var searchWidthMove: Task<Void, Never>?

    var body: some View {
        // Keep the navigation inset attached to one stable container as the file view changes.
        ZStack { content }
            // An encrypted preview being read before Quick Look can show it.
            .overlay(alignment: .top) { QuickLookPreparingCapsule(model: model, passwords: app.passwords) }
            .accessibilityElement(children: .contain)
            .accessibilitySortPriority(2)
            .archiveDrop(model: model, folder: model.folder)
            .frame(minWidth: Self.minFilesWidth)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    BrowserNavigation(model: model)
                    banners
                }
            }
            // Room for the floating controls: grid, list and columns scroll their last row clear of
            // them, and the files show through around the glass.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear
                    .frame(height: floatingHeight)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            // The controls themselves float in an overlay over the files rather than in that inset,
            // so Actions can grow upward over the files when it fans out.
            .overlay(alignment: .bottom) {
                floatingControls
                    // While Actions is fanned out it rises over the files; the room below them stays
                    // the row's, so the list doesn't jump under the pointer.
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        if !model.isActionStackOpen { floatingHeight = height }
                    }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    if model.editSession.showsExternalChange { ExternalChangeBar(model: model) }
                    // Save is in the title bar; the bar says what's pending and offers Revert.
                    else if model.editSession.isEdited { UnsavedChangesBar(model: model, showsSave: false) }
                }
            }
            // Details is part of the window, not an option: no toggle, no close button.
            .inspector(isPresented: .constant(true)) {
                DetailsPane(model: model)
                    .accessibilityElement(children: .contain)
                    .accessibilitySortPriority(1)
                    .inspectorColumnWidth(min: 250, ideal: DetailsPane.idealWidth, max: 400)
            }
            // The whole window's width, Details included: the title bar spans it (`TitleBarLayout`).
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { windowWidth = $0 }
            // The window keeps its title (Window menu, Mission Control); the title bar shows
            // it as the archive's menu instead (`ArchiveTitleMenu`), with a visible chevron.
            .navigationTitle(model.title)
            .navigationSubtitle(model.subtitle)
            .toolbar(removing: .title)
            // The title bar is the window's background, as the floating path and capsules assume
            // (#242). macOS 27.2 started drawing a bar with a hairline under it by default.
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .toolbar { toolbar }
            // ⌘F (Edit › Find…) puts the keyboard in the search field.
            .onChange(of: model.searchFocusRequest) { activateSearch() }
            .onChange(of: isSearchFocused) { _, focused in if !focused { isSearchExpanded = false } }
            .onChange(of: titleBar.searchWidth, initial: true) { _, target in followSearchWidth(target) }
            .onKeyPress(.escape) {
                if model.renamingPath != nil {
                    model.renamingPath = nil
                    return .handled
                }
                if model.quickLook.isActive {
                    model.quickLook.close()
                    return .handled
                }
                // The innermost thing first: a fanned-out Actions stack folds before the selection goes.
                if model.isActionStackOpen {
                    model.isActionStackOpen = false
                    return .handled
                }
                guard !model.selection.isEmpty else { return .ignored }
                model.select([])
                return .handled
            }
            .onChange(of: model.selection) { model.quickLook.selectionChanged() }
            .sheet(isPresented: $model.isChoosingEncoding) { EncodingSheet(model: model) }
            .editingNotice(model, isActive: !app.glance.isShown) { app.extractAndRepack(model) }
            .background {
                WindowReader { window in
                    editingDelegate.attach(window, model: model)
                    model.quickLook.attach(to: window)
                    model.dragOut.install(in: window)
                    app.glance.prepareMainWindow(window)
                }
                .id(ObjectIdentifier(model))
            }
    }

    private var isSearchOpen: Bool { isSearchExpanded || isSearchFocused || !model.query.isEmpty }

    private var titleBar: TitleBarLayout {
        TitleBarLayout(windowWidth: windowWidth, isSearchOpen: isSearchOpen,
                       isEncrypted: model.archive.isEncrypted, saveShowsTitle: model.editSession.canSave)
    }

    /// Opening or closing Search moves its width over a few frames (`SearchWidthMotion`); a window
    /// resize, ⌘F or Reduce Motion sets it at once.
    private func followSearchWidth(_ target: CGFloat) {
        let open = isSearchOpen
        let toggled = open != searchWasOpen
        searchWasOpen = open
        searchWidthMove?.cancel()
        searchWidthMove = nil
        guard toggled, let duration = SearchWidthMotion.duration(opening: open, byKeyboard: Motion.byKeyboard,
                                                                reduceMotion: reduceMotion) else {
            shownSearchWidth = target
            return
        }
        let start = shownSearchWidth
        searchWidthMove = Task { @MainActor in
            let began = ContinuousClock.now
            while !Task.isCancelled {
                let fraction = (ContinuousClock.now - began) / .seconds(duration)
                shownSearchWidth = start + (target - start) * SearchWidthMotion.progress(fraction)
                if fraction >= 1 { break }
                try? await Task.sleep(for: .milliseconds(8))
            }
        }
    }

    /// Opens Search, then gives it the keyboard once the field exists.
    private func activateSearch() {
        withAnimation(Motion.current(Motion.appear)) { isSearchExpanded = true }
        Task { @MainActor in
            await Task.yield()
            isSearchFocused = true
            searchFocusRequest += 1
        }
    }

    private var searchPrompt: String {
        model.indexingProgress ?? String(localized: "Search \(model.archive.files.count) files")
    }

    /// Room for the files, their columns and the floating controls before Details gives way.
    static let minFilesWidth: CGFloat = 480

    /// The title's menu: the archive as a whole.
    @ViewBuilder
    private var titleMenu: some View {
        Button("Archive Info", systemImage: "info.circle") { showsArchiveInfo = true }
        if let url = model.levels.first?.archive.source?.url {
            Button("Show in Finder", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
        Button("Rename Archive…", systemImage: "pencil") { Task { await model.renameArchive() } }
            .disabled(model.archive.source == nil || model.editSession.isSaving || model.levels.count != 1)
        Divider()
        Button("Close Archive", systemImage: "xmark") { app.closeArchive() }
    }

    /// Notices about the listing itself, under the navigation row.
    @ViewBuilder
    private var banners: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            ArchiveNotices(findings: model.archive.checkup)
            if !model.legacyNames.isEmpty { LegacyNamesBanner(model: model) }
            if let summary = model.searchCoverageSummary {
                DisclosureGroup {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Space.s) {
                            ForEach(model.searchOmissions) { omission in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(verbatim: omission.container.path)
                                        Text(omission.reason.description)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Locate") { model.locateSearchOmission(omission) }
                                        .accessibilityLabel(String(localized: "Locate \(omission.container.path)"))
                                        .help("Show this archive in its folder without opening it")
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 180)
                } label: {
                    Text(summary)
                }
                .padding(Space.s)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isSearching, model.visibleEntries.isEmpty {
            NoSearchResultsView(model: model)
        } else if model.visibleEntries.isEmpty, model.folder.isEmpty || model.viewMode != .columns {
            EmptyContentView(model: model) { app.isChoosingArchive = true }
        } else {
            // View-mode switches are keyboard-speed actions: no animation. Search keeps the
            // keyboard when results appear or clearing it restores Columns.
            switch model.isSearching && model.viewMode == .columns ? .list : model.viewMode {
            case .grid: ContentGrid(model: model, isSearchFocused: $isSearchFocused)
            case .list: ContentList(model: model, isSearchFocused: $isSearchFocused)
            case .columns: ContentColumns(model: model, isSearchFocused: $isSearchFocused)
            }
        }
    }

    /// The glass along the bottom: the whole archive on the leading side, Actions on the trailing
    /// side. One prominent action at a time: Extract All carries the accent until Actions shows,
    /// for a selection or, with nothing selected, to install an archive that's one app.
    @ViewBuilder
    private var floatingControls: some View {
        let installsArchive = showsNextSteps && NextStepsSettings(hidden: NextStepsSettings.decode(hiddenSteps))
            .archiveLayout(installable: model.archiveTarget).front != nil
        let showsActions = (!model.selection.isEmpty && showsNextSteps) || model.activity != nil || installsArchive
        HStack(alignment: .bottom, spacing: Space.s) {
            ArchiveActions(model: model, prominent: !showsActions, switchTo: .glance { app.glance.collapse() })
                .accessibilitySortPriority(0.5)
            Spacer(minLength: 0)
            ZStack {
                if showsActions {
                    NextStepsBar(model: model)
                        .accessibilityElement(children: .contain)
                        .accessibilitySortPriority(0)
                        .transition(.rise(reduceMotion: reduceMotion))
                }
            }
            // Springs in for a click, eases out faster, and doesn't move at all for arrow keys, ⌘A or Esc.
            .animation(Motion.presence(showsActions, reduceMotion: reduceMotion), value: showsActions)
        }
        // The same distance from the window's edges as the path above and Details beside (#242).
        .padding(.horizontal, FloatingGlass.edgeInset)
        .padding(.top, Space.s)
        .padding(.bottom, FloatingGlass.edgeInset)
    }

    /// The title bar (#242): the archive itself on the leading side (its name and menu, then its
    /// password control), and what you do with it grouped at the trailing end: Search, the view
    /// modes, then Delete · Save. Search starts as a magnifying glass and opens leftward into the
    /// room the name leaves, so the controls after it never move. Tray and New Archive aren't about
    /// this archive; they stay in the menu bar (Window › Show Tray ⌥⌘T, File › New Archive… ⌘N)
    /// and the Tray's menu-bar icon.
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            ArchiveTitleMenu(title: model.title, subtitle: model.subtitle, maxWidth: titleBar.titleMaxWidth) { titleMenu }
                .popover(isPresented: $showsArchiveInfo, arrowEdge: .bottom) {
                    ArchiveInfoPopover(model: model)
                }
                .task {
                    guard ArchiveInfoView.opensForDemo else { return }
                    try? await Task.sleep(for: .milliseconds(500))
                    showsArchiveInfo = true
                }
        }
        .sharedBackgroundVisibility(.hidden)
        // The archive's identity is the last thing to go.
        .overflowPriority(keepsVisible: true)

        // Password access belongs to the archive, so it follows its name, as Glance's lock does.
        if model.archive.isEncrypted {
            ToolbarItem(placement: .navigation) {
                ArchiveUnlockControl(model: model)
            }
            .overflowPriority(keepsVisible: true)
        }

        ToolbarSpacer(.flexible)

        // First of the trailing group, so it has the title bar's free room to open into.
        ToolbarItem {
            ToolbarSearchField(query: $model.query, prompt: searchPrompt, isFocused: $isSearchFocused,
                               focusRequest: searchFocusRequest, width: shownSearchWidth,
                               isOpen: isSearchOpen, activate: activateSearch)
        }
        .overflowPriority(keepsVisible: true)

        ToolbarSpacer(.fixed)

        ToolbarItem {
            Picker("View", selection: $model.viewMode) {
                Label("Icons", systemImage: "square.grid.2x2").tag(BrowserModel.ViewMode.grid)
                Label("List", systemImage: "list.bullet").tag(BrowserModel.ViewMode.list)
                Label("Columns", systemImage: "rectangle.split.3x1").tag(BrowserModel.ViewMode.columns)
            }
            .pickerStyle(.segmented)
        }
        .overflowPriority(keepsVisible: false)

        // Editing gets its own capsule, apart from the view modes, so the first edit
        // changes only that capsule.
        ToolbarSpacer(.fixed)

        // Editing, there before the first edit (#216): Delete for the selection, Save for the
        // archive. Both are always shown; they say when there's nothing to do by being disabled.
        ToolbarItemGroup {
            ArchiveEditingControls(model: model)
        }
        .overflowPriority(keepsVisible: true)
    }
}

/// Hands over the hosting window once it exists (for the responder chain and drag sessions).
struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView { Reader(onWindow: onWindow) }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class Reader: NSView {
        let onWindow: (NSWindow) -> Void
        init(onWindow: @escaping (NSWindow) -> Void) {
            self.onWindow = onWindow
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError() }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onWindow(window) }
        }
    }
}

/// Archive Info from the title menu: as tall as what it says, up to 420 pt, then it scrolls.
/// (A fixed 420 pt left half the popover empty for an ordinary archive.)
private struct ArchiveInfoPopover: View {
    let model: BrowserModel
    static let maxHeight: CGFloat = 420
    /// Measured from the content; the cap until the first measurement.
    @State private var contentHeight: CGFloat = Self.maxHeight

    var body: some View {
        ScrollView {
            ArchiveInfoView(model: model)
                .padding(Space.l)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: 320, height: min(contentHeight, Self.maxHeight))
    }
}
