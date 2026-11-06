import AppKit
import Observation
import QuickLookThumbnailing
import SwiftUI

/// Where a draft's window is looking (#302): the folder, its history, the view mode and Search,
/// as the Browser keeps them for an archive. Only what the window shows; the planned files stay
/// the draft's. View › as Icons/List/Columns and Edit › Find… reach it through the draft.
@Observable
final class DraftBrowsing {
    var folder = "" { didSet { if oldValue != folder { locationChanged?() } } }
    var viewMode = BrowserModel.ViewMode.list { didSet { if oldValue != viewMode { locationChanged?() } } }
    var query = "" { didSet { if oldValue != query { locationChanged?() } } }
    @ObservationIgnored var locationChanged: (() -> Void)?
    var gridColumns = 1
    var scrollTarget: String?
    private var cursor: String?
    private var anchor: String?
    /// Bumped by ⌘F, like the Browser's `searchFocusRequest`.
    var searchFocusRequest = 0
    private(set) var back: [String] = []
    private(set) var forward: [String] = []
    /// Every planned item by path, rebuilt with the tree when the files change.
    private(set) var nodes: [String: DraftNode] = [:]
    private(set) var roots: [DraftNode] = []

    var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    var canGoBack: Bool { !back.isEmpty }
    var canGoForward: Bool { !forward.isEmpty }
    var canGoUp: Bool { !folder.isEmpty }

    func update(tree: [DraftNode]) {
        roots = tree
        var index: [String: DraftNode] = [:]
        func walk(_ nodes: [DraftNode]) {
            for node in nodes {
                index[node.id] = node
                if let children = node.children { walk(children) }
            }
        }
        walk(tree)
        nodes = index
        // A removed folder (or Undo of its add) takes you to the nearest one still planned.
        while !folder.isEmpty, index[folder]?.file.isFolder != true { folder = ArchiveEntry.parent(of: folder) }
        back.removeAll { !$0.isEmpty && index[$0]?.file.isFolder != true }
        forward.removeAll { !$0.isEmpty && index[$0]?.file.isFolder != true }
        locationChanged?()
    }

    func children(of path: String) -> [DraftNode] {
        path.isEmpty ? roots : (nodes[path]?.children ?? [])
    }

    /// What the files area lists: the folder, or every match while searching.
    var visible: [DraftNode] {
        guard isSearching else { return children(of: folder) }
        let query = query.trimmingCharacters(in: .whitespaces)
        return nodes.values
            .filter { $0.name.localizedStandardContains(query) }
            .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    func go(to path: String) {
        guard path != folder, path.isEmpty || nodes[path]?.file.isFolder == true else { return }
        query = ""
        back.append(folder)
        forward = []
        folder = path
    }

    func goBack() {
        guard let previous = back.popLast() else { return }
        query = ""
        forward.append(folder)
        folder = previous
    }

    func goForward() {
        guard let next = forward.popLast() else { return }
        query = ""
        back.append(folder)
        folder = next
    }

    func goUp() { if canGoUp { go(to: ArchiveEntry.parent(of: folder)) } }

    /// Columns show the ancestor columns too; every other mode only selects visible rows/hits.
    var selectablePaths: Set<String> {
        guard viewMode == .columns, !isSearching else { return Set(visible.map(\.id)) }
        return Set(([""] + segments.map(\.path)).flatMap { children(of: $0).map(\.id) })
    }

    func move(_ direction: BrowserModel.Direction, selection: Set<String>, extending: Bool) -> Set<String> {
        if viewMode == .columns, !isSearching {
            let current = cursor.flatMap { selection.contains($0) ? nodes[$0] : nil }
                ?? selection.sorted().first.flatMap { nodes[$0] }
            var next = current
            if let current {
                let parent = ArchiveEntry.parent(of: current.id)
                let siblings = children(of: parent)
                switch direction {
                case .up, .down:
                    if let index = siblings.firstIndex(where: { $0.id == current.id }) {
                        next = siblings[max(0, min(siblings.count - 1, index + (direction == .down ? 1 : -1)))]
                    }
                case .right:
                    if current.file.isFolder { next = children(of: current.id).first ?? current }
                case .left:
                    if !parent.isEmpty { next = nodes[parent] }
                }
            } else { next = visible.first }
            guard let next else { return selection }
            go(to: next.file.isFolder ? next.id : ArchiveEntry.parent(of: next.id))
            cursor = next.id
            anchor = next.id
            scrollTarget = next.id
            return [next.id]
        }
        let items = visible
        guard !items.isEmpty else { return [] }
        let step: Int
        switch direction {
        case .up: step = viewMode == .grid ? -max(1, gridColumns) : -1
        case .down: step = viewMode == .grid ? max(1, gridColumns) : 1
        case .left: guard viewMode == .grid else { return selection }; step = -1
        case .right: guard viewMode == .grid else { return selection }; step = 1
        }
        let current = cursor.flatMap { id in selection.contains(id) ? items.firstIndex { $0.id == id } : nil }
            ?? items.firstIndex { selection.contains($0.id) }
        let index = current.map { max(0, min(items.count - 1, $0 + step)) } ?? (step > 0 ? 0 : items.count - 1)
        let id = items[index].id
        let start = anchor.flatMap { id in selection.contains(id) ? items.firstIndex { $0.id == id } : nil } ?? current ?? index
        cursor = id
        scrollTarget = id
        if extending {
            anchor = items[start].id
            return Set(items[min(start, index)...max(start, index)].map(\.id))
        }
        anchor = id
        return [id]
    }

    /// A folder opens; a file shows where it is (a search hit's folder), as the Browser's Open does
    /// for a file it can't preview here.
    func open(_ node: DraftNode) {
        if node.file.isFolder {
            query = ""
            go(to: node.id)
        } else if isSearching {
            query = ""
            go(to: ArchiveEntry.parent(of: node.id))
        }
    }

    /// The path as the Browser's breadcrumbs show it: the archive, then each folder.
    var segments: [(title: String, path: String)] {
        var result: [(String, String)] = []
        var path = ""
        for component in folder.split(separator: "/") {
            path = path.isEmpty ? String(component) : path + "/" + component
            result.append((String(component), path))
        }
        return result
    }
}

// MARK: - Navigation

/// The Browser's navigation capsule for a draft: Back, Forward and Up beside where you are, the
/// archive-to-be first, in the same glass and sizes (#242).
struct DraftNavigation: View {
    let browsing: DraftBrowsing
    let archiveName: String

    var body: some View {
        HStack(spacing: Space.s) {
            HStack(spacing: 0) {
                button(String(localized: "Back"), "chevron.left", help: String(localized: "See the previous place"),
                       enabled: browsing.canGoBack) { browsing.goBack() }
                button(String(localized: "Forward"), "chevron.right", help: String(localized: "See the next place"),
                       enabled: browsing.canGoForward) { browsing.goForward() }
                button(String(localized: "Enclosing Folder"), "arrow.up", help: String(localized: "See the folder this one is in"),
                       enabled: browsing.canGoUp) { browsing.goUp() }
                Rectangle()
                    .fill(.separator)
                    .frame(width: 1, height: 16)
                    .padding(.horizontal, Space.xs)
                    .accessibilityHidden(true)
                trail
                    .padding(.trailing, Space.xs)
            }
            .padding(FloatingGlass.barInset)
            .frame(height: FloatingGlass.barHeight)
            .accessibleGlass(in: .capsule)
            .accessibilityElement(children: .contain)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, FloatingGlass.edgeInset)
        .padding(.top, FloatingGlass.topInset)
        .padding(.bottom, Space.s)
    }

    private func button(_ title: String, _ symbol: String, help: String, enabled: Bool,
                        action: @escaping () -> Void) -> some View {
        Button(title, systemImage: symbol, action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(ActionButtonStyle(iconOnly: true, height: FloatingGlass.barHeight - 2 * FloatingGlass.barInset))
            .accessibilityLabel(title)
            .help(help)
            .disabled(!enabled)
    }

    /// The whole route while it fits; otherwise the archive and where you are.
    private var trail: some View {
        let segments = browsing.segments
        return ViewThatFits(in: .horizontal) {
            route(segments, skipping: 0)
            if segments.count > 1 { route(segments, skipping: segments.count - 1) }
        }
        .frame(height: Breadcrumbs.height)
    }

    private func route(_ segments: [(title: String, path: String)], skipping hidden: Int) -> some View {
        HStack(spacing: 2) {
            segment(archiveName, path: "", isArchive: true, isLast: segments.isEmpty)
            if hidden > 0 {
                separator
                Text(verbatim: "…").font(.callout).foregroundStyle(.secondary).accessibilityHidden(true)
            }
            ForEach(Array(segments.enumerated()).dropFirst(hidden), id: \.element.path) { index, item in
                separator
                segment(item.title, path: item.path, isArchive: false, isLast: index == segments.count - 1)
            }
        }
        .fixedSize()
    }

    private var separator: some View {
        Image(systemName: "chevron.compact.right")
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }

    private func segment(_ title: String, path: String, isArchive: Bool, isLast: Bool) -> some View {
        Button {
            browsing.query = ""
            browsing.go(to: path)
        } label: {
            Label {
                Text(verbatim: title).lineLimit(1).truncationMode(.middle)
            } icon: {
                Image(systemName: isArchive ? "archivebox.fill" : "folder.fill")
                    .foregroundStyle(isArchive ? AnyShapeStyle(.accentText) : AnyShapeStyle(.secondary))
            }
            .font(.callout)
            .fontWeight(isLast ? .semibold : .regular)
            .foregroundStyle(isLast ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .contentShape(.rect)
        }
        .buttonStyle(PathButtonStyle())
        .help(isArchive ? String(localized: "Go to the top of “\(title)”") : String(localized: "Go to “\(title)”"))
    }
}

// MARK: - Icons

/// The Browser's icon grid for planned items: the original's Quick Look thumbnail or Finder icon,
/// its name (in the accent while selected) and its size. A click selects, ⌘-click adds or takes
/// away, a double-click opens a folder.
struct DraftGrid: View {
    @Bindable var draft: ArchiveDraft
    let browsing: DraftBrowsing
    let arrived: Set<String>

    var body: some View {
        GeometryReader { proxy in
            let metrics = GridMetrics(width: proxy.size.width)
            let items = browsing.visible
            ScrollViewReader { scroller in
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(metrics.tileWidth), spacing: GridMetrics.spacing, alignment: .top),
                                             count: metrics.columns),
                              alignment: .leading, spacing: GridMetrics.spacing) {
                        ForEach(items) { node in
                            DraftTile(node: node, isSelected: draft.selection.contains(node.id),
                                      hasArrived: arrived.contains(node.id),
                                      location: browsing.isSearching ? ArchiveEntry.parent(of: node.id) : nil)
                                .frame(width: metrics.tileWidth, height: GridMetrics.tileHeight, alignment: .top)
                                .id(node.id)
                                .onTapGesture(count: 2) {
                                    draft.open(node)
                                }
                                .simultaneousGesture(TapGesture().onEnded { select(node) })
                                .contextMenu { DraftItemMenu(draft: draft, paths: menuPaths(for: node)) }
                        }
                    }
                    .padding(GridMetrics.inset)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background {
                    Color.clear.contentShape(.rect).onTapGesture { draft.selection = [] }
                }
                .onChange(of: browsing.scrollTarget) { _, target in
                    if let target { scroller.scrollTo(target) }
                }
            }
            .onAppear { browsing.gridColumns = metrics.columns }
            .onChange(of: metrics.columns) { _, value in browsing.gridColumns = value }
        }
    }

    private func select(_ node: DraftNode) {
        // A double-click may have opened its folder before the simultaneous single-click fires.
        guard browsing.visible.contains(where: { $0.id == node.id }) else { return }
        if NSEvent.modifierFlags.contains(.command) {
            if draft.selection.contains(node.id) { draft.selection.remove(node.id) } else { draft.selection.insert(node.id) }
        } else {
            draft.selection = [node.id]
        }
    }

    private func menuPaths(for node: DraftNode) -> Set<String> {
        draft.selection.contains(node.id) ? draft.selection : [node.id]
    }
}

private struct DraftTile: View {
    @Environment(\.colorSchemeContrast) private var contrast
    let node: DraftNode
    let isSelected: Bool
    let hasArrived: Bool
    let location: String?

    var body: some View {
        VStack(spacing: Space.s) {
            DraftThumbnail(file: node.file)
                .frame(height: 84)
                .frame(maxWidth: .infinity)
                .padding(Space.s)
                .background(.primary.opacity(isSelected ? 0.08 : 0), in: .rect(cornerRadius: Radius.card))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.card)
                        .strokeBorder(hasArrived ? AnyShapeStyle(.tint)
                                      : AnyShapeStyle(.primary.opacity(ContrastStyle.resolve(contrast).increased && isSelected ? 0.45 : 0)),
                                      lineWidth: hasArrived ? 1.5 : 1)
                        .allowsHitTesting(false)
                }
                .accessibilityHidden(true)
            VStack(spacing: 2) {
                Text(verbatim: node.name)
                    .font(.callout)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                    .background(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 5))
                Text(verbatim: location.map { $0.isEmpty ? "—" : $0 } ?? node.bytes.bytes)
                    .font(.caption)
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.head)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: node.name))
        .accessibilityValue(Text(verbatim: node.bytes.bytes))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A picture or a page as Quick Look draws it, in Finder's icon mode; a folder or anything
/// Quick Look can't draw keeps its Finder icon.
private struct DraftThumbnail: View {
    let file: PackFile
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            } else {
                DraftIcon(file: file).frame(width: 64, height: 64)
            }
        }
        .task(id: file.source) {
            image = nil
            guard let url = file.source, !file.isFolder, !file.isLink else { return }
            // Decorated as Finder draws it (a page's edge, a photo's frame), as the Tray does; a
            // bare page of text reads as an empty square on the window.
            let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 84, height: 84),
                                                       scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .all)
            request.iconMode = true
            let result = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
            guard !Task.isCancelled else { return }
            image = result
        }
    }
}

// MARK: - Columns

/// Finder's column view for a draft: one column per folder on the way to the current one; a
/// selected folder opens as the next column, a selected file shows in Details.
struct DraftColumns: View {
    @Bindable var draft: ArchiveDraft
    let browsing: DraftBrowsing
    let arrived: Set<String>

    var body: some View {
        let parents = [""] + browsing.segments.map(\.path)
        ScrollViewReader { scroller in
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(parents, id: \.self) { parent in
                        column(parent)
                            .frame(width: ContentColumns.columnWidth)
                        Divider()
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .defaultScrollAnchor(.trailing, for: .initialOffset)
            .onChange(of: parents.count) { scroller.scrollTo(parents.last, anchor: .trailing) }
        }
    }

    private func column(_ parent: String) -> some View {
        let onTheWay = Self.child(of: parent, toward: browsing.folder)
        return ScrollViewReader { scroller in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(browsing.children(of: parent)) { node in
                        let selected = draft.selection.contains(node.id)
                        DraftColumnRow(node: node, isSelected: selected, isOnTheWay: !selected && node.id == onTheWay,
                                       hasArrived: arrived.contains(node.id))
                            .id(node.id)
                            .onTapGesture { select(node) }
                            .contextMenu {
                                DraftItemMenu(draft: draft, paths: draft.selection.contains(node.id) ? draft.selection : [node.id])
                            }
                    }
                }
                .padding(.vertical, Space.xs)
            }
            .id(parent)
            .onChange(of: browsing.scrollTarget) { _, target in
                guard let target, browsing.children(of: parent).contains(where: { $0.id == target }) else { return }
                scroller.scrollTo(target)
            }
            .background {
                Color.clear.contentShape(.rect).onTapGesture {
                    browsing.go(to: parent)
                    draft.selection = []
                }
            }
        }
    }

    /// A folder opens as the next column; a file stays in its folder's column.
    private func select(_ node: DraftNode) {
        draft.selection = [node.id]
        browsing.go(to: node.file.isFolder ? node.id : ArchiveEntry.parent(of: node.id))
    }

    static func child(of parent: String, toward folder: String) -> String? {
        let prefix = parent.isEmpty ? "" : parent + "/"
        guard folder.hasPrefix(prefix), folder.count > prefix.count else { return nil }
        return prefix + (folder.dropFirst(prefix.count).split(separator: "/").first.map(String.init) ?? "")
    }
}

private struct DraftColumnRow: View {
    @Environment(\.colorSchemeContrast) private var contrast
    let node: DraftNode
    let isSelected: Bool
    let isOnTheWay: Bool
    let hasArrived: Bool

    var body: some View {
        let contrastStyle = ContrastStyle.resolve(contrast)
        HStack(spacing: 6) {
            DraftIcon(file: node.file)
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
            Text(verbatim: node.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            if node.file.isFolder {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.8)) : contrastStyle.metadata)
                    .accessibilityHidden(true)
            }
        }
        .font(.body)
        .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .padding(.horizontal, Space.s)
        .frame(height: 22)
        .background {
            RoundedRectangle(cornerRadius: 5)
                .fill(isSelected ? AnyShapeStyle(.tint) : isOnTheWay ? AnyShapeStyle(.primary.opacity(contrastStyle.borderOpacity)) : AnyShapeStyle(.clear))
                .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(.tint, lineWidth: 1.5).opacity(hasArrived ? 1 : 0) }
                .padding(.horizontal, 6)
        }
        .padding(.horizontal, 6)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: node.name))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Item menu

/// What the planned items' context menu offers in every view: take them out, or find the originals.
struct DraftItemMenu: View {
    let draft: ArchiveDraft
    let paths: Set<String>

    var body: some View {
        if !paths.isEmpty {
            Button {
                draft.selection = paths
                draft.removeSelection()
            } label: {
                Text(paths.count > 1 ? String(localized: "Remove \(paths.count) Items") : String(localized: "Remove"))
                Text("The originals stay where they are")
            }
            .disabled(draft.isImporting || draft.isSaving)
            Divider()
            Button("Show in Finder") {
                let urls = draft.files.filter { paths.contains($0.path) }.compactMap(\.source)
                NSWorkspace.shared.activateFileViewerSelecting(urls)
            }
        }
    }
}

extension View {
    /// Keep file navigation on the focused files surface; title/search field editing stays native.
    func draftKeys(_ draft: ArchiveDraft, handlesArrows: Bool = true) -> some View {
        self
            .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { press in
                guard handlesArrows, !draft.isImporting, !draft.isSaving,
                      press.modifiers.isDisjoint(with: [.command, .option, .control]) else { return .ignored }
                let direction: BrowserModel.Direction = switch press.key {
                case .upArrow: .up
                case .downArrow: .down
                case .leftArrow: .left
                default: .right
                }
                draft.selection = draft.browsing.move(direction, selection: draft.selection,
                                                       extending: press.modifiers.contains(.shift))
                return .handled
            }
            .onKeyPress(.return) {
                guard !draft.isImporting, !draft.isSaving, draft.selection.count == 1,
                      let path = draft.selection.first, let node = draft.browsing.nodes[path] else { return .ignored }
                draft.open(node)
                return .handled
            }
            .onKeyPress(characters: CharacterSet(charactersIn: "a"), phases: .down) { press in
                guard handlesArrows, press.modifiers == .command,
                      !draft.isImporting, !draft.isSaving else { return .ignored }
                draft.selection = Set(draft.browsing.visible.map(\.id))
                return .handled
            }
            .onKeyPress(keys: [.delete], phases: .down) { press in
                guard !draft.isImporting, !draft.isSaving, !draft.selection.isEmpty,
                      press.modifiers.isDisjoint(with: [.command, .option, .control]) else { return .ignored }
                draft.removeSelection()
                return .handled
            }
    }
}
