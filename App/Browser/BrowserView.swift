import SwiftUI

/// The Browser (#160): the archive's files are the main surface, with the folder list and the
/// preview as optional panes either side. The title bar says which archive this is and how
/// Checkup went; the row above the files gets you around (folders, Back/Forward/Up, where you are,
/// Search, preview); the row below holds Glance and Extract All. Actions floats over the files for
/// the selection. Everything essential stays in reach with both panes closed.
struct BrowserView: View {
    @Bindable var model: BrowserModel
    @State private var editingDelegate = EditingWindowDelegate()
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SettingsKeys.nextStepsShown) private var showsNextSteps = true
    /// The folder list starts closed, for room; Folders (⌃⌘S) opens it, and it stays as it was left.
    @State private var columns: NavigationSplitViewVisibility = BrowserLayout.showsFolders ? .all : .detailOnly
    @FocusState private var isSearchFocused: Bool
    /// Archive Info, opened from Checkup or the title's menu.
    @State private var showsArchiveInfo = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            SidebarView(model: model)
                .accessibilityElement(children: .contain)
                .accessibilitySortPriority(3)
                .sidebarColumnWidth()
                // Folders, in the header row, opens and closes the list; no second toggle in the title bar.
                .toolbar(removing: .sidebarToggle)
        } detail: {
            content
                .accessibilityElement(children: .contain)
                .accessibilitySortPriority(2)
                .archiveDrop(model: model, folder: model.folder)
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        BrowserHeader(model: model, showsFolders: showsFolders, isSearchFocused: $isSearchFocused)
                        banners
                    }
                }
                // Actions takes real room above the bars: grid, list and columns scroll their last
                // row clear of it, and nothing is reserved while it's hidden.
                .safeAreaInset(edge: .bottom, spacing: 0) { nextSteps }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 0) {
                        if model.editSession.showsExternalChange { ExternalChangeBar(model: model) }
                        else if model.editSession.isEdited { UnsavedChangesBar(model: model) }
                        BrowserStatusBar(model: model, selectionHasActions: showsNextSteps && !model.selection.isEmpty) {
                            app.glance.collapse()
                        }
                    }
                }
                // The window keeps its title (Window menu, Mission Control); the title bar shows
                // it as the archive's menu instead (`ArchiveTitleMenu`), with a visible chevron.
                .navigationTitle(model.title)
                .navigationSubtitle(model.subtitle)
                .toolbar(removing: .title)
                // ⌘F (Edit › Find…) puts the keyboard in the header's search field.
                .onChange(of: model.searchFocusRequest) { isSearchFocused = true }
        }
        .inspector(isPresented: $model.showInspector) {
            InspectorView(model: model) { withTransaction(Motion.keyboardAware) { model.showInspector = false } }
                .accessibilityElement(children: .contain)
                .accessibilitySortPriority(1)
                .inspectorColumnWidth(min: 220, ideal: 280, max: 380)
        }
        .toolbar { toolbar }
        .onChange(of: columns) { _, visibility in BrowserLayout.remember(folders: visibility != .detailOnly) }
        .onChange(of: model.showInspector) { _, shown in BrowserLayout.remember(inspector: shown) }
        .onKeyPress(.escape) {
            if model.renamingPath != nil {
                model.renamingPath = nil
                return .handled
            }
            if model.quickLook.isActive {
                model.quickLook.close()
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

    private var showsFolders: Binding<Bool> {
        Binding { columns != .detailOnly } set: { columns = $0 ? .all : .detailOnly }
    }

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

    /// Notices about the listing itself, under the header row.
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
            // View-mode switches are keyboard-speed actions: no animation.
            switch model.isSearching && model.viewMode == .columns ? .list : model.viewMode {
            case .grid: ContentGrid(model: model)
            case .list: ContentList(model: model)
            case .columns: ContentColumns(model: model)
            }
        }
    }

    @ViewBuilder
    private var nextSteps: some View {
        let visible = (!model.selection.isEmpty && showsNextSteps) || model.activity != nil
        ZStack {
            if visible {
                NextStepsBar(model: model)
                    .accessibilityElement(children: .contain)
                    .accessibilitySortPriority(0)
                    .padding(.top, Space.s)
                    .padding(.bottom, Space.l)
                    .transition(.rise(reduceMotion: reduceMotion))
            }
        }
        // Never ask the column for the capsule's width: a minimum here feeds the split view's own
        // sizing and loops (the "Update Constraints in Window" crash).
        .frame(minWidth: 0, maxWidth: .infinity)
        // Springs in for a click, eases out faster, and doesn't move at all for arrow keys, ⌘A or Esc.
        .animation(Motion.presence(visible, reduceMotion: reduceMotion), value: visible)
    }

    /// The title bar holds the archive itself: its name and menu (the title), how to look at it,
    /// and Checkup with the password beside it. Getting around is the header row's job and Extract
    /// All the bottom row's. Tray and New Archive aren't about this archive; they stay in the menu
    /// bar (Window › Show Tray ⌥⌘T, File › New Archive… ⌘N) and the Tray's menu-bar icon.
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

        // The archive's own state — safe or not, locked or not — in reach with every pane closed.
        ToolbarItemGroup(placement: .primaryAction) {
            CheckupToolbarButton(model: model, isPresented: $showsArchiveInfo)
            if model.archive.isEncrypted {
                ArchiveUnlockControl(model: model, showsTitle: true)
            }
        }
        .overflowPriority(keepsVisible: true)
    }
}

/// Which optional Browser panes were last open. Remembered when people open or close one; a
/// design-review scene (`-StowScene`) reads only its own launch arguments and never saves, so
/// everyday use can't change a screenshot and a scene can't change everyday use.
enum BrowserLayout {
    static var showsFolders: Bool { flag(SettingsKeys.browserShowsFolders, default: false) }
    static var showsInspector: Bool { flag(SettingsKeys.browserShowsInspector, default: true) }

    static func remember(folders: Bool) { save(folders, for: SettingsKeys.browserShowsFolders) }
    static func remember(inspector: Bool) { save(inspector, for: SettingsKeys.browserShowsInspector) }

    private static var isScene: Bool { UserDefaults.standard.string(forKey: "StowScene") != nil }

    private static func flag(_ key: String, default value: Bool) -> Bool {
        let store = UserDefaults.standard
        guard isScene else { return store.object(forKey: key) == nil ? value : store.bool(forKey: key) }
        // Launch arguments arrive as strings ("YES") or numbers.
        switch store.volatileDomain(forName: UserDefaults.argumentDomain)[key] {
        case let flag as Bool: return flag
        case let number as NSNumber: return number.boolValue
        case let text as String: return ["yes", "true", "1"].contains(text.lowercased())
        default: return value
        }
    }

    private static func save(_ value: Bool, for key: String) {
        guard !isScene else { return }
        UserDefaults.standard.set(value, forKey: key)
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
