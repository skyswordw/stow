import SwiftUI

/// Hover preview timing, per the tooltip rule: the first preview waits so that passing
/// the pointer over the list doesn't flash popovers; once one is open, neighbours
/// open immediately so scanning down a list feels instant.
@Observable
final class HoverPreviewModel {
    private(set) var presented: ArchiveEntry.ID? {
        didSet {
            if presented == nil { stopWatching() } else if oldValue == nil { startWatching() }
        }
    }

    /// The popover doesn't dismiss itself: AppKit's outside-click dismissal also swallowed the
    /// click when it landed on the item the popover points at, so the first click on a previewed
    /// file only closed the preview (#167). These close it instead and let the event through: any
    /// press (a click means act, not look) and a window losing the keyboard (Space opening Quick
    /// Look, a sheet, switching apps).
    @ObservationIgnored private var pressMonitor: Any?
    @ObservationIgnored private var resignObserver: (any NSObjectProtocol)?

    private var openTask: Task<Void, Never>?
    private var closeTask: Task<Void, Never>?
    private var lastClosed = Date.distantPast

    private let openDelay = Duration.milliseconds(450)
    private let closeGrace = Duration.milliseconds(120)
    private let warmWindow: TimeInterval = 0.5

    func enter(_ entry: ArchiveEntry) {
        closeTask?.cancel()
        openTask?.cancel()
        // Not while a button is down: that's a drag or a marquee, not a look.
        guard entry.kind.isPreviewable, NSEvent.pressedMouseButtons == 0 else {
            close()
            return
        }
        if isWarm {
            showQuietly(entry.id)
            return
        }
        openTask = Task { [weak self, openDelay] in
            try? await Task.sleep(for: openDelay)
            guard !Task.isCancelled else { return }
            self?.presented = entry.id
        }
    }

    func exit(_ entry: ArchiveEntry) {
        openTask?.cancel()
        closeTask = Task { [weak self, closeGrace] in
            try? await Task.sleep(for: closeGrace)
            guard !Task.isCancelled, let self, self.presented == entry.id else { return }
            self.close()
        }
    }

    /// Opens a preview straight away (design review runs have no pointer).
    func present(_ id: ArchiveEntry.ID) {
        openTask?.cancel()
        if isWarm { showQuietly(id) } else { presented = id }
    }

    /// One is open or just closed: the pointer is scanning the list.
    private var isWarm: Bool {
        presented != nil || Date.now.timeIntervalSince(lastClosed) < warmWindow
    }

    /// Neighbours open instantly and unanimated while one is open (DESIGN.md › Motion); only the
    /// first preview fades in. SwiftUI turns the transaction into the popover's `animates`.
    private func showQuietly(_ id: ArchiveEntry.ID) {
        withTransaction(Self.unanimated) { presented = id }
    }

    private static var unanimated: Transaction {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        return transaction
    }

    /// Closing is instant: an exit never takes longer than the entrance.
    func close() {
        if presented != nil { lastClosed = .now }
        withTransaction(Self.unanimated) { presented = nil }
    }

    private func startWatching() {
        pressMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            // Local monitors run on the main thread, inside event dispatch.
            MainActor.assumeIsolated { self?.close() }
            return event
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    private func stopWatching() {
        if let pressMonitor { NSEvent.removeMonitor(pressMonitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        pressMonitor = nil
        resignObserver = nil
    }

    isolated deinit {
        stopWatching()
    }
}

private struct HoverPreviewModifier: ViewModifier {
    @AppStorage(SettingsKeys.hoverPreviews) private var enabled = true
    let entry: ArchiveEntry
    let model: HoverPreviewModel
    let browser: BrowserModel

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                if enabled && inside { model.enter(entry) } else { model.exit(entry) }
                // Drag-out needs to know which entry a press lands on.
                if inside {
                    browser.dragOut.hovered = entry.id
                } else if browser.dragOut.hovered == entry.id {
                    browser.dragOut.hovered = nil
                }
            }
            .onChange(of: enabled) { if !enabled { model.close() } }
            .popover(isPresented: isPresented, arrowEdge: .trailing) {
                HoverPreviewCard(entry: entry, browser: browser)
                    // The model closes it (see `HoverPreviewModel.presented`), so clicks reach the items.
                    .interactiveDismissDisabled()
            }
    }

    private var isPresented: Binding<Bool> {
        Binding {
            enabled && model.presented == entry.id
        } set: { newValue in
            if !newValue, model.presented == entry.id { model.close() }
        }
    }
}

extension View {
    func hoverPreview(for entry: ArchiveEntry, model: HoverPreviewModel, browser: BrowserModel) -> some View {
        modifier(HoverPreviewModifier(entry: entry, model: model, browser: browser))
    }
}

/// The real thing, read from the archive: a fixed-size card so the popover never jumps when the
/// content arrives.
struct HoverPreviewCard: View {
    let entry: ArchiveEntry
    let browser: BrowserModel

    var body: some View {
        HoverPreviewCardBody(entry: entry, browser: browser)
            // Popovers inherit their anchor's environment; table cells are single-line.
            .lineLimit(nil)
    }
}

struct HoverPreviewCardBody: View {
    let entry: ArchiveEntry
    let browser: BrowserModel
    var preview: RichPreview?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            RichPreviewView(entry: entry, model: browser, preview: preview)
                .frame(width: 300, height: 220)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                    .accessibilityAddTraits(.isHeader)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(entry.kindDescription) · \(entry.size.bytes)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Space.m)
        .frame(width: 324)
    }
}
