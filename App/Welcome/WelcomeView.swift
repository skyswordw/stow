import SwiftUI
import UniformTypeIdentifiers

/// The welcome window, fixed and compact: it can't be resized or zoomed, so it never floats in
/// empty space. The Browser is a window of its own (`AppRoot` hands over between them).
struct WelcomeWindow: View {
    static let size = CGSize(width: 640, height: 600)
    @Environment(AppState.self) private var app
    @State private var window: NSWindow?
    @State private var trafficLights = TrafficLights.standard

    var body: some View {
        WelcomeView()
            .safeAreaInset(edge: .bottom, spacing: 0) { PackActivityAccessory() }
            .frame(width: Self.size.width, height: Self.size.height)
            // Settings mirrors the traffic lights in the other top corner: their vertical centre,
            // and the close button's inset from the leading edge as its glyph's from the trailing.
            .overlay(alignment: .topTrailing) {
                WelcomeSettingsButton()
                    // The gear's ink sits half a point below its frame's centre.
                    .padding(.top, trafficLights.midY - WelcomeSettingsButton.size / 2 - 0.5)
                    .padding(.trailing, trafficLights.inset - WelcomeSettingsButton.glyphInset)
                    .ignoresSafeArea()
            }
            .background {
                WindowReader { window in
                    self.window = window
                    window.animationBehavior = WindowSwitch.animation
                    // Once AppKit has laid out the title bar.
                    DispatchQueue.main.async {
                        if let measured = TrafficLights(in: window) { trafficLights = measured }
                    }
                }
            }
            // Closing it while an archive is still on its way cancels that, as closing the Browser
            // does. The hand-over only closes it once the archive is in, and an archive opening into
            // Glance isn't this window's to cancel.
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
                guard let closing = notification.object as? NSWindow, closing === window else { return }
                app.mainWindowDidClose(.welcome)
            }
            .modifier(AppRoot(host: .welcome))
    }
}

/// Where the window's own buttons sit, measured from the close button (in points from the window's
/// top-leading corner), so the Settings gear can mirror them whatever the system's metrics are.
private struct TrafficLights: Equatable {
    var inset: CGFloat
    var midY: CGFloat
    /// The macOS 26 metrics, until the window is measured.
    static let standard = TrafficLights(inset: 9, midY: 16)

    init(inset: CGFloat, midY: CGFloat) {
        self.inset = inset
        self.midY = midY
    }

    @MainActor init?(in window: NSWindow) {
        guard let close = window.standardWindowButton(.closeButton), close.window != nil else { return nil }
        let frame = close.convert(close.bounds, to: nil)
        guard frame.width > 0 else { return nil }
        self.init(inset: frame.minX, midY: window.frame.height - frame.midY)
    }
}

/// Settings as a quiet gear in the window's top-trailing corner: an icon like the traffic lights
/// opposite, named "Settings…" for VoiceOver and its tooltip, with a hover circle and a focus ring.
private struct WelcomeSettingsButton: View {
    /// The hover circle: a little over the traffic lights' own 16 pt buttons, so it stays light.
    static let size: CGFloat = 22
    /// The glyph draws as wide as a traffic light (14 pt) at this point size.
    private static let pointSize: CGFloat = 13.5
    private static let glyph: CGFloat = 14
    /// From the circle's edge to the glyph's, so the glyph (not the circle) lines up with the inset.
    static let glyphInset = (size - glyph) / 2

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        Button {
            SettingsRouter.shared.show(.general)
        } label: {
            Image(systemName: "gearshape")
                // Medium, so its strokes carry about the weight of the filled lights opposite.
                .font(.system(size: Self.pointSize, weight: .medium))
                .frame(width: Self.size, height: Self.size)
                .contentShape(.circle)
        }
        .buttonStyle(CornerButtonStyle(increased: ContrastStyle.resolve(colorSchemeContrast).increased))
        .focusRing(in: Circle(), outset: 0)
        .accessibilityLabel(Text("Settings…"))
        .help("Open Stow’s settings (⌘,)")
    }
}

private struct CornerButtonStyle: ButtonStyle {
    let increased: Bool
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // Secondary like the window's other chrome; full strength under Increase Contrast.
            .foregroundStyle(increased || isHovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .background(.primary.opacity(configuration.isPressed ? 0.12 : isHovering ? 0.06 : 0), in: .circle)
            .overlay {
                if increased { Circle().strokeBorder(.primary.opacity(0.45), lineWidth: 1) }
            }
            .onHover { isHovering = $0 }
    }
}

/// The empty window is the drop target: it says what dropping will do. Archives opened before sit
/// below it.
struct WelcomeView: View {
    @Environment(AppState.self) private var app
    @Environment(\.reducesMotion) private var reduceMotion
    @State private var isTargeted = false
    /// A drag that only promises a file (Mail, Photos, chat apps); see `OtherAppFiles`.
    @State private var isPromiseTargeted = false
    /// With keyboard navigation on, the window starts on Create Archive, its primary action.
    @FocusState private var focus: Action?
    private enum Action: Hashable { case open, create }

    private static let dropZoneSize = CGSize(width: 560, height: 380)
    /// With no history it is the whole window, at the same width it has above the Recent list.
    private static let soloDropZoneSize = CGSize(width: 560, height: CGFloat.infinity)

    var body: some View {
        let entries = app.recents.visible
        VStack(spacing: Space.xl) {
            dropZone(size: entries.isEmpty ? Self.soloDropZoneSize : Self.dropZoneSize)
            if !entries.isEmpty {
                RecentList(entries: entries, recents: app.recents) { app.openRecent($0) }
                    .frame(maxWidth: Self.dropZoneSize.width, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: Self.dropZoneSize.width)
        .padding(.horizontal, Space.xxl)
        .padding(.bottom, Space.xxl)
        .padding(.top, Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // A quiet title bar: the traffic lights over the window, no title, no bar.
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        // Files from Finder arrive on the drop zone's own target as URLs; drags that only promise
        // an archive (Mail attachments, chat apps) fall through to here and are received first.
        .onDrop(of: OtherAppFiles.promisedTypes, isTargeted: $isPromiseTargeted) { providers in
            Task {
                let urls = await OtherAppFiles.receive(providers)
                if !urls.isEmpty { _ = handleDrop(urls) }
            }
            return true
        }
        .defaultFocus($focus, .create)
        .onAppear { app.recents.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            app.recents.refresh()
        }
    }

    private var highlighted: Bool { isTargeted || isPromiseTargeted }

    private func dropZone(size: CGSize) -> some View {
        // Without the format list when a short window also has to fit the Recent list, then
        // without the icon; the two actions always stay.
        ViewThatFits(in: .vertical) {
            dropZoneContent(showsFormats: true)
            dropZoneContent(showsFormats: false)
            dropZoneContent(showsFormats: false, showsIcon: false)
        }
        .padding(.horizontal, Space.xl)
        .padding(.vertical, Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(maxWidth: size.width)
        .frame(minHeight: 220, maxHeight: size.height)
        .background {
            RoundedRectangle(cornerRadius: Radius.panel + 4)
                .fill(highlighted ? AnyShapeStyle(.tint.opacity(0.08)) : AnyShapeStyle(.clear))
                .strokeBorder(highlighted ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator),
                              style: StrokeStyle(lineWidth: highlighted ? 2 : 1.5, dash: highlighted ? [] : [7, 6]))
        }
        .scaleEffect(highlighted && !reduceMotion ? 1.015 : 1)
        .animation(Motion.resolved(Motion.target, reduceMotion: reduceMotion), value: highlighted)
        .dropDestination(for: URL.self) { urls, _ in
            handleDrop(urls)
        } isTargeted: { isTargeted = $0 }
    }

    private func dropZoneContent(showsFormats: Bool, showsIcon: Bool = true) -> some View {
        VStack(spacing: Space.l) {
            // The app's own icon and name, so a large empty window still says whose it is.
            // The drop feedback is the border, the tint and the words; the icon stays put.
            if showsIcon {
                VStack(spacing: Space.xs) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 64, height: 64)
                        .accessibilityHidden(true)
                    Text(verbatim: "Stow")
                        .font(.headline).accessibilityAddTraits(.isHeader)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: Space.xs) {
                Text(highlighted ? String(localized: "Let go to open") : String(localized: "Drop to open or pack"))
                    .font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                    .contentTransition(.opacity)
                Text("An archive opens here; several are extracted. Anything else gets packed.")
                    .foregroundStyle(.secondary)
            }

            if showsFormats {
                HStack(spacing: 6) {
                    ForEach(["ZIP", "7Z", "RAR", "TAR", "GZ", "XZ", "DMG", "ISO"], id: \.self) { format in
                        Text(format)
                            .font(.caption2.weight(.semibold))
                            .tracking(0.3)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.primary.opacity(0.05), in: .rect(cornerRadius: 5))
                    }
                    Text("+ 25 more")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
            }

            // The two ways in, side by side at one width: Create is the prominent one, trailing as
            // the primary button of a pair is on the Mac; Open is its plain partner. While a drag
            // is over the zone they step back, so the drop is the only thing it asks for.
            HStack(spacing: Space.m) {
                Button { app.isChoosingArchive = true } label: {
                    Text("Open Archive…").frame(minWidth: Self.actionWidth)
                }
                .help("Choose an archive to open (⌘O)")
                .focused($focus, equals: .open)
                Button { app.beginNewArchive() } label: {
                    Text("Create Archive…").frame(minWidth: Self.actionWidth)
                }
                .buttonStyle(.glassProminent)
                .help("Start a new archive and add files to it (⌘N)")
                .focused($focus, equals: .create)
            }
            .controlSize(.large)
            .fixedSize()
            .padding(.top, Space.s)
            .opacity(highlighted ? 0.35 : 1)
        }
    }

    /// Wide enough for both titles in English and Simplified Chinese, so the pair reads as one row.
    private static let actionWidth: CGFloat = 132

    private func handleDrop(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty else { return false }
        let archives = urls.allSatisfy { ArchiveFormat.infer(fromName: $0.lastPathComponent) != nil }
        if urls.count == 1, archives {
            app.openPreferred(urls[0])
        } else if archives {
            app.extractArchives(urls)
        } else {
            app.pack(urls)
        }
        return true
    }
}

/// Archives opened before: name, folder and when, newest first.
private struct RecentList: View {
    let entries: [RecentArchives.Entry]
    let recents: RecentArchives
    let open: (RecentArchives.Entry) -> Void

    /// Which ends of the list have rows scrolled out of sight.
    struct Edges: Equatable {
        var above = false
        var below = false
    }

    @State private var hidden = Edges()
    /// Roughly one row: whatever row sits at the bottom edge is visibly on its way out.
    private static let fade: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(String(localized: "Recent"))
                Spacer()
                Button("Clear") { recents.clear() }
                    .buttonStyle(.plain)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .help("Clear the list of recent archives")
            }
            .padding(.horizontal, Space.s)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(entries) { entry in
                        RecentRow(entry: entry) { open(entry) }
                            .contextMenu {
                                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
                                Button("Remove from Recent") { recents.remove(entry) }
                            }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .onScrollGeometryChange(for: Edges.self) { geometry in
                let below = geometry.contentSize.height - geometry.visibleRect.maxY
                return Edges(above: geometry.visibleRect.minY > 1, below: below > 1)
            } action: { _, edges in
                hidden = edges
            }
            // An edge with more behind it fades over about a row, so a cut-off row reads as "scroll for more".
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: hidden.above ? Space.l : 0)
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: hidden.below ? Self.fade : 0)
                }
            }
        }
    }
}

private struct RecentRow: View {
    let entry: RecentArchives.Entry
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: Space.m) {
                FormatBadge(format: ArchiveFormat.infer(fromName: SplitArchive.baseName(entry.name) ?? entry.name) ?? .other)
                    .scaleEffect(0.8)
                    .frame(width: 28, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(entry.folderDisplay)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                Spacer(minLength: Space.s)
                Text(entry.openedDisplay())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, Space.s)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(RecentButtonStyle())
        // The default ring was square and the scroll view cut off its sides; round the row as its
        // hover does, inside the list.
        .focusRing(in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous), outset: 0)
        .help(entry.path)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens the archive"))
    }
}

private struct RecentButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(.primary.opacity(configuration.isPressed ? 0.1 : isHovering ? 0.05 : 0),
                        in: .rect(cornerRadius: Radius.chip))
            .onHover { isHovering = $0 }
    }
}

extension URL {
    var fileSize: Int64 {
        Int64((try? resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
}
