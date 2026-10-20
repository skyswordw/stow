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
        guard entry.kind.isPreviewable else {
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

    func close() {
        if presented != nil { lastClosed = .now }
        presented = nil
    }
}

private struct HoverPreviewModifier: ViewModifier {
    let entry: ArchiveEntry
    let model: HoverPreviewModel

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                inside ? model.enter(entry) : model.exit(entry)
            }
            .popover(isPresented: isPresented, arrowEdge: .trailing) {
                HoverPreviewCard(entry: entry)
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
    func hoverPreview(for entry: ArchiveEntry, model: HoverPreviewModel) -> some View {
        modifier(HoverPreviewModifier(entry: entry, model: model))
    }
}

struct HoverPreviewCard: View {
    let entry: ArchiveEntry

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            EntryThumbnail(entry: entry, style: .large)
                .frame(width: 280)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text("\(entry.kind.label) · \(entry.size.bytes)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Space.m)
    }
}
