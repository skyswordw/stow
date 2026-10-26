import SwiftUI

/// The Browser (#160): the archive's files and, beside them, Details, which is always there. The
/// title bar says which archive this is and how Checkup went. Floating glass controls sit over the
/// files: getting around and Search above them, and below them the whole archive's controls
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
    @FocusState private var isSearchFocused: Bool
    /// Archive Info, opened from Checkup or the title's menu.
    @State private var showsArchiveInfo = false
    /// How tall the floating controls are (taller while a failure card shows), so the files keep
    /// exactly that much room below their last row.
    @State private var floatingHeight: CGFloat = 62

    var body: some View {
        // Keep the navigation/search inset attached to one stable container as the file view changes.
        ZStack { content }
            .accessibilityElement(children: .contain)
            .accessibilitySortPriority(2)
            .archiveDrop(model: model, folder: model.folder)
            .frame(minWidth: Self.minFilesWidth)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    BrowserNavigation(model: model, isSearchFocused: $isSearchFocused)
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
                    else if model.editSession.isEdited { UnsavedChangesBar(model: model) }
                }
            }
            // Details is part of the window, not an option: no toggle, no close button.
            .inspector(isPresented: .constant(true)) {
                DetailsPane(model: model)
                    .accessibilityElement(children: .contain)
                    .accessibilitySortPriority(1)
                    .inspectorColumnWidth(min: 250, ideal: DetailsPane.idealWidth, max: 400)
            }
            // The window keeps its title (Window menu, Mission Control); the title bar shows
            // it as the archive's menu instead (`ArchiveTitleMenu`), with a visible chevron.
            .navigationTitle(model.title)
            .navigationSubtitle(model.subtitle)
            .toolbar(removing: .title)
            .toolbar { toolbar }
            // ⌘F (Edit › Find…) puts the keyboard in the search field.
            .onChange(of: model.searchFocusRequest) { isSearchFocused = true }
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
            ArchiveActions(model: model, prominent: !showsActions) { app.glance.collapse() }
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
        .padding(.horizontal, Space.l)
        .padding(.top, Space.s)
        .padding(.bottom, Space.l)
    }

    /// The title bar holds the archive itself: its name and menu (the title), how to look at it,
    /// and Checkup with the password beside it. Tray and New Archive aren't about this archive;
    /// they stay in the menu bar (Window › Show Tray ⌥⌘T, File › New Archive… ⌘N) and the Tray's
    /// menu-bar icon.
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            ArchiveTitleMenu(title: model.title, subtitle: model.subtitle) { titleMenu }
        }
        .sharedBackgroundVisibility(.hidden)

        ToolbarSpacer(.flexible)

        ToolbarItem {
            Picker("View", selection: $model.viewMode) {
                Label("Icons", systemImage: "square.grid.2x2").tag(BrowserModel.ViewMode.grid)
                Label("List", systemImage: "list.bullet").tag(BrowserModel.ViewMode.list)
                Label("Columns", systemImage: "rectangle.split.3x1").tag(BrowserModel.ViewMode.columns)
            }
            .pickerStyle(.segmented)
        }
        .overflowPriority(keepsVisible: false)

        // The archive's own state — safe or not, locked or not — always in reach.
        ToolbarItemGroup(placement: .primaryAction) {
            CheckupToolbarButton(model: model, isPresented: $showsArchiveInfo)
            if model.archive.isEncrypted {
                ArchiveUnlockControl(model: model, showsTitle: true)
            }
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
