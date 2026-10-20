import SwiftUI

struct BrowserView: View {
    @Bindable var model: BrowserModel
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 220, ideal: 248, max: 320)
                // Search sits at the top of the sidebar, beside the folders it searches across,
                // which keeps the inspector's toolbar section to just its toggle.
                .searchable(text: $model.query, placement: .sidebar, prompt: "Search \(model.archive.files.count) files")
        } detail: {
            content
                .overlay(alignment: .bottom) { nextSteps }
                .navigationTitle(model.title)
                .navigationSubtitle(model.subtitle)
        }
        .inspector(isPresented: $model.showInspector) {
            InspectorView(model: model)
                .inspectorColumnWidth(min: 240, ideal: 280, max: 360)
                // The toggle lives in the inspector's own toolbar section, pushed to the window's
                // trailing edge — never straddling the column divider. SwiftUI keeps it in the
                // toolbar while the inspector is collapsed, so it needs no second copy.
                .toolbar {
                    ToolbarSpacer(.flexible)
                    ToolbarItem { inspectorToggle }
                }
        }
        .toolbar { toolbar }
        .onKeyPress(.escape) {
            guard !model.selection.isEmpty else { return .ignored }
            model.selection = []
            return .handled
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.visibleEntries.isEmpty {
            ContentUnavailableView.search(text: model.query)
        } else {
            // View-mode switches are keyboard-speed actions: no animation.
            switch model.viewMode {
            case .grid: ContentGrid(model: model)
            case .list: ContentList(model: model)
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
        .padding(.bottom, Space.l)
        .animation(Motion.resolved(Motion.appear, reduceMotion: reduceMotion), value: visible)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button("Enclosing Folder", systemImage: "chevron.left") { model.goUp() }
                .disabled(model.folder.isEmpty || model.isSearching)
                .keyboardShortcut(.upArrow, modifiers: .command)
        }

        ToolbarItem {
            Picker("View", selection: $model.viewMode) {
                Label("Icons", systemImage: "square.grid.2x2").tag(BrowserModel.ViewMode.grid)
                Label("List", systemImage: "list.bullet").tag(BrowserModel.ViewMode.list)
            }
            .pickerStyle(.segmented)
        }

        ToolbarSpacer(.fixed)

        ToolbarItem {
            Button("Tray", systemImage: "tray") { app.tray.toggle() }
                .help("Show the Tray — gather files from anywhere")
        }

        ToolbarItem {
            Button("New Archive", systemImage: "plus.rectangle.on.folder") {
                app.packRequest = PackRequest(files: SampleArchive.packCandidates)
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
        Button(model.showInspector ? "Hide Inspector" : "Show Inspector", systemImage: "sidebar.right") {
            model.showInspector.toggle()
        }
        .keyboardShortcut("i", modifiers: [.command, .option])
    }
}
