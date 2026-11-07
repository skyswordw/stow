import AppKit
import SwiftUI

/// Finder's column view: one column per folder on the way to the current one. A selected folder
/// opens as the next column. A selected file previews in Details, which is always beside the files,
/// so the columns don't repeat it in a column of their own (#160).
struct ContentColumns: View {
    @Bindable var model: BrowserModel
    var isSearchFocused: Binding<Bool>
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
                }
                .frame(maxHeight: .infinity)
            }
            .scrollIndicators(.automatic)
            // Columns that open inside a folder (switching from List or Grid, or a new window)
            // start at the newest column, not the root.
            .defaultScrollAnchor(.trailing, for: .initialOffset)
            .onChange(of: parents.count) {
                // Keep the newest column in view; keyboard-speed, so no animation.
                scroller.scrollTo(parents.last, anchor: .trailing)
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear { if !isSearchFocused.wrappedValue { isFocused = true } }
        // Search hands the keyboard back to the files when it lets go (Esc, or a click away),
        // and when the window first opens, so arrow keys work straight away.
        .filesTakeKeyboard($isFocused, isSearchFocused: isSearchFocused)
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
                                guard model.renamingPath == nil else { return }
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
                            // Over a file, the drop goes into this column's folder, and the column says so.
                            .archiveDrop(model: model, folder: entry.path, isEnabled: entry.isNavigable)
                    }
                }
                .padding(.vertical, Space.xs)
            }
            .archiveDrop(model: model, folder: parent)
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
    @Environment(\.colorSchemeContrast) private var contrast
    private var contrastStyle: ContrastStyle { .resolve(contrast) }
    let entry: ArchiveEntry
    let model: BrowserModel
    let isSelected: Bool
    let isOnTheWay: Bool

    var body: some View {
        HStack(spacing: 6) {
            RowIcon(entry: entry, model: model)
                .accessibilityHidden(true)
                .frame(width: 16, height: 16)
            EditingName(model: model, entry: entry)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            if entry.isNavigable {
                Image(systemName: "chevron.right").accessibilityHidden(true)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.8)) : contrastStyle.metadata)
            }
        }
        .font(.body)
        .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .opacity(entry.isHelper ? 0.55 : 1)
        .padding(.horizontal, Space.s)
        .frame(height: 22)
        .background {
            RoundedRectangle(cornerRadius: 5)
                .fill(isSelected ? AnyShapeStyle(.tint) : isOnTheWay ? AnyShapeStyle(.primary.opacity(contrastStyle.borderOpacity)) : AnyShapeStyle(.clear))
                .padding(.horizontal, 6)
        }
        .padding(.horizontal, 6)
        .contentShape(.rect)
        .archiveEntryAccessibility(entry: entry,
                                   isRenaming: model.renamingPath == entry.path) {
            model.select([entry.id])
            model.open(entry)
        }
    }
}

// MARK: - Breadcrumbs

/// Where you are, archive by archive and folder by folder; every part is a place to go back to.
/// Sits in the Browser's navigation capsule, after Back, Forward and Up. A short path takes only its
/// own width, so the capsule hugs it, and the whole route shows while it fits. A deep one folds the
/// folders in its middle into a "…" menu, one at a time, so the archive it starts from and where
/// you are stay readable and every part is still one click away (#242).
struct Breadcrumbs: View {
    @Environment(\.colorSchemeContrast) private var contrast
    private var contrastStyle: ContrastStyle { .resolve(contrast) }
    let model: BrowserModel

    static let height: CGFloat = 28

    var body: some View {
        let segments = model.pathSegments
        ViewThatFits(in: .horizontal) {
            ForEach(Self.folds(count: segments.count), id: \.self) { fold in
                trail(segments, fold: fold)
                    .fixedSize()
            }
            // Nothing fits whole: the menu, then where you are, truncated in the middle.
            trail(segments, fold: Fold(count: segments.count, hidden: segments.count - 1))
        }
        .accessibilityElement(children: .contain)
    }

    /// Which parts of a path of `count` parts show: the first (the archive), then a menu for
    /// `hidden` parts after it, then the rest. The last fold hides everything but where you are.
    struct Fold: Hashable {
        let count: Int
        let hidden: Int

        /// The archive the path starts from stays while anything else does.
        var head: Range<Int> { hidden >= count - 1 ? 0..<0 : 0..<min(1, count) }
        var folded: Range<Int> { head.upperBound..<(head.upperBound + hidden) }
        var tail: Range<Int> { folded.upperBound..<count }
    }

    /// Every way to show a path, from the whole route to only where you are, in the order
    /// `ViewThatFits` tries them.
    static func folds(count: Int) -> [Fold] {
        guard count > 2 else { return [Fold(count: count, hidden: 0)] }
        return (0...(count - 1)).map { Fold(count: count, hidden: $0) }
    }

    private func trail(_ segments: [BrowserModel.PathSegment], fold: Fold) -> some View {
        HStack(spacing: 2) {
            ForEach(fold.head, id: \.self) { index in
                segmentButton(segments[index], index: index, isLast: index == segments.count - 1)
            }
            if !fold.folded.isEmpty {
                if !fold.head.isEmpty { separator }
                foldedMenu(Array(segments[fold.folded]))
            }
            ForEach(fold.tail, id: \.self) { index in
                if index > 0 { separator }
                segmentButton(segments[index], index: index, isLast: index == segments.count - 1)
            }
        }
        .frame(height: Self.height)
    }

    private var separator: some View {
        Image(systemName: "chevron.compact.right").accessibilityHidden(true)
            .font(.caption)
            .foregroundStyle(contrastStyle.metadata)
    }

    private func segmentButton(_ segment: BrowserModel.PathSegment, index: Int, isLast: Bool) -> some View {
        Button {
            model.go(to: segment)
        } label: {
            Label {
                Text(segment.title).lineLimit(1).truncationMode(.middle)
            } icon: {
                icon(segment)
            }
            .font(.callout)
            .fontWeight(isLast ? .semibold : .regular)
            .foregroundStyle(isLast ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .contentShape(.rect)
        }
        .buttonStyle(PathButtonStyle())
        .help(help(segment))
        // Where you are keeps its place; it's the one that may truncate.
        .layoutPriority(isLast ? 0 : 1)
    }

    /// The folders the path has no room for, outermost first, each a place to go.
    private func foldedMenu(_ folded: [BrowserModel.PathSegment]) -> some View {
        Menu {
            ForEach(folded) { segment in
                Button {
                    model.go(to: segment)
                } label: {
                    Label { Text(segment.title) } icon: { icon(segment) }
                }
                .help(help(segment))
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 26, height: Self.height - 6)
                .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(PathButtonStyle())
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(String(localized: "Enclosing Folders"))
        .accessibilityValue(folded.map(\.title).joined(separator: ", "))
        .help(String(localized: "Go to a folder further up: \(folded.map(\.title).joined(separator: " › "))"))
    }

    private func icon(_ segment: BrowserModel.PathSegment) -> some View {
        Image(systemName: segment.isArchive ? "archivebox.fill" : "folder.fill")
            .foregroundStyle(segment.isArchive ? AnyShapeStyle(.accentText) : AnyShapeStyle(.secondary))
    }

    private func help(_ segment: BrowserModel.PathSegment) -> String {
        segment.isArchive ? String(localized: "Go to the top of “\(segment.title)”") : String(localized: "Go to “\(segment.title)”")
    }
}

struct PathButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(.primary.opacity(configuration.isPressed ? 0.12 : isHovering ? 0.06 : 0),
                        in: .capsule)
            .onHover { isHovering = $0 }
    }
}
