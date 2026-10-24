import SwiftUI
import UniformTypeIdentifiers

/// The empty window is the drop target: it says what dropping will do. Archives opened before sit
/// below it. The window keeps a fixed, compact size while it shows this (`MainWindowSizing`); in full
/// screen or a zoomed window the same column stays centred rather than stretching.
struct WelcomeView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isTargeted = false
    /// A drag that only promises a file (Mail, Photos, chat apps); see `OtherAppFiles`.
    @State private var isPromiseTargeted = false

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
        .padding(.horizontal, Space.xxl)
        .padding(.bottom, Space.xxl)
        .padding(.top, Space.l)
        .frame(maxWidth: MainWindowSizing.welcomeSize.width, maxHeight: MainWindowSizing.welcomeSize.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: 560, minHeight: 480)
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
                    .font(.headline).accessibilityAddTraits(.isHeader)
                    .foregroundStyle(.secondary)
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

/// Stow has one main window: the welcome while no archive is open, the Browser once one is. The
/// welcome gets a fixed, compact size that can't be resized, as welcome windows usually do, so a
/// large window never leaves it floating in empty space. Opening an archive grows the window to the
/// Browser's last size; closing it shrinks back. The title bar stays where it is both ways, and the
/// window stays on screen. Full screen and zoomed windows keep their size, and stay resizable.
@MainActor
final class MainWindowSizing {
    /// The welcome window's content size.
    static let welcomeSize = CGSize(width: 640, height: 600)
    private static let browserDefault = CGSize(width: 1120, height: 700)
    private static let browserSizeKey = "mainWindow.browserSize"

    private weak var window: NSWindow?
    private var showsWelcome = true
    /// The welcome is up at its fixed size, so the window can't be resized. SwiftUI turns resizing
    /// back on when the content changes; `styleMask` is watched to keep it off.
    private var locked = false
    private var styleObservation: NSKeyValueObservation?
    /// Where the welcome's top-left was before an archive opened, and where the Browser's was put.
    /// Closing returns to the first unless the Browser was moved.
    private var welcomeTopLeft: CGPoint?
    private var browserTopLeft: CGPoint?
    private var observers: [NSObjectProtocol] = []

    /// A new main window (SwiftUI makes one each time it's reopened) takes the size of what it shows.
    func attach(_ window: NSWindow, showsWelcome: Bool) {
        guard window !== self.window else { return }
        observers.forEach(NotificationCenter.default.removeObserver)
        self.window = window
        self.showsWelcome = showsWelcome
        welcomeTopLeft = nil
        browserTopLeft = nil
        locked = false
        styleObservation = window.observe(\.styleMask) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.enforceLock() }
        }
        let center = NotificationCenter.default
        let remember: @Sendable (Notification) -> Void = { [weak self] _ in MainActor.assumeIsolated { self?.rememberBrowserSize() } }
        observers = [
            center.addObserver(forName: NSWindow.didEndLiveResizeNotification, object: window, queue: .main, using: remember),
            center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main, using: remember),
            center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.fit(animated: false) }
            },
        ]
        fit(animated: false)
        // SwiftUI can still put its default or restored frame on the window as it comes on screen.
        Task { @MainActor [weak self] in self?.fit(animated: false) }
    }

    /// The window switches between the welcome and the Browser. Animated only when a click or a
    /// drop caused it, never from the keyboard or under Reduce Motion (DESIGN.md › Motion).
    func show(welcome: Bool, animated: Bool) {
        guard welcome != showsWelcome else { return }
        if welcome { rememberBrowserSize() }
        showsWelcome = welcome
        fit(animated: animated)
    }

    private func fit(animated: Bool) {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        let screen = (window.screen ?? NSScreen.main)?.visibleFrame ?? window.frame
        let topLeft = CGPoint(x: window.frame.minX, y: window.frame.maxY)
        let welcomeFrameSize = window.frameRect(forContentRect: CGRect(origin: .zero, size: Self.welcomeSize)).size
        if showsWelcome {
            // A Browser someone zoomed to fill the screen keeps that size and stays resizable.
            guard locked || !window.isZoomed else { return }
            let anchor = topLeft == browserTopLeft ? welcomeTopLeft ?? topLeft : topLeft
            setLocked(true)
            move(window, to: Self.frame(size: welcomeFrameSize, topLeft: anchor, in: screen), animated: animated, duration: 0.2)
        } else {
            let wasWelcome = locked
            setLocked(false)
            // A window SwiftUI opened straight into the Browser already has its own size.
            guard wasWelcome || window.frame.size == welcomeFrameSize else { return }
            let target = Self.frame(size: Self.browserSize, topLeft: topLeft, in: screen)
            welcomeTopLeft = topLeft
            browserTopLeft = CGPoint(x: target.minX, y: target.maxY)
            move(window, to: target, animated: animated, duration: 0.25)
        }
    }

    private func setLocked(_ locked: Bool) {
        self.locked = locked
        enforceLock()
    }

    private func enforceLock() {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        if locked == window.styleMask.contains(.resizable) {
            if locked { window.styleMask.remove(.resizable) } else { window.styleMask.insert(.resizable) }
        }
    }

    private func rememberBrowserSize() {
        guard !showsWelcome, let window, window.styleMask.contains(.resizable),
              !window.styleMask.contains(.fullScreen) else { return }
        UserDefaults.standard.set(NSStringFromSize(window.frame.size), forKey: Self.browserSizeKey)
    }

    private static var browserSize: CGSize {
        let saved = UserDefaults.standard.string(forKey: browserSizeKey).map(NSSizeFromString) ?? .zero
        return saved.width > 0 && saved.height > 0 ? saved : browserDefault
    }

    /// `size` hung from `topLeft`, moved back on screen where it would overhang, and no bigger than it.
    private static func frame(size: CGSize, topLeft: CGPoint, in screen: CGRect) -> CGRect {
        let width = min(size.width, screen.width), height = min(size.height, screen.height)
        let x = min(max(topLeft.x, screen.minX), screen.maxX - width)
        let top = min(max(topLeft.y, screen.minY + height), screen.maxY)
        return CGRect(x: x, y: top - height, width: width, height: height)
    }

    private func move(_ window: NSWindow, to frame: CGRect, animated: Bool, duration: TimeInterval) {
        guard window.frame != frame else { return }
        guard animated, window.isVisible else { return window.setFrame(frame, display: true) }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            // A strong ease-out: the window answers the click at once and settles softly.
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
            window.animator().setFrame(frame, display: true)
        }
    }
}

extension URL {
    var fileSize: Int64 {
        Int64((try? resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
}
