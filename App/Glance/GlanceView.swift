import SwiftUI

/// What the Glance window hosts: the opening state, then the browser.
struct GlanceRoot: View {
    let glance: GlanceController
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(SettingsKeys.glanceMaterial) private var materialPreference = SettingsKeys.GlanceMaterialPreference.liquidGlass.rawValue
    @State private var settled = true

    var body: some View {
        Group {
            if let name = glance.pendingName, app.isOpening {
                OpeningView(name: name, glance: glance)
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

    /// The window's one surface, which the files sit on directly. Liquid Glass gets a wash of the
    /// window colour so rows stay readable over a busy desktop; classic frosted is already dense
    /// enough; Reduce Transparency is solid.
    @ViewBuilder
    private var background: some View {
        let preference = SettingsKeys.GlanceMaterialPreference(rawValue: materialPreference) ?? .liquidGlass
        switch GlanceMaterial.resolve(reduceTransparency: reduceTransparency, preference: preference) {
        case .glass: Rectangle().fill(Color(nsColor: .windowBackgroundColor).opacity(0.5)).accessibleGlass(in: .rect)
        case .frosted: Rectangle().fill(.regularMaterial)
        case .solid: Color(nsColor: .windowBackgroundColor)
        }
    }
}

/// The compact browser (#159), borderless as ArcZip's Mini is: no title bar, the archive named in
/// a header that moves the window, the Browser's navigation capsule under it, and the files on the
/// window's own surface. Along the bottom, the window's controls (Close, Pin on Top, Open in Full
/// Window), then Extract All, and Actions on the trailing side.
struct GlanceView: View {
    @Bindable var model: BrowserModel
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var editingDelegate = EditingWindowDelegate()
    let glance: GlanceController
    @AppStorage(SettingsKeys.nextStepsShown) private var showsNextSteps = true
    @AppStorage(SettingsKeys.nextStepsHidden) private var hiddenSteps = NextStepsSettings.encode(NextStepsSettings.defaultHidden)

    var body: some View {
        VStack(spacing: 0) {
            GlanceHeader(model: model)
            files
        }
        // The header takes the title bar's place, so it starts at the window's top edge.
        .ignoresSafeArea(.container, edges: .top)
        // The window keeps its title for the Window menu, Mission Control and accessibility;
        // the header shows it.
        .navigationTitle(model.title)
        .navigationSubtitle(model.subtitle)
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

    /// The files, with the navigation capsule floating over their top and the controls over their
    /// bottom, and the full window's unsaved-changes and changed-on-disk bars under them.
    private var files: some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                // Glance has no Search, so the path has the window's width.
                NavigationCapsule(model: model, fillsWidth: true)
                    .padding(.horizontal, GlanceLayout.inset)
            }
            .overlay(alignment: .bottom) { floatingControls }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if model.editSession.showsExternalChange { ExternalChangeBar(model: model) }
                else if model.editSession.isEdited { UnsavedChangesBar(model: model) }
            }
    }

    @ViewBuilder
    private var content: some View {
        // On the window's surface, like the rows.
        if model.isSearching, model.visibleEntries.isEmpty {
            NoSearchResultsView(model: model)
        } else if model.visibleEntries.isEmpty {
            // The full window's words; there's no Open panel here, so an empty archive offers nothing.
            EmptyContentView(model: model)
        } else {
            GlanceList(model: model)
        }
    }

    /// The window's controls on the leading side, then the archive's Extract All, and Actions on
    /// the trailing side, with one prominent action at a time: Extract All carries the accent until
    /// Actions shows, for a selection or to install an archive that's one app, or until there are
    /// changes to save, when the bar's Save (or Save a Copy…) is the one. When the row runs out of
    /// room, Extract All keeps its icon and drops its words.
    @ViewBuilder
    private var floatingControls: some View {
        let installsArchive = showsNextSteps && NextStepsSettings(hidden: NextStepsSettings.decode(hiddenSteps))
            .archiveLayout(installable: model.archiveTarget).front != nil
        let showsActions = (!model.selection.isEmpty && showsNextSteps) || model.activity != nil || installsArchive
        // Edits pending or being saved: the bar under the files holds the accent.
        let savesEdits = model.editSession.isEdited || model.editSession.isSaving
        let extractsProminently = !showsActions && !savesEdits
        HStack(alignment: .bottom, spacing: Space.s) {
            GlanceWindowControls(glance: glance)
                .accessibilitySortPriority(0.6)
            ViewThatFits(in: .horizontal) {
                ArchiveActions(model: model, prominent: extractsProminently)
                ArchiveActions(model: model, prominent: extractsProminently, compact: true)
            }
            // The accent fades across as a status change; a ⌘S or Delete key press just swaps it.
            .animation(Motion.byKeyboard ? nil : Motion.resolved(Motion.status, reduceMotion: reduceMotion),
                       value: savesEdits)
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
        .padding([.horizontal, .bottom], GlanceLayout.inset)
    }
}

/// Glance's measures.
enum GlanceLayout {
    /// The floating glass's distance from the window's sides and bottom.
    static let inset = Space.s + Space.xs
    /// The header's leading and trailing margin; the badge lines up with the rows' icons.
    static let margin = Space.l
}

/// The archive Glance shows: its format badge, its name and what it is, wherever you are inside
/// it, and its password beside the name when it's encrypted. It's where the title bar was, so it
/// moves the window; the lock keeps its click.
private struct GlanceHeader: View {
    let model: BrowserModel

    var body: some View {
        HStack(spacing: Space.m) {
            FormatBadge(format: model.archive.format, height: 32)
                // The subtitle under the name says the same.
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(model.title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .accessibilityAddTraits(.isHeader)
                    // A long name gives way first; the lock always shows.
                    ArchiveUnlockControl(model: model, badge: true)
                        .fixedSize()
                }
                Text(model.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, GlanceLayout.margin)
        .padding(.top, Space.m + 2)
        .padding(.bottom, GlanceLayout.inset - 2)
        .help(model.title)
        // Dragging anywhere but the lock moves the window, as the title bar did. (SwiftUI never
        // passes a background drag to AppKit, so `isMovableByWindowBackground` alone wouldn't.)
        .contentShape(.rect)
        .gesture(WindowDragGesture())
        .allowsWindowActivationEvents(true)
        .accessibilityElement(children: .contain)
    }
}

/// Close, Pin on Top and Open in Full Window: the window's own controls, now that it has no title
/// bar, in one glass capsule of icon buttons like the navigation capsule's. Colourful controls
/// (Settings › General) fill the same three buttons in the traffic lights' colours; nothing moves
/// or changes size. Pinned: the pin fills and a ring goes round its button.
///
/// While the archive is still opening the same capsule is already in place: Close stops the
/// opening (Escape too), and Open in Full Window waits, dimmed, for something to show.
private struct GlanceWindowControls: View {
    let glance: GlanceController
    var isOpening = false
    @AppStorage(SettingsKeys.glanceColourfulControls) private var colourful = false

    var body: some View {
        HStack(spacing: 2) {
            if colourful {
                close.buttonStyle(ColourfulWindowControl(colour: .trafficRed))
                pin.buttonStyle(ColourfulWindowControl(colour: .trafficYellow, isOn: glance.isPinned))
                expand.buttonStyle(ColourfulWindowControl(colour: .trafficGreen))
            } else {
                close.buttonStyle(ActionButtonStyle(iconOnly: true))
                pin.buttonStyle(ActionButtonStyle(iconOnly: true, isOn: glance.isPinned))
                expand.buttonStyle(ActionButtonStyle(iconOnly: true))
            }
        }
        .padding(ActionButtonStyle.inset)
        .accessibleGlass(in: .capsule)
        .labelStyle(.iconOnly)
        .fixedSize()
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var close: some View {
        if isOpening {
            Button("Close", systemImage: "xmark") { glance.stopOpening() }
                .accessibilityLabel(String(localized: "Close"))
                .help("Stop opening and close")
                // The loaded Glance handles Escape itself; until then, Escape is this button.
                .keyboardShortcut(.cancelAction)
        } else {
            Button("Close", systemImage: "xmark") { glance.close() }
                .accessibilityLabel(String(localized: "Close"))
                .help("Close")
        }
    }

    private var pin: some View {
        Button(glance.isPinned ? String(localized: "Unpin") : String(localized: "Pin on Top"),
               systemImage: glance.isPinned ? "pin.fill" : "pin") { glance.isPinned.toggle() }
            .accessibilityAddTraits(glance.isPinned ? .isSelected : [])
            .help(glance.isPinned ? String(localized: "Stop keeping Glance above other windows")
                                  : String(localized: "Keep Glance above other windows"))
    }

    private var expand: some View {
        Button("Open in Full Window", systemImage: "arrow.up.left.and.arrow.down.right") { glance.expand() }
            .accessibilityLabel(String(localized: "Open in Full Window"))
            .help("Show this archive in the full window — same folder, selection and history")
            .disabled(isOpening)
    }
}

private extension Color {
    /// The traffic lights' own fills, softer than the system's red, yellow and green.
    static let trafficRed = Color(red: 1, green: 0.373, blue: 0.341)
    static let trafficYellow = Color(red: 0.996, green: 0.737, blue: 0.180)
    static let trafficGreen = Color(red: 0.157, green: 0.784, blue: 0.251)
}

/// One of the colourful window controls: the capsule's button filled in a traffic light's colour,
/// its symbol always showing and dark on it as theirs are, so it stays legible on yellow. On
/// (pinned), a darker ring runs round its edge, inside the capsule like the plain button's.
/// Unavailable (Open in Full Window while opening), it goes grey as a dimmed traffic light does.
private struct ColourfulWindowControl: ButtonStyle {
    let colour: Color
    var isOn = false

    func makeBody(configuration: Configuration) -> some View {
        Control(configuration: configuration, colour: colour, isOn: isOn)
    }

    static let diameter = ActionButtonStyle.height

    private struct Control: View {
        let configuration: ButtonStyleConfiguration
        let colour: Color
        let isOn: Bool
        @State private var isHovering = false
        @Environment(\.colorSchemeContrast) private var contrast
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isEnabled ? AnyShapeStyle(.black.opacity(0.62)) : AnyShapeStyle(.tertiary))
                .frame(width: ColourfulWindowControl.diameter, height: ColourfulWindowControl.diameter)
                .background(isEnabled ? AnyShapeStyle(colour) : AnyShapeStyle(.quaternary), in: .circle)
                .overlay {
                    Circle().fill(configuration.isPressed ? Color.black.opacity(0.16) : Color.white.opacity(isHovering && isEnabled ? 0.14 : 0))
                    // Increase Contrast outlines each one, so it reads by shape as well as colour.
                    if ContrastStyle.resolve(contrast).increased {
                        Circle().strokeBorder(.black.opacity(0.5))
                    }
                }
                .overlay {
                    Circle()
                        .strokeBorder(.black.opacity(0.4), lineWidth: 2)
                        .opacity(isOn ? 1 : 0)
                        .allowsHitTesting(false)
                }
                .contentShape(.circle)
                .onHover { isHovering = $0 }
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
            // The rows sit on the window's surface.
            .scrollContentBackground(.hidden)
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

/// From Finder: Glance is up at once and says what it's reading. With no title bar, the window's
/// controls are already where they'll stay, and the whole surface moves the window.
private struct OpeningView: View {
    let name: String
    let glance: GlanceController

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
        .contentShape(.rect)
        .gesture(WindowDragGesture())
        .allowsWindowActivationEvents(true)
        .overlay(alignment: .bottomLeading) {
            GlanceWindowControls(glance: glance, isOpening: true)
                .padding([.horizontal, .bottom], GlanceLayout.inset)
        }
        .ignoresSafeArea(.container, edges: .top)
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
