import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A new archive that isn't written yet (#293), laid out as the Browser is (#302), so making an
/// archive and opening one read as the same workspace. Where the Browser names the archive, the
/// title bar names this one (its name and format, both editable, over what it plans); where the
/// Browser keeps Delete · Save, this keeps Remove · Pack…; where Extract All floats, Add Files…
/// does. The planned files take the Browser's list and columns, folders open in place, and Details
/// beside them tells the real sources' facts — never a packed size or a password before Pack has
/// made them. Nothing on disk changes until the pack succeeds; the originals never do.
/// DESIGN.md › New archive draft.
struct ArchiveDraftView: View {
    @Bindable var draft: ArchiveDraft
    @Environment(AppState.self) private var app
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.reducesMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var delegate = CreationWindowDelegate()
    /// The planned contents as a tree, rebuilt only when the files change (not on every selection).
    @State private var tree: [DraftNode] = []
    /// Top-level items an add (or an Undo) just brought in: ringed in the accent for a moment, as
    /// in the Tray.
    @State private var arrived: Set<String> = []
    @State private var isTargeted = false
    @State private var isPromiseTargeted = false
    /// The list takes the keyboard when it appears, as the Browser's files do.
    @FocusState private var listFocused: Bool

    private var contrastStyle: ContrastStyle { .resolve(contrast) }
    private var highlighted: Bool { isTargeted || isPromiseTargeted }
    private var isEmpty: Bool { draft.files.isEmpty }
    private var isBusy: Bool { draft.isImporting || draft.isSaving }
    private var canAdd: Bool { !draft.isImporting && !draft.isChoosingSources && !draft.isSaving }

    var body: some View {
        files
            .frame(minWidth: BrowserView.minFilesWidth)
            .safeAreaInset(edge: .top, spacing: 0) { banner }
            // Room for the floating glass, so the last row scrolls clear of it.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear
                    .frame(height: isEmpty && !draft.isSaving ? 0 : Self.floatingHeight)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .overlay(alignment: .bottom) { floatingControls }
            // Details is part of the window, as in the Browser: no toggle, no close button.
            .inspector(isPresented: .constant(true)) {
                DraftDetails(draft: draft)
                    .accessibilitySortPriority(1)
                    .inspectorColumnWidth(min: 250, ideal: DetailsPane.idealWidth, max: 400)
            }
            // The window keeps its title for the Window menu and Mission Control; the title bar
            // shows the editable name instead.
            .navigationTitle(draft.name.isEmpty ? String(localized: "Untitled Archive") : draft.name)
            .toolbar(removing: .title)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .toolbar { toolbar }
            .animation(Motion.byKeyboard ? nil : Motion.resolved(Motion.status, reduceMotion: reduceMotion), value: isEmpty)
            .animation(Motion.presence(draft.isSaving, reduceMotion: reduceMotion), value: draft.isSaving)
            // Drags that only promise a file (Mail, Photos, chat apps) land anywhere in the window.
            .onDrop(of: OtherAppFiles.promisedTypes, isTargeted: $isPromiseTargeted) { providers in
                guard canAdd else { return false }
                draft.receivePromises(providers)
                return true
            }
            .onKeyPress(.escape) {
                guard !draft.selection.isEmpty else { return .ignored }
                draft.selection = []
                return .handled
            }
            .onChange(of: draft.files, initial: true) { old, new in
                tree = DraftNode.tree(from: new)
                noteArrivals(old: old, new: new)
            }
            .background {
                WindowReader { window in
                    delegate.attach(window, draft: draft) {
                        if app.archiveDraft === draft { app.archiveDraft = nil }
                    }
                }
            }
            .sheet(item: $draft.packRequest, onDismiss: {
                if !draft.isSaving { draft.quitAfterSave = false }
            }) { request in
                PackSheet(request: request, draft: draft) { urls in
                    let quitting = draft.quitAfterSave
                    dismissWindow(id: "creation")
                    if app.archiveDraft === draft { app.archiveDraft = nil }
                    if quitting { NSApp.terminate(nil) }
                    else if let first = urls.first {
                        app.open(first)
                        app.showMainWindow()
                    }
                }.environment(app)
            }
    }

    /// The floating row's height and the gaps around it, as the Browser reserves under its files.
    private static let floatingHeight = FloatingGlass.barHeight + Space.s + FloatingGlass.edgeInset

    // MARK: Title bar

    /// The Browser's arrangement: the archive itself on the leading side, editing at the trailing
    /// end. Remove · Pack… share one capsule as Delete · Save do, and Pack takes the accent and its
    /// name once there's something to pack, as Save does once there's something to save.
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            DraftTitle(draft: draft, subtitle: subtitle)
                .disabled(draft.isSaving)
        }
        .sharedBackgroundVisibility(.hidden)

        ToolbarSpacer(.flexible)

        ToolbarItemGroup {
            Button {
                draft.removeSelection()
            } label: {
                Label("Remove", systemImage: "minus.circle")
            }
            .disabled(draft.selection.isEmpty || isBusy)
            .help(draft.selection.isEmpty ? String(localized: "Select files to take them out of this archive")
                  : String(localized: "Take the selection out of this archive. The originals stay where they are."))
            .accessibilityLabel(String(localized: "Remove"))

            Group {
                if isEmpty {
                    packButton.disabled(true)
                } else {
                    // Says its name once there's something to pack: an icon alone in a filled
                    // circle reads as a pressed button.
                    packButton
                        .labelStyle(.titleAndIcon)
                        .buttonStyle(.borderedProminent)
                        .disabled(!draft.canSave || app.packing.isRunning)
                }
            }
            .help(isEmpty ? String(localized: "Add files to pack this archive")
                  : String(localized: "Choose how to pack it and where to put it"))
            .accessibilityLabel(String(localized: "Pack…"))
        }
    }

    /// Tray's Pack glyph: a box the files go into.
    private var packButton: some View {
        Button {
            draft.prepareSave()
        } label: {
            Label("Pack…", systemImage: "archivebox")
        }
    }

    /// Never a final size: these are the originals, before compression. The archive's own size is
    /// known only once it's packed.
    private var subtitle: String {
        if draft.isImporting { return String(localized: "Adding files…") }
        let unpacked = String(localized: "Not packed yet")
        guard !isEmpty else { return unpacked }
        let bytes = draft.files.reduce(Int64(0)) { $0 + ($1.isFolder ? 0 : $1.size) }
        return unpacked + " · " + DraftSummary.text(items: tree.count, bytes: bytes)
    }

    // MARK: Problem

    /// An add or a pack that went wrong, where the Browser shows its notices: under the title bar,
    /// over the files.
    @ViewBuilder private var banner: some View {
        if let problem = draft.problem {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .accessibilityHidden(true)
                Text(verbatim: problem)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Dismiss", systemImage: "xmark") {
                    withAnimation(Motion.presence(false, reduceMotion: reduceMotion)) { draft.problem = nil }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(contrastStyle.metadata)
            }
            .font(.callout)
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.s)
            .background(.yellow.opacity(0.12), in: .rect(cornerRadius: Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card)
                    .strokeBorder(.yellow.opacity(contrastStyle.increased ? 0.8 : 0.3))
            }
            .accessibilityElement(children: .contain)
            .padding(.horizontal, FloatingGlass.edgeInset)
            .padding(.top, FloatingGlass.topInset)
            .padding(.bottom, Space.s)
            .transition(.opacity.animation(Motion.byKeyboard ? nil : Motion.resolved(Motion.status, reduceMotion: reduceMotion)))
        }
    }

    // MARK: Files

    /// The whole files area takes drops. While something is held over it, an accent edge inset as
    /// far as Details is, with a light tint, says where it lands.
    private var files: some View {
        ZStack {
            if isEmpty {
                empty.transition(.opacity)
            } else {
                list.transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            let shape = RoundedRectangle(cornerRadius: Radius.windowPanel, style: .continuous)
            shape.fill(.tint.opacity(0.06))
                .overlay { shape.strokeBorder(.tint, lineWidth: 2) }
                .padding(Radius.windowInset)
                .opacity(highlighted ? 1 : 0)
                .allowsHitTesting(false)
                .animation(Motion.resolved(Motion.target, reduceMotion: reduceMotion), value: highlighted)
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard canAdd else { return false }
            Task { await draft.add(urls) }
            return true
        } isTargeted: { isTargeted = $0 }
    }

    /// Nothing planned yet. A dashed edge where the files will be, the same shape and inset as
    /// Details beside it, says the space takes a drop; Add Files… is the window's one prominent
    /// button until there's something to pack.
    private var empty: some View {
        ContentUnavailableView {
            Label {
                Text(highlighted ? String(localized: "Let go to add") : String(localized: "Drop files and folders here"))
                    .contentTransition(.opacity)
            } icon: {
                Image(systemName: "archivebox")
            }
        } description: {
            Text("Or add them from anywhere on your Mac. Nothing is written until you pack, and the originals stay where they are.")
        } actions: {
            Button("Add Files…") { draft.chooseSources() }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(!canAdd)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: Radius.windowPanel, style: .continuous)
                .strokeBorder(contrastStyle.increased ? AnyShapeStyle(.secondary) : AnyShapeStyle(.separator),
                              style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
                .opacity(highlighted ? 0 : 1)
                .padding(.horizontal, Radius.windowInset)
                .padding(.top, FloatingGlass.topInset)
                .padding(.bottom, Radius.windowInset)
                .accessibilityHidden(true)
        }
    }

    /// The Browser's list, with its columns: Name, Size, Kind and Modified, read from the real files.
    /// Folders open in place, so a subtree can be checked or taken out without leaving the list.
    private var list: some View {
        ScrollViewReader { proxy in
            Table(tree, children: \.children, selection: $draft.selection) {
                TableColumn(String(localized: "Name")) { node in
                    DraftNameCell(node: node, hasArrived: arrived.contains(node.id), contrastStyle: contrastStyle)
                        .id(node.id)
                }
                .width(min: 130, ideal: 320)

                TableColumn(String(localized: "Size")) { node in
                    Text(node.bytes.bytes)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .width(min: 70, ideal: 84, max: 110)
                .alignment(.trailing)

                TableColumn(String(localized: "Kind")) { node in
                    Text(DraftFacts.of(node.file).kind)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .width(min: 64, ideal: 150, max: 220)

                TableColumn(String(localized: "Modified")) { node in
                    if let modified = DraftFacts.of(node.file).modified {
                        Text(modified, format: .dateTime.day().month(.abbreviated).year())
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .width(min: ContentList.modifiedWidth, ideal: max(110, ContentList.modifiedWidth), max: 140)
            }
            .alternatingRowBackgrounds(.disabled)
            .contextMenu(forSelectionType: String.self) { paths in
                if !paths.isEmpty {
                    Button {
                        draft.selection = paths
                        draft.removeSelection()
                    } label: {
                        Text(paths.count > 1 ? String(localized: "Remove \(paths.count) Items") : String(localized: "Remove"))
                        Text("The originals stay where they are")
                    }
                    .disabled(isBusy)
                    Divider()
                    Button("Show in Finder") {
                        let urls = draft.files.filter { paths.contains($0.path) }.compactMap(\.source)
                        NSWorkspace.shared.activateFileViewerSelecting(urls)
                    }
                }
            }
            .disabled(isBusy)
            .focused($listFocused)
            .onAppear { listFocused = true }
            // What an add brought in may be below the fold: bring the last of it into view.
            .onChange(of: arrived) { _, arrived in
                guard let last = tree.last(where: { arrived.contains($0.id) }) else { return }
                withAnimation(reduceMotion ? nil : Motion.current(Motion.status)) { proxy.scrollTo(last.id) }
            }
        }
    }

    /// The glass along the bottom, as in the Browser: adding more at the leading corner, where the
    /// Browser's Extract All is, and packing's progress at the trailing one, where its activity
    /// shows. While the draft is empty the centred Add Files… is the only one.
    private var floatingControls: some View {
        HStack(alignment: .bottom, spacing: Space.s) {
            if !isEmpty {
                Button {
                    draft.chooseSources()
                } label: {
                    Label("Add Files…", systemImage: "plus")
                }
                .buttonStyle(ActionButtonStyle())
                .disabled(!canAdd)
                .help(String(localized: "Add more files and folders. You can also drop them on the list."))
                .padding(ActionButtonStyle.inset)
                .accessibleGlass(in: .capsule)
                .fixedSize()
                .transition(.opacity)
            }
            Spacer(minLength: 0)
            ZStack {
                if draft.isSaving, app.packing.activity != nil {
                    PackActivityBar(packing: app.packing)
                        .transition(.rise(reduceMotion: reduceMotion))
                }
            }
        }
        .padding(.horizontal, FloatingGlass.edgeInset)
        .padding(.top, Space.s)
        .padding(.bottom, FloatingGlass.edgeInset)
    }

    /// New top-level rows, from an add or from Undo putting a removal back. The ring comes at once
    /// and fades after 1.2 s (DESIGN.md › Motion, as the Tray's rows do).
    private func noteArrivals(old: [PackFile], new: [PackFile]) {
        let before = Set(old.lazy.filter { !$0.path.contains("/") }.map(\.path))
        let added = Set(new.lazy.filter { !$0.path.contains("/") }.map(\.path)).subtracting(before)
        guard !added.isEmpty else { return }
        arrived = added
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard arrived == added else { return }
            withAnimation(Motion.resolved(Motion.status, reduceMotion: reduceMotion)) { arrived = [] }
        }
    }
}

/// The title bar's title for a draft, where the Browser names its archive: the name, which reads
/// as the title until it's clicked and then is a field; the format as the Pack sentence's token,
/// any format there and then, carried into Pack unchanged; and what's planned underneath, in the
/// Browser's subtitle place.
private struct DraftTitle: View {
    @Bindable var draft: ArchiveDraft
    let subtitle: String
    @Environment(\.reducesMotion) private var reduceMotion
    @FocusState private var nameFocused: Bool
    @State private var isHoveringName = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                nameField
                Token(title: "." + draft.format.fileExtension) {
                    ForEach(PackFormat.allCases) { format in
                        Button(format.displayName) { draft.format = format }
                    }
                }
                .accessibilityLabel(String(localized: "Archive Format"))
                .accessibilityValue(draft.format.displayName)
                .help(String(localized: "Choose the archive’s format. Pack starts with it."))
            }
            .font(.headline)
            HStack(spacing: Space.xs) {
                if draft.isImporting { ProgressView().controlSize(.mini) }
                Text(subtitle).liveNumber()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .animation(Motion.byKeyboard ? nil : Motion.resolved(Motion.token, reduceMotion: reduceMotion), value: draft.format)
    }

    /// As wide as the name (up to the Browser title's width), so the format follows straight after it.
    private var nameField: some View {
        let placeholder = String(localized: "Untitled Archive")
        return Text(verbatim: draft.name.isEmpty ? placeholder : draft.name)
            .lineLimit(1)
            .hidden()
            // Its ideal width is the name's, held between these; a longer name scrolls in the field.
            .frame(minWidth: 60, maxWidth: TitleBarLayout.titleMaximum - 80, alignment: .leading)
            .fixedSize(horizontal: true, vertical: false)
            .overlay {
                TextField("Archive Name", text: $draft.name, prompt: Text(placeholder))
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    // A title-bar field draws its text dimmed by default; this is the window's title.
                    .foregroundStyle(.primary)
                    .focused($nameFocused)
                    .onSubmit { nameFocused = false }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background {
                // Hover and editing show it's a field; at rest it's the window's title.
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(nameFocused ? AnyShapeStyle(.background) : AnyShapeStyle(.primary.opacity(isHoveringName ? 0.06 : 0)))
            }
            .focusRing(in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .onHover { isHoveringName = $0 }
            .padding(.leading, -4)
            .help(String(localized: "Rename the archive"))
    }
}

/// A planned item's name: the real file's Finder icon, its name, and a link's arrow.
private struct DraftNameCell: View {
    let node: DraftNode
    let hasArrived: Bool
    let contrastStyle: ContrastStyle

    var body: some View {
        HStack(spacing: Space.s) {
            DraftIcon(file: node.file)
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
            Text(verbatim: node.name)
                .lineLimit(1)
                .truncationMode(.middle)
            if node.file.isLink {
                Image(systemName: "arrow.turn.up.right")
                    .font(.caption)
                    .foregroundStyle(contrastStyle.metadata)
                    .help(String(localized: "Symbolic link"))
                    .accessibilityLabel(String(localized: "Symbolic link"))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 3)
        .background(hasArrived ? AnyShapeStyle(.tint.opacity(0.08)) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 5))
        .overlay {
            // A ring rather than a fill, so it never reads as the selection.
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(.tint, lineWidth: 1.5)
                .opacity(hasArrived ? 1 : 0)
                .allowsHitTesting(false)
        }
        .padding(.horizontal, -3)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// The file's own Finder icon, read once per path.
struct DraftIcon: View {
    let file: PackFile
    @MainActor private static var cache: [String: NSImage] = [:]

    var body: some View {
        if let url = file.source {
            Image(nsImage: Self.icon(for: url))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            NativeIcon(type: file.isFolder ? .folder : .data)
        }
    }

    private static func icon(for url: URL) -> NSImage {
        if let hit = cache[url.path] { return hit }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache[url.path] = icon
        return icon
    }
}

/// What Finder says about a planned item's original: its kind and when it last changed. Read once
/// per path, when a row or Details first shows it.
enum DraftFacts {
    struct Facts {
        var kind: String
        var modified: Date?
    }
    @MainActor private static var cache: [String: Facts] = [:]

    @MainActor static func of(_ file: PackFile) -> Facts {
        guard let url = file.source else {
            return Facts(kind: file.isFolder ? String(localized: "Folder") : "")
        }
        if let hit = cache[url.path] { return hit }
        let values = try? url.resourceValues(forKeys: [.localizedTypeDescriptionKey, .contentModificationDateKey])
        let facts = Facts(kind: values?.localizedTypeDescription ?? (file.isFolder ? String(localized: "Folder") : ""),
                          modified: values?.contentModificationDate)
        cache[url.path] = facts
        return facts
    }
}

/// "4 items · 12.4 MB before compression": what a draft plans to pack, never what it will weigh.
enum DraftSummary {
    static func text(items: Int, bytes: Int64) -> String {
        String(localized: "\(items) items") + " · " + String(localized: "\(bytes.bytes) before compression")
    }
}

/// An item in the draft's planned contents, with what's inside it.
struct DraftNode: Identifiable {
    let file: PackFile
    var children: [DraftNode]?
    /// Everything inside a folder, at any depth.
    var count = 0
    /// The originals' size before compression: a file's own, or everything inside a folder.
    var bytes: Int64 = 0
    var id: String { file.path }
    var name: String { file.path.split(separator: "/").last.map(String.init) ?? file.path }

    /// Folders come before what's in them (the draft lists them that way); top-level items keep
    /// the order they were added in, and the inside of a folder sorts as Finder does by name.
    static func tree(from files: [PackFile]) -> [DraftNode] {
        final class Builder {
            let file: PackFile
            var children: [Builder] = []
            init(_ file: PackFile) { self.file = file }
            func node() -> DraftNode {
                guard file.isFolder else { return DraftNode(file: file, bytes: file.size) }
                let nodes = children.map { $0.node() }
                    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                return DraftNode(file: file, children: nodes.isEmpty ? nil : nodes,
                                 count: nodes.reduce(nodes.count) { $0 + $1.count },
                                 bytes: nodes.reduce(Int64(0)) { $0 + $1.bytes })
            }
        }
        var byPath: [String: Builder] = [:]
        var roots: [Builder] = []
        for file in files {
            let builder = Builder(file)
            byPath[file.path] = builder
            if let slash = file.path.lastIndex(of: "/"), let parent = byPath[String(file.path[..<slash])] {
                parent.children.append(builder)
            } else {
                roots.append(builder)
            }
        }
        return roots.map { $0.node() }
    }
}

extension PackFormat {
    /// The type Finder draws this format's documents with (the last part of a double extension).
    var contentType: UTType {
        let last = fileExtension.split(separator: ".").last.map(String.init) ?? fileExtension
        return UTType(filenameExtension: last) ?? .archive
    }
}

final class CreationWindowDelegate: NSObject, NSWindowDelegate {
    weak var draft: ArchiveDraft?
    private weak var window: NSWindow?
    private var original: (any NSWindowDelegate)?
    private var didClose: () -> Void = {}

    func attach(_ window: NSWindow, draft: ArchiveDraft, didClose: @escaping () -> Void) {
        self.draft = draft
        self.didClose = didClose
        window.isDocumentEdited = draft.isEdited
        if let previous = self.window, previous !== window, previous.delegate === self {
            previous.delegate = original
        }
        self.window = window
        if window.delegate !== self {
            original = (window.delegate as? CreationWindowDelegate)?.original ?? window.delegate
            window.delegate = self
        }
    }

    isolated deinit {
        if let window, window.delegate === self { window.delegate = original }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let draft else { return true }
        guard !draft.isSaving, sender.attachedSheet == nil else { return false }
        return draft.allowDiscardOrSave()
    }

    func windowWillClose(_ notification: Notification) {
        draft?.close()
        didClose()
        original?.windowWillClose?(notification)
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { draft?.undoManager }

    nonisolated override func responds(to selector: Selector!) -> Bool {
        if super.responds(to: selector) { return true }
        return MainActor.assumeIsolated { original?.responds(to: selector) == true }
    }
    private nonisolated struct DelegateBox: @unchecked Sendable { let delegate: (any NSWindowDelegate)? }
    nonisolated override func forwardingTarget(for selector: Selector!) -> Any? {
        MainActor.assumeIsolated { DelegateBox(delegate: original) }.delegate
    }
}
