import SwiftUI
import UniformTypeIdentifiers

/// The empty window is the drop target: it says what dropping will do. Archives opened before sit in
/// a sidebar, where the archive card and folders will be once one opens, so the window keeps the
/// Browser's shape. The drop zone fills the rest, up to a cap, so a large window gets a centred
/// target rather than a sea of dashed border. With nothing to recall there is no sidebar at all.
struct WelcomeView<Accessory: View>: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isTargeted = false
    /// A drag that only promises a file (Mail, Photos, chat apps); see `OtherAppFiles`.
    @State private var isPromiseTargeted = false
    /// The sidebar toggle hid Recent; this window keeps it hidden until it's shown again.
    @SceneStorage("welcome.recentHidden") private var recentHidden = false
    /// Where the drop zone sits in the stage's height; see `dropZonePlacement`.
    @State private var placement = EdgeInsets()
    /// Under the drop zone, inside the stage: the pack capsule while packing.
    @ViewBuilder var accessory: () -> Accessory

    /// The drop zone fills the stage in a typical window; a larger one centres it at this size.
    private static var dropZoneMax: CGSize { CGSize(width: 680, height: 480) }
    private static var stageMargin: CGFloat { Space.xxl }
    /// The stage keeps room for the title, the sentence and both buttons on one line.
    private static var stageMinWidth: CGFloat { 400 }

    var body: some View {
        let entries = app.recents.visible
        NavigationSplitView(columnVisibility: columns(hasRecents: !entries.isEmpty)) {
            RecentSidebar(entries: entries, open: { app.openRecent($0) }, show: showInFinder,
                          remove: { entry in withoutRecent { app.recents.remove(entry) } },
                          clear: { withoutRecent { app.recents.clear() } })
                .sidebarColumnWidth()
                // With nothing in Recent there's no sidebar, and so nothing to toggle.
                .toolbar(removing: entries.isEmpty ? .sidebarToggle : nil)
        } detail: {
            stage
                .frame(minWidth: Self.stageMinWidth)
        }
        // A quiet title bar: the traffic lights over the window, no title, no bar.
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .frame(minWidth: 560, minHeight: 480)
        // Files from Finder arrive on the stage's own target as URLs; drags that only promise
        // an archive (Mail attachments, chat apps) fall through to here and are received first.
        .onDrop(of: OtherAppFiles.promisedTypes, isTargeted: $isPromiseTargeted) { providers in
            Task {
                let urls = await OtherAppFiles.receive(providers)
                if !urls.isEmpty { _ = handleDrop(urls) }
            }
            return true
        }
        .onAppear { app.recents.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            app.recents.refresh()
        }
    }

    /// The sidebar shows whenever there's something in it, unless the toggle hid it.
    private func columns(hasRecents: Bool) -> Binding<NavigationSplitViewVisibility> {
        Binding {
            hasRecents && !recentHidden ? .all : .detailOnly
        } set: { visibility in
            guard hasRecents else { return }
            recentHidden = visibility == .detailOnly
        }
    }

    /// Emptying Recent folds the sidebar away and the stage widens into its place: eased, quicker
    /// than an arrival, and not at all under Reduce Motion or from the keyboard.
    private func withoutRecent(_ change: () -> Void) {
        withAnimation(reduceMotion ? nil : Motion.presence(false, reduceMotion: false), change)
    }

    private func showInFinder(_ entry: RecentArchives.Entry) {
        NSWorkspace.shared.activateFileViewerSelecting([entry.url])
    }

    private var highlighted: Bool { isTargeted || isPromiseTargeted }

    /// Everything beside the sidebar takes drops, not only the dashed outline inside it.
    private var stage: some View {
        let gap = Space.s, margin = Self.stageMargin, cap = Self.dropZoneMax.height
        return dropZone
            .padding(.horizontal, Self.stageMargin)
            .padding(.top, placement.top)
            .padding(.bottom, placement.bottom)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onGeometryChange(for: EdgeInsets.self) { proxy in
                dropZonePlacement(stage: proxy.size.height, titleBar: proxy.safeAreaInsets.top,
                                  gap: gap, margin: margin, cap: cap)
            } action: { placement = $0 }
            .contentShape(.rect)
            .dropDestination(for: URL.self) { urls, _ in
                handleDrop(urls)
            } isTargeted: { isTargeted = $0 }
            .safeAreaInset(edge: .bottom, spacing: 0) { accessory() }
    }

    private var dropZone: some View {
        // The format list goes first when the stage is too narrow or too short for it.
        ViewThatFits {
            dropZoneContent(showsFormats: true)
            dropZoneContent(showsFormats: false)
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(maxWidth: Self.dropZoneMax.width, maxHeight: Self.dropZoneMax.height)
        .frame(minHeight: 260)
        .background {
            RoundedRectangle(cornerRadius: Radius.panel + 4)
                .fill(highlighted ? AnyShapeStyle(.tint.opacity(0.08)) : AnyShapeStyle(.clear))
                .strokeBorder(highlighted ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator),
                              style: StrokeStyle(lineWidth: highlighted ? 2 : 1.5, dash: highlighted ? [] : [7, 6]))
        }
        .scaleEffect(highlighted && !reduceMotion ? 1.015 : 1)
        .animation(Motion.resolved(Motion.target, reduceMotion: reduceMotion), value: highlighted)
    }

    private func dropZoneContent(showsFormats: Bool) -> some View {
        VStack(spacing: Space.l) {
            // The app's own icon and name, so a large empty window still says whose it is.
            // The drop feedback is the border, the tint and the words; the icon stays put.
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

            VStack(spacing: Space.xs) {
                Text(highlighted ? String(localized: "Let go to open") : String(localized: "Drop to open or pack"))
                    .font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                    .contentTransition(.opacity)
                // Narrow enough that the two sentences break between them, not one word from the end.
                Text("An archive opens here; several are extracted. Anything else gets packed.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 296)
                    .fixedSize(horizontal: false, vertical: true)
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
                .fixedSize()
                .accessibilityElement(children: .combine)
            }

            HStack(spacing: Space.s) {
                Button("Open Archive…") { app.isChoosingArchive = true }
                Button("Try the Sample") { app.openArchive(named: SampleArchive.make().name) }
                    .buttonStyle(.glassProminent)
            }
            .controlSize(.large)
            .fixedSize()
            .padding(.top, Space.s)
        }
        .multilineTextAlignment(.center)
    }

    private func handleDrop(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty else { return false }
        let archives = urls.allSatisfy { ArchiveFormat.infer(fromName: $0.lastPathComponent) != nil }
        if urls.count == 1, archives {
            app.open(urls[0])
        } else if archives {
            app.extractArchives(urls)
        } else {
            app.pack(urls)
        }
        return true
    }
}

/// Room above and below the drop zone. It starts `gap` under the title bar, level with the Recent
/// heading, and fills down to `margin` from the bottom; once `cap` stops it growing, the spare height
/// centres it in the whole window rather than in the part below the title bar.
private nonisolated func dropZonePlacement(stage: CGFloat, titleBar: CGFloat,
                                           gap: CGFloat, margin: CGFloat, cap: CGFloat) -> EdgeInsets {
    let height = min(cap, stage - gap - margin)
    let above = max(gap, (stage - titleBar - height) / 2)
    return EdgeInsets(top: above, leading: 0, bottom: max(margin, stage - height - above), trailing: 0)
}

extension WelcomeView where Accessory == EmptyView {
    init() { self.init { EmptyView() } }
}

/// Archives opened before, newest first, in the column the archive card takes once one opens.
private struct RecentSidebar: View {
    let entries: [RecentArchives.Entry]
    let open: (RecentArchives.Entry) -> Void
    let show: (RecentArchives.Entry) -> Void
    let remove: (RecentArchives.Entry) -> Void
    let clear: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(alignment: .firstTextBaseline) {
                    SectionLabel(String(localized: "Recent"))
                    Spacer()
                    Button("Clear", action: clear)
                        .buttonStyle(.plain)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .help("Clear the list of recent archives")
                }
                .padding(.horizontal, Space.s)
                .padding(.bottom, Space.xs)

                LazyVStack(spacing: 2) {
                    ForEach(entries) { entry in
                        RecentRow(entry: entry) { open(entry) }
                            .contextMenu {
                                Button("Show in Finder") { show(entry) }
                                Button("Remove from Recent") { remove(entry) }
                            }
                    }
                }
            }
            .padding(.horizontal, Space.s)
            .padding(.top, Space.xs)
            .padding(.bottom, Space.l)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

private struct RecentRow: View {
    let entry: RecentArchives.Entry
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: Space.s + 2) {
                // The archive card's badge in miniature: the same mark, in the same column.
                FormatBadge(format: ArchiveFormat.infer(fromName: SplitArchive.baseName(entry.name) ?? entry.name) ?? .other)
                    .scaleEffect(0.7)
                    .frame(width: 24, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    // The folder gives way first, to its own name and then to an ellipsis; when it
                    // was opened always reads in full. The whole path is in the tooltip.
                    ViewThatFits(in: .horizontal) {
                        caption(entry.folderDisplay).fixedSize()
                        caption(entry.folder.lastPathComponent)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.s)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(RecentButtonStyle())
        .help(entry.path)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens the archive"))
    }

    private func caption(_ folder: String) -> some View {
        HStack(spacing: 3) {
            Text(folder)
                .lineLimit(1)
                .truncationMode(.head)
            Text(verbatim: "·")
                .accessibilityHidden(true)
            Text(entry.openedDisplay())
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        }
    }
}

private struct RecentButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(.primary.opacity(configuration.isPressed ? 0.1 : isHovering ? 0.06 : 0),
                        in: .rect(cornerRadius: Radius.chip))
            .onHover { isHovering = $0 }
    }
}

extension URL {
    var fileSize: Int64 {
        Int64((try? resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
}
