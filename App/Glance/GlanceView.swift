import SwiftUI

/// What the Glance window hosts: the opening state, then the browser.
struct GlanceRoot: View {
    let glance: GlanceController
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var settled = true

    var body: some View {
        Group {
            if let name = glance.pendingName, app.isOpening {
                OpeningView(name: name)
            } else if let model = app.browser {
                GlanceView(model: model, glance: glance)
            } else {
                Color.clear
            }
        }
        .scaleEffect(settled || reduceMotion ? 1 : 0.96, anchor: glance.anchor)
        .opacity(settled ? 1 : 0)
        .frame(minWidth: GlancePlacement.minimumSize.width, minHeight: GlancePlacement.minimumSize.height)
        .background { background.ignoresSafeArea() }
        .onChange(of: glance.appearance) {
            // Spatial and rare: the content springs out of the pointer (DESIGN.md › Motion).
            var start = Transaction()
            start.disablesAnimations = true
            withTransaction(start) { settled = false }
            withAnimation(Motion.resolved(Motion.appear, reduceMotion: reduceMotion)) { settled = true }
        }
        .onChange(of: app.isOpening) { _, opening in
            guard !opening, glance.pendingName != nil else { return }
            glance.pendingName = nil
            if app.browser == nil, app.openFailure == nil { glance.close() }
        }
        .onChange(of: app.browser == nil) { _, closed in
            if closed, glance.pendingName == nil { glance.close() }
        }
        .passwordSheet(app.passwords)
        // The same failure card as the full window; that window is closed while Glance shows.
        .sheet(item: Binding(get: { glance.isShown ? app.openFailure : nil }, set: { app.openFailure = $0 })) { open in
            FailureCard(failure: open.failure) { action in
                app.openFailure = nil
                guard let action, let url = open.url else {
                    if app.browser == nil { glance.close() }
                    return
                }
                switch action {
                case .tryAgain: glance.open(url)
                case .openInStow:
                    // Where its password can be entered: the full window.
                    glance.close()
                    app.showMainWindow()
                    app.open(url)
                default:
                    app.follow(action, opening: url)
                    if app.browser == nil { glance.close() }
                }
            }
        }
    }

    @ViewBuilder
    private var background: some View {
        switch GlanceMaterial.resolve(reduceTransparency: reduceTransparency) {
        case .glass: Rectangle().fill(.clear).glassEffect(.regular, in: .rect)
        case .solid: Color(nsColor: .windowBackgroundColor)
        }
    }
}

/// The compact browser: a two-column list on a solid card, Next Steps floating over it, and the
/// controls in the window's toolbar on the glass.
struct GlanceView: View {
    @Bindable var model: BrowserModel
    let glance: GlanceController
    @AppStorage(SettingsKeys.nextStepsShown) private var showsNextSteps = true

    var body: some View {
        content
            .clipShape(.rect(cornerRadius: Radius.card))
            // Keeps the solid card apart from the glass when both are dark.
            .overlay { RoundedRectangle(cornerRadius: Radius.card).strokeBorder(.separator.opacity(0.6)) }
            .overlay(alignment: .bottom) { nextSteps }
            .padding([.horizontal, .bottom], Space.s)
            .navigationTitle(model.title)
            .toolbar { toolbar }
            .onKeyPress(.escape) {
                if model.quickLook.isVisible {
                    model.quickLook.close()
                } else if !model.selection.isEmpty {
                    model.select([])
                } else {
                    glance.close()
                }
                return .handled
            }
            .onChange(of: model.selection) { model.quickLook.selectionChanged() }
            .sheet(isPresented: $model.isChoosingEncoding) { EncodingSheet(model: model) }
            .background {
                WindowReader { window in
                    model.quickLook.attach(to: window)
                    model.dragOut.install(in: window)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if model.isSearching, model.visibleEntries.isEmpty {
            NoSearchResultsView(model: model)
                .background(.background)
        } else if model.visibleEntries.isEmpty {
            // The full window's words; there's no Open panel here, so an empty archive offers nothing.
            EmptyContentView(model: model)
                .background(.background)
        } else {
            GlanceList(model: model)
        }
    }

    /// Next Steps for a selection; otherwise Extract All, in the same place. Selecting is a
    /// 100-times-a-day action, so the swap doesn't animate (DESIGN.md › Motion).
    @ViewBuilder
    private var nextSteps: some View {
        Group {
            if (!model.selection.isEmpty && showsNextSteps) || model.activity != nil {
                NextStepsBar(model: model)
            } else {
                Button {
                    model.extractAll()
                } label: {
                    Label("Extract All", systemImage: "arrow.down.to.line")
                        .padding(.horizontal, Space.xs)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .help("Extract everything to a folder you choose")
            }
        }
        .padding(.bottom, Space.m)
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
            Toggle(isOn: Binding(get: { glance.isPinned }, set: { glance.isPinned = $0 })) {
                Label(glance.isPinned ? String(localized: "Unpin") : String(localized: "Pin on Top"),
                      systemImage: glance.isPinned ? "pin.fill" : "pin")
            }
            .toggleStyle(.button)
            .help(glance.isPinned ? String(localized: "Stop keeping Glance above other windows")
                                  : String(localized: "Keep Glance above other windows"))
        }

        ToolbarItem {
            Button("Open in Full Window", systemImage: "arrow.up.left.and.arrow.down.right") { glance.expand() }
                .help("Show this archive in the full window — same folder, selection and history")
        }
    }
}

/// Name and size only — what fits a small window — with the full list's keys, menus and previews.
private struct GlanceList: View {
    @Bindable var model: BrowserModel
    @State private var hover = HoverPreviewModel()

    var body: some View {
        ScrollViewReader { scroller in
            Table(model.visibleEntries, selection: $model.selection) {
                TableColumn(String(localized: "Name")) { entry in
                    HStack(spacing: Space.s) {
                        RowIcon(entry: entry, model: model)
                            .frame(width: 18, height: 18)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(entry.name).lineLimit(1).truncationMode(.middle)
                            if model.isSearching {
                                Text(entry.parent.isEmpty ? String(localized: "Top level") : entry.parent)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .opacity(entry.isHelper ? 0.55 : 1)
                    .contentShape(.rect)
                    .hoverPreview(for: entry, model: hover, browser: model)
                }

                TableColumn(String(localized: "Size")) { entry in
                    Text(entry.size.bytes)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .width(min: 64, ideal: 80, max: 100)
                .alignment(.trailing)
            }
            .tableColumnHeaders(.hidden)
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
            .safeAreaPadding(.bottom, 56)
            .quickLookKeys(model)
            .onChange(of: model.selection) { model.selectionDidChange() }
            .onChange(of: model.scrollTarget) { _, target in
                guard let target else { return }
                scroller.scrollTo(target)
                model.scrollTarget = nil
            }
        }
    }
}

/// From Finder: Glance is up at once and says what it's reading.
private struct OpeningView: View {
    let name: String

    var body: some View {
        VStack(spacing: Space.m) {
            ProgressView().controlSize(.small)
            Text("Opening “\(name)”…")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Window menu: switch between Glance and the full window, and pin Glance.
struct GlanceCommands: Commands {
    let app: AppState

    var body: some Commands {
        let glance = app.glance
        CommandGroup(after: .windowArrangement) {
            Divider()
            if glance.isShown {
                Button("Open in Full Window") { glance.expand() }
                    .keyboardShortcut("g", modifiers: [.command, .option])
            } else {
                Button("Switch to Glance") { glance.collapse() }
                    .keyboardShortcut("g", modifiers: [.command, .option])
                    .disabled(app.browser == nil)
            }
            Toggle("Keep Glance on Top", isOn: Binding(get: { glance.isPinned }, set: { glance.isPinned = $0 }))
        }
    }
}
