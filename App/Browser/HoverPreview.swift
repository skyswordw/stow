import SwiftUI

/// Hover preview timing, per the tooltip rule: the first preview waits so that passing
/// the pointer over the list doesn't flash popovers; once one is open, neighbours
/// open immediately so scanning down a list feels instant.
@Observable
final class HoverPreviewModel {
    private(set) var presented: ArchiveEntry.ID?

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
        let isWarm = presented != nil || Date.now.timeIntervalSince(lastClosed) < warmWindow
        if isWarm {
            presented = entry.id
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
        presented = id
    }

    func close() {
        if presented != nil { lastClosed = .now }
        presented = nil
    }
}

private struct HoverPreviewModifier: ViewModifier {
    let entry: ArchiveEntry
    let model: HoverPreviewModel
    let browser: BrowserModel

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                inside ? model.enter(entry) : model.exit(entry)
                // Drag-out needs to know which entry a press lands on.
                if inside {
                    browser.dragOut.hovered = entry.id
                } else if browser.dragOut.hovered == entry.id {
                    browser.dragOut.hovered = nil
                }
            }
            .popover(isPresented: isPresented, arrowEdge: .trailing) {
                HoverPreviewCard(entry: entry, browser: browser)
            }
    }

    private var isPresented: Binding<Bool> {
        Binding {
            model.presented == entry.id
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
