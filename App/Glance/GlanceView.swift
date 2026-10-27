import SwiftUI

/// What the Glance window hosts: the opening state, then the browser.
struct GlanceRoot: View {
    let glance: GlanceController
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(SettingsKeys.glanceColourfulControls) private var colourfulControls = false
    @AppStorage(SettingsKeys.glanceMaterial) private var materialPreference = SettingsKeys.GlanceMaterialPreference.liquidGlass.rawValue
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
        .toolbar { windowControls }
        .onChange(of: colourfulControls) { glance.updateWindowControls() }
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
        .cloudDownloadSheet(app, isActive: glance.isShown)
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
        let preference = SettingsKeys.GlanceMaterialPreference(rawValue: materialPreference) ?? .liquidGlass
        switch GlanceMaterial.resolve(reduceTransparency: reduceTransparency, preference: preference) {
        case .glass: Rectangle().fill(.clear).accessibleGlass(in: .rect)
        case .frosted: Rectangle().fill(.regularMaterial)
        case .solid: Color(nsColor: .windowBackgroundColor)
        }
    }

    @ToolbarContentBuilder
    private var windowControls: some ToolbarContent {
        if colourfulControls {
            // In the traffic lights' place and their colours, each its own circle with its symbol
            // always showing, so they read as this window's controls rather than one tinted capsule.
            ToolbarItem(placement: .navigation) {
                HStack(spacing: Space.s) {
                    Button("Close", systemImage: "xmark") { glance.close() }
                        .buttonStyle(ColourfulWindowControl(colour: .red))
                        .accessibilityLabel(String(localized: "Close"))
                        .help("Close")
                    Button(glance.isPinned ? String(localized: "Unpin") : String(localized: "Pin on Top"),
                           systemImage: glance.isPinned ? "pin.fill" : "pin") { glance.isPinned.toggle() }
                        .buttonStyle(ColourfulWindowControl(colour: .yellow))
                        .accessibilityAddTraits(glance.isPinned ? .isSelected : [])
                        .help(pinHelp)
                    Button("Open in Full Window", systemImage: "arrow.up.left.and.arrow.down.right") { glance.expand() }
                        .buttonStyle(ColourfulWindowControl(colour: .green))
                        .accessibilityLabel(String(localized: "Open in Full Window"))
                        .help("Show this archive in the full window — same folder, selection and history")
                }
                .padding(.leading, Space.xs)
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            // Open in Full Window is with Extract All, where the full window has Glance.
            ToolbarItem {
                Toggle(isOn: Binding(get: { glance.isPinned }, set: { glance.isPinned = $0 })) {
                    Label(glance.isPinned ? String(localized: "Unpin") : String(localized: "Pin on Top"),
                          systemImage: glance.isPinned ? "pin.fill" : "pin")
                }
                .toggleStyle(.button)
                .help(pinHelp)
            }
        }
    }

    private var pinHelp: String {
        glance.isPinned ? String(localized: "Stop keeping Glance above other windows")
                        : String(localized: "Keep Glance above other windows")
    }
}

/// One of the colourful window controls (Settings › General): a filled circle the size of the
/// toolbar's buttons, in a traffic light's colour, with its symbol dark on it as theirs are.
private struct ColourfulWindowControl: ButtonStyle {
    let colour: Color

    func makeBody(configuration: Configuration) -> some View {
        Control(configuration: configuration, colour: colour)
    }

    private struct Control: View {
        let configuration: ButtonStyleConfiguration
        let colour: Color
        @Environment(\.colorSchemeContrast) private var contrast

        var body: some View {
            configuration.label
                .labelStyle(.iconOnly)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.black.opacity(0.62))
                .frame(width: 24, height: 24)
                .background(colour, in: .circle)
                .overlay {
                    Circle().fill(.black.opacity(configuration.isPressed ? 0.18 : 0))
                    // Increase Contrast outlines each one, so it reads by shape as well as colour.
                    if ContrastStyle.resolve(contrast).increased {
                        Circle().strokeBorder(.black.opacity(0.5))
                    }
                }
                .contentShape(.circle)
        }
    }
}

/// The compact browser (#159): the Browser's files on a solid card inside the window's glass, with
/// the Browser's floating glass over them — getting around above, and below the archive's controls
/// (Open in Full Window, Extract All) on the leading side and Actions on the trailing side. The title
/// bar says which archive this is, as the full window's does; where you are inside it is the path.
struct GlanceView: View {
    @Bindable var model: BrowserModel
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var editingDelegate = EditingWindowDelegate()
    let glance: GlanceController
    @AppStorage(SettingsKeys.nextStepsShown) private var showsNextSteps = true
    @AppStorage(SettingsKeys.nextStepsHidden) private var hiddenSteps = NextStepsSettings.encode(NextStepsSettings.defaultHidden)
    @AppStorage(SettingsKeys.glanceColourfulControls) private var colourfulControls = false

    var body: some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                // Glance has no Search, so the path has the card's width.
                NavigationCapsule(model: model)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding([.horizontal, .top], GlanceCard.inset)
            }
            .overlay(alignment: .bottom) { floatingControls }
            .glanceCard()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if model.editSession.showsExternalChange { ExternalChangeBar(model: model) }
                else if model.editSession.isEdited { UnsavedChangesBar(model: model) }
            }
            .padding([.horizontal, .bottom], GlanceCard.inset)
            .navigationTitle(model.title)
            .navigationSubtitle(model.subtitle)
            .toolbar { toolbar }
            .onKeyPress(.escape) {
                if model.renamingPath != nil {
                    model.renamingPath = nil
                } else if model.quickLook.isActive {
                    model.quickLook.close()
                } else if model.isActionStackOpen {
                    model.isActionStackOpen = false
                } else if !model.selection.isEmpty {
                    model.select([])
                } else {
                    glance.close()
                }
                return .handled
            }
            .onChange(of: model.selection) { model.quickLook.selectionChanged() }
            .sheet(isPresented: $model.isChoosingEncoding) { EncodingSheet(model: model) }
            .editingNotice(model, isActive: glance.isShown) {
                glance.expand()
                app.extractAndRepack(model)
            }
            .background {
                WindowReader { window in
                    editingDelegate.attach(window, model: model)
                    model.quickLook.attach(to: window)
                    model.dragOut.install(in: window)
                }
                .id(ObjectIdentifier(model))
            }
    }

    @ViewBuilder
    private var content: some View {
        // The card is their background.
        if model.isSearching, model.visibleEntries.isEmpty {
            NoSearchResultsView(model: model)
        } else if model.visibleEntries.isEmpty {
            // The full window's words; there's no Open panel here, so an empty archive offers nothing.
            EmptyContentView(model: model)
        } else {
            GlanceList(model: model)
        }
    }

    /// The full window's bottom row, smaller: the archive's controls on the leading side, Actions
    /// on the trailing side, and one prominent action at a time. Extract All carries the accent
    /// until Actions shows, for a selection or to install an archive that's one app.
    @ViewBuilder
    private var floatingControls: some View {
        let installsArchive = showsNextSteps && NextStepsSettings(hidden: NextStepsSettings.decode(hiddenSteps))
            .archiveLayout(installable: model.archiveTarget).front != nil
        let showsActions = (!model.selection.isEmpty && showsNextSteps) || model.activity != nil || installsArchive
        HStack(alignment: .bottom, spacing: Space.s) {
            // The colourful window controls already have a green Open in Full Window; it shows once.
            ArchiveActions(model: model, prominent: !showsActions,
                           switchTo: colourfulControls ? nil : .fullWindow { glance.expand() })
                .accessibilitySortPriority(0.5)
            Spacer(minLength: 0)
            ZStack {
                if showsActions {
                    // One Actions view in every state, so Install morphs into its progress like a selection's.
                    NextStepsBar(model: model)
                        .accessibilityElement(children: .contain)
                        .accessibilitySortPriority(0)
                        .transition(.rise(reduceMotion: reduceMotion))
                }
            }
            // Springs in for a click, eases out faster, and doesn't move at all for arrow keys, ⌘A or Esc.
            .animation(Motion.presence(showsActions, reduceMotion: reduceMotion), value: showsActions)
        }
        .padding(GlanceCard.inset)
    }

    /// The title bar is the archive's: its name and what it is (`navigationTitle`), and its
    /// password at the trailing edge, as in the full window. Getting around is over the files.
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if model.archive.isEncrypted {
            ToolbarItem(placement: .primaryAction) { ArchiveUnlockControl(model: model) }
        }
    }
}

/// Glance's files: a solid surface for reading inside the window's glass, its corners concentric
/// with the window's, and the light rim Details and the floating glass have.
enum GlanceCard {
    /// The glass around the card, and the floating glass's inset inside it.
    static let inset = Space.s
    /// The window's own corner radius (macOS 26: 16 pt) less the inset, so the card's corners and
    /// the window's run parallel.
    static let cornerRadius: CGFloat = 16 - inset
}

private extension View {
    func glanceCard() -> some View { modifier(GlanceCardSurface()) }
}

private struct GlanceCardSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: GlanceCard.cornerRadius, style: .continuous)
        let dark = colorScheme == .dark
        content
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(shape)
            .overlay {
                // Brighter along the top, as if lit from above; it keeps the card apart from the glass
                // when both are dark.
                shape.strokeBorder(ContrastStyle.resolve(contrast).increased ? AnyShapeStyle(Color.primary.opacity(0.45))
                                   : AnyShapeStyle(LinearGradient(colors: [.white.opacity(dark ? 0.16 : 0.9), .primary.opacity(dark ? 0.08 : 0.1)],
                                                                  startPoint: .top, endPoint: .bottom)),
                                   lineWidth: 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .shadow(color: .black.opacity(dark ? 0.3 : 0.07), radius: dark ? 10 : 8, y: 2)
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
                    .archiveEntryAccessibility(entry: entry, isRenaming: model.renamingPath == entry.path) {
                        model.select([entry.id])
                        model.open(entry)
                    }
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
            .collapsesSelectionOnClick(model)
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
