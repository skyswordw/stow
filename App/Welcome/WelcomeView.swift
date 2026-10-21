import SwiftUI
import UniformTypeIdentifiers

/// The empty window is the drop target: it says what dropping will do. Archives opened before sit
/// beside it (below it in a narrow window); the drop target keeps a fixed maximum so the list,
/// not a sea of dashed border, fills a large window.
struct WelcomeView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isTargeted = false
    /// A drag that only promises a file (Mail, Photos, chat apps); see `OtherAppFiles`.
    @State private var isPromiseTargeted = false
    @State private var isWide = false

    /// Wide enough for the drop target and the Recent list side by side.
    private static let wideWidth: CGFloat = 900
    private static let dropZoneSize = CGSize(width: 560, height: 380)
    /// Alone in the window there's nothing to balance it against, so it stays a little smaller.
    private static let soloDropZoneSize = CGSize(width: 520, height: 360)

    var body: some View {
        let entries = app.recents.visible
        let layout = isWide
            ? AnyLayout(HStackLayout(alignment: .top, spacing: Space.xxl))
            : AnyLayout(VStackLayout(spacing: Space.xl))
        layout {
            dropZone(size: entries.isEmpty ? Self.soloDropZoneSize : Self.dropZoneSize)
            if !entries.isEmpty {
                RecentList(entries: entries, recents: app.recents) { app.openRecent($0) }
                    .frame(maxWidth: isWide ? 440 : Self.dropZoneSize.width,
                           maxHeight: isWide ? Self.dropZoneSize.height : .infinity)
            }
        }
        .padding(.horizontal, Space.xxl)
        .padding(.bottom, Space.xxl)
        .padding(.top, Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: 560, minHeight: 480)
        .onGeometryChange(for: Bool.self) { $0.size.width >= Self.wideWidth } action: { isWide = $0 }
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
        .onAppear { app.recents.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            app.recents.refresh()
        }
    }

    private var highlighted: Bool { isTargeted || isPromiseTargeted }

    private func dropZone(size: CGSize) -> some View {
        // Without the format list when a short window also has to fit the Recent list.
        ViewThatFits(in: .vertical) {
            dropZoneContent(showsFormats: true)
            dropZoneContent(showsFormats: false)
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
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: Space.xs) {
                Text(highlighted ? String(localized: "Let go to open") : String(localized: "Drop to open or pack"))
                    .font(.title2.weight(.semibold))
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

            HStack(spacing: Space.s) {
                Button("Open Archive…") { app.isChoosingArchive = true }
                Button("Try the Sample") { app.openArchive(named: SampleArchive.make().name) }
                    .buttonStyle(.glassProminent)
            }
            .controlSize(.large)
            .padding(.top, Space.s)
        }
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
                FormatBadge(format: ArchiveFormat.infer(fromName: entry.name) ?? .zip)
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
