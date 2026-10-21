import AppKit
import SwiftUI

/// Finder's column view: one column per folder on the way to the current one, and a preview of a
/// selected file at the end. A selected folder opens as the next column.
struct ContentColumns: View {
    @Bindable var model: BrowserModel
    @FocusState private var isFocused: Bool

    static let columnWidth: CGFloat = 240

    var body: some View {
        let parents = columnParents
        ScrollViewReader { scroller in
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(parents, id: \.self) { parent in
                        Column(model: model, parent: parent, onTap: { isFocused = true })
                            .frame(width: Self.columnWidth)
                        Divider()
                    }
                    if let file = previewedFile {
                        PreviewColumn(entry: file, model: model)
                            .frame(width: 300)
                            .id("preview")
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .scrollIndicators(.automatic)
            .onChange(of: parents.count + (previewedFile == nil ? 0 : 1000)) {
                // Keep the newest column in view; keyboard-speed, so no animation.
                scroller.scrollTo(previewedFile == nil ? parents.last : "preview", anchor: .trailing)
            }
        }
        .safeAreaPadding(.bottom, 56)
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear { isFocused = true }
        .browserKeys(model)
    }

    /// The root and each folder down to the current one.
    private var columnParents: [String] {
        var parents = [""]
        var path = ""
        for component in model.folder.split(separator: "/") {
            path = path.isEmpty ? String(component) : path + "/" + component
            parents.append(path)
        }
        return parents
    }

    private var previewedFile: ArchiveEntry? {
        guard model.selection.count == 1, let id = model.selection.first,
              let entry = model.archive.entry(at: id), !entry.isNavigable, entry.parent == model.folder else { return nil }
        return entry
    }
}

private struct Column: View {
    let model: BrowserModel
    let parent: String
    let onTap: () -> Void
    @State private var hover = HoverPreviewModel()

    var body: some View {
        let entries = model.archive.children(of: parent, includingHelpers: model.showHelperItems)
        // The folder this column leads to (shown in grey) and whether this column has the keyboard.
        let onTheWay = Self.child(of: parent, toward: model.folder)
        ScrollViewReader { scroller in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(entries) { entry in
                        let selected = model.selection.contains(entry.id)
                        Row(entry: entry, model: model, isSelected: selected, isOnTheWay: !selected && entry.id == onTheWay)
                            .id(entry.id)
                            .onTapGesture(count: 2) { model.open(entry) }
                            .simultaneousGesture(TapGesture().onEnded {
                                onTap()
                                model.columnSelect(entry, modifiers: NSEvent.modifierFlags)
                            })
                            .onHover { inside in
                                if inside {
                                    model.dragOut.hovered = entry.id
                                } else if model.dragOut.hovered == entry.id {
                                    model.dragOut.hovered = nil
                                }
                            }
                            .contextMenu { EntryMenu(model: model, entry: entry) }
                    }
                }
                .padding(.vertical, Space.xs)
            }
            .background {
                // Empty space in a column: nothing selected, this column is the last one.
                Color.clear
                    .contentShape(.rect)
                    .onTapGesture {
                        onTap()
                        model.folder = parent
                        model.select([])
                    }
            }
            .onChange(of: model.scrollTarget) { _, target in
                guard let target, entries.contains(where: { $0.id == target }) else { return }
                scroller.scrollTo(target)
                model.scrollTarget = nil
            }
        }
    }

    static func child(of parent: String, toward folder: String) -> String? {
        let prefix = parent.isEmpty ? "" : parent + "/"
        guard folder.hasPrefix(prefix), folder.count > prefix.count else { return nil }
        return prefix + (folder.dropFirst(prefix.count).split(separator: "/").first.map(String.init) ?? "")
    }
}

private struct Row: View {
    let entry: ArchiveEntry
    let model: BrowserModel
    let isSelected: Bool
    let isOnTheWay: Bool

    var body: some View {
        HStack(spacing: 6) {
            RowIcon(entry: entry, model: model)
                .frame(width: 16, height: 16)
            Text(entry.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            if entry.isNavigable {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.tertiary))
            }
        }
        .font(.body)
        .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .opacity(entry.isHelper ? 0.55 : 1)
        .padding(.horizontal, Space.s)
        .frame(height: 22)
        .background {
            RoundedRectangle(cornerRadius: 5)
                .fill(isSelected ? AnyShapeStyle(.tint) : isOnTheWay ? AnyShapeStyle(.primary.opacity(0.1)) : AnyShapeStyle(.clear))
                .padding(.horizontal, 6)
        }
        .padding(.horizontal, 6)
        .contentShape(.rect)
    }
}

/// The last column for a selected file: its real content and the facts about it.
private struct PreviewColumn: View {
    let entry: ArchiveEntry
    let model: BrowserModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.m) {
                RichPreviewView(entry: entry, model: model)
                    .frame(height: 220)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name).font(.headline).textSelection(.enabled)
                    Text("\(entry.kindDescription) · \(entry.size.bytes)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                MetadataGrid(rows: [
                    (String(localized: "Modified"), entry.modified.formatted(date: .abbreviated, time: .shortened)),
                    (String(localized: "Packed"), entry.packedSize.bytes),
                ])
            }
            .padding(Space.l)
        }
    }
}

// MARK: - Path bar

/// Where you are, archive by archive and folder by folder; every part is a place to go back to.
struct PathBar: View {
    let model: BrowserModel

    static let height: CGFloat = 28

    var body: some View {
        let segments = model.pathSegments
        ScrollView(.horizontal) {
            HStack(spacing: 2) {
                ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                    if index > 0 {
                        Image(systemName: "chevron.compact.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Button {
                        model.go(to: segment)
                    } label: {
                        Label {
                            Text(segment.title).lineLimit(1)
                        } icon: {
                            Image(systemName: segment.isArchive ? "archivebox.fill" : "folder.fill")
                                .foregroundStyle(segment.isArchive ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        }
                        .font(.caption)
                        .fontWeight(index == segments.count - 1 ? .semibold : .regular)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .contentShape(.rect)
                    }
                    .buttonStyle(PathButtonStyle())
                    .help(segment.isArchive ? String(localized: "Go to the top of “\(segment.title)”") : String(localized: "Go to “\(segment.title)”"))
                }
            }
            .padding(.horizontal, Space.m)
            .frame(height: Self.height)
        }
        .scrollIndicators(.never)
        .defaultScrollAnchor(.leading, for: .alignment)
        .defaultScrollAnchor(.trailing, for: .initialOffset)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Path")
    }
}

private struct PathButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(.primary.opacity(configuration.isPressed ? 0.12 : isHovering ? 0.06 : 0),
                        in: .rect(cornerRadius: 5))
            .onHover { isHovering = $0 }
    }
}
