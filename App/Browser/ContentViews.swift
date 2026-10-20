import AppKit
import SwiftUI

// MARK: - Grid

struct ContentGrid: View {
    @Bindable var model: BrowserModel

    private let columns = [GridItem(.adaptive(minimum: 128, maximum: 164), spacing: Space.l, alignment: .top)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Space.l) {
                ForEach(model.visibleEntries) { entry in
                    GridTile(entry: entry,
                             isSelected: model.selection.contains(entry.id),
                             showsPath: model.isSearching)
                        .onTapGesture(count: 2) { model.open(entry) }
                        // Select immediately — don't make single clicks wait for double-click detection.
                        .simultaneousGesture(TapGesture().onEnded { select(entry) })
                        .contextMenu { EntryMenu(model: model, entry: entry) }
                }
            }
            .padding(Space.xl)
            .padding(.bottom, 64) // room for the Next Steps capsule
        }
        .background {
            Color.clear
                .contentShape(.rect)
                .onTapGesture { model.selection = [] }
        }
    }

    private func select(_ entry: ArchiveEntry) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if model.selection.contains(entry.id) { model.selection.remove(entry.id) } else { model.selection.insert(entry.id) }
        } else if flags.contains(.shift) {
            model.selection.insert(entry.id)
        } else {
            model.selection = [entry.id]
        }
    }
}

private struct GridTile: View {
    let entry: ArchiveEntry
    let isSelected: Bool
    let showsPath: Bool

    var body: some View {
        VStack(spacing: Space.s) {
            EntryThumbnail(entry: entry, style: .tile)
                .frame(height: 84)
                .frame(maxWidth: .infinity)
                .padding(Space.s)
                .background(.primary.opacity(isSelected ? 0.08 : 0), in: .rect(cornerRadius: Radius.card))

            VStack(spacing: 2) {
                Text(entry.name)
                    .font(.callout)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                    .background(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear),
                                in: .rect(cornerRadius: 5))
                Text(showsPath ? entry.parent.isEmpty ? "Top level" : entry.parent : entry.size.bytes)
                    .font(.caption)
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.head)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: - List

struct ContentList: View {
    @Bindable var model: BrowserModel
    @State private var hover = HoverPreviewModel()

    var body: some View {
        Table(model.visibleEntries, selection: $model.selection) {
            TableColumn("Name") { entry in
                HStack(spacing: Space.s) {
                    EntryThumbnail(entry: entry, style: .row)
                        .frame(width: 18, height: 18)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(entry.name).lineLimit(1)
                        if model.isSearching {
                            Text(entry.parent.isEmpty ? "Top level" : entry.parent)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
                .hoverPreview(for: entry, model: hover)
            }
            .width(min: 220, ideal: 320)

            TableColumn("Size") { entry in
                Text(entry.size.bytes)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(min: 70, ideal: 90)
            .alignment(.trailing)

            TableColumn("Kind") { entry in
                Text(entry.kind.label).foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 120)

            TableColumn("Modified") { entry in
                Text(entry.modified, format: .dateTime.day().month(.abbreviated).year())
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 120)
        }
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
    }
}

struct EntryMenu: View {
    let model: BrowserModel
    let entry: ArchiveEntry

    var body: some View {
        let steps = NextStep.suggestions(for: [entry])
        ForEach(steps) { step in
            Button(step.title, systemImage: step.symbol) { model.run(step, on: [entry]) }
        }
        Divider()
        Button("Copy Name", systemImage: "doc.on.doc") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(entry.name, forType: .string)
        }
    }
}
