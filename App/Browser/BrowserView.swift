import SwiftUI

struct BrowserView: View {
    @Bindable var model: BrowserModel
    @State private var editingDelegate = EditingWindowDelegate()
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 220, ideal: 248, max: 320)
                // Search sits at the top of the sidebar, beside the folders it searches across,
                // which keeps the inspector's toolbar section to just its toggle.
                .searchable(text: $model.query, placement: .sidebar, prompt: searchPrompt)
        } detail: {
            content
                .archiveDrop(model: model, folder: model.folder)
                .safeAreaInset(edge: .top, spacing: 0) {
                    if !model.legacyNames.isEmpty { LegacyNamesBanner(model: model) }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 0) {
                        if model.editSession.showsExternalChange { ExternalChangeBar(model: model) }
                        else if model.editSession.isEdited { UnsavedChangesBar(model: model) }
                        PathBar(model: model)
                    }
                }
                .overlay(alignment: .bottom) { nextSteps }
                .navigationTitle(model.title)
                .navigationSubtitle(model.subtitle)
        }
        .inspector(isPresented: $model.showInspector) {
            InspectorView(model: model)
                .inspectorColumnWidth(min: 240, ideal: 280, max: 360)
                // The toggle mirrors the sidebar's: at the inspector's leading edge, inside its own
                // toolbar section — never straddling the column divider. SwiftUI keeps it in the
                // toolbar while the inspector is collapsed, so it needs no second copy.
                .toolbar {
                    ToolbarItem { inspectorToggle }
                    ToolbarSpacer(.flexible)
                }
        }
        .toolbar { toolbar }
        .onKeyPress(.escape) {
            if model.quickLook.isVisible {
                model.quickLook.close()
                return .handled
            }
            guard !model.selection.isEmpty else { return .ignored }
            model.select([])
            return .handled
        }
        .onChange(of: model.selection) { model.quickLook.selectionChanged() }
        .sheet(isPresented: $model.isChoosingEncoding) { EncodingSheet(model: model) }
        .alert("Archive Editing", isPresented: Binding(get: { model.editSession.message != nil }, set: { if !$0 { model.editSession.message = nil } })) {
            Button("OK", role: .cancel) { model.editSession.message = nil }
        } message: { Text(model.editSession.message ?? "") }
        .alert(model.editSession.readOnlyReason, isPresented: Binding(get: { model.editSession.showsReadOnly }, set: { model.editSession.showsReadOnly = $0 })) {
            Button("Extract and Repack…") { app.extractAndRepack(model) }
            Button("OK", role: .cancel) { }
        }
        .onChange(of: model.level.id) {
            if let window = model.editingWindow { editingDelegate.attach(window, model: model) }
        }
        .background {
            WindowReader { window in
                editingDelegate.attach(window, model: model)
                model.quickLook.attach(to: window)
                model.dragOut.install(in: window)
                ToolbarPriority.install(in: window)
            }
            .id(ObjectIdentifier(model))
        }
    }

    private var searchPrompt: String {
        model.indexingProgress ?? String(localized: "Search \(model.archive.files.count.formatted()) files")
    }

    @ViewBuilder
    private var content: some View {
        if model.isSearching, model.visibleEntries.isEmpty {
            if let progress = model.indexingProgress {
                ContentUnavailableView(progress, systemImage: "magnifyingglass",
                                       description: Text("You can keep browsing while Stow finishes reading the names."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView {
                    Label("No files match “\(model.query)”", systemImage: "magnifyingglass")
                } description: {
                    Text("Stow looked in every folder of this archive. Check the spelling, or search for part of a name.")
                } actions: {
                    Button("Clear Search") { model.query = "" }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
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
        let visible = !model.selection.isEmpty || model.activity != nil
        ZStack {
            if visible {
                NextStepsBar(model: model)
                    .transition(.rise(reduceMotion: reduceMotion))
            }
        }
        .padding(.bottom, Space.l + PathBar.height + (model.editSession.isEdited ? 48 : 0))
        // Springs in for a click, eases out faster, and doesn't move at all for arrow keys, ⌘A or Esc.
        .animation(Motion.presence(visible, reduceMotion: reduceMotion), value: visible)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            ControlGroup {
                Button("Back", systemImage: "chevron.left") { model.goBack() }
                    .disabled(!model.canGoBack)
                    .help("See the previous place")
                Button("Forward", systemImage: "chevron.right") { model.goForward() }
                    .disabled(!model.canGoForward)
                    .help("See the next place")
            }
            .controlGroupStyle(.navigation)
        }

        ToolbarItem {
            Picker("View", selection: $model.viewMode) {
                Label("Icons", systemImage: "square.grid.2x2").tag(BrowserModel.ViewMode.grid)
                Label("List", systemImage: "list.bullet").tag(BrowserModel.ViewMode.list)
                Label("Columns", systemImage: "rectangle.split.3x1").tag(BrowserModel.ViewMode.columns)
            }
            .pickerStyle(.segmented)
        }

        ToolbarSpacer(.fixed)

        ToolbarItem {
            Button("Tray", systemImage: "tray") { app.tray.toggle() }
                .help("Show the Tray — gather files from anywhere")
        }

        ToolbarItem {
            Button("Glance", systemImage: "arrow.down.right.and.arrow.up.left") { app.glance.collapse() }
                .help("Switch to Glance, a small window — same folder, selection and history")
        }

        ToolbarItem {
            Button("New Archive", systemImage: "plus.rectangle.on.folder") {
                app.chooseFilesToPack()
            }
            .help("Pack files into a new archive")
        }

        ToolbarSpacer(.fixed)

        ToolbarItem(placement: .primaryAction) {
            Button {
                model.extractAll()
            } label: {
                Label("Extract All", systemImage: "arrow.down.to.line")
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, Space.xs)
            }
            .buttonStyle(.glassProminent)
            .help("Extract everything to a folder you choose")
        }

    }

    private var inspectorToggle: some View {
        Button(model.showInspector ? String(localized: "Hide Inspector") : String(localized: "Show Inspector"), systemImage: "sidebar.right") {
            // ⌥⌘I is a keyboard action: the inspector snaps; a click on the toggle still slides it.
            withTransaction(Motion.keyboardAware) { model.showInspector.toggle() }
        }
        .keyboardShortcut("i", modifiers: [.command, .option])
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
