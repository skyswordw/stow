import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A new archive that isn't written yet (#293): its name and format as the window's heading, what
/// will go in it as a list of the real files, and Save, which asks how to pack it. Nothing on disk
/// changes until the pack succeeds; the originals never do. DESIGN.md › New archive draft.
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
    @FocusState private var nameFocused: Bool

    private var contrastStyle: ContrastStyle { .resolve(contrast) }
    private var highlighted: Bool { isTargeted || isPromiseTargeted }
    private var isEmpty: Bool { draft.files.isEmpty }
    private var isBusy: Bool { draft.isImporting || draft.isSaving }
    private var canAdd: Bool { !draft.isImporting && !draft.isChoosingSources && !draft.isSaving }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            header
            if let problem = draft.problem {
                problemCard(problem)
                    .transition(.opacity.animation(Motion.byKeyboard ? nil : Motion.resolved(Motion.status, reduceMotion: reduceMotion)))
            }
            card
        }
        .padding(.horizontal, Space.xl)
        .padding(.top, Space.s)
        .padding(.bottom, Space.xl)
        .frame(minWidth: 560, minHeight: 420)
        // Packing floats over the list, as it does over the Browser's files.
        .overlay(alignment: .bottom) {
            if draft.isSaving, app.packing.activity != nil {
                PackActivityBar(packing: app.packing)
                    .padding(.bottom, Space.xl + Space.s)
                    .transition(.rise(reduceMotion: reduceMotion))
            }
        }
        .animation(Motion.byKeyboard ? nil : Motion.resolved(Motion.status, reduceMotion: reduceMotion), value: isEmpty)
        .animation(Motion.presence(draft.isSaving, reduceMotion: reduceMotion), value: draft.isSaving)
        // A quiet title bar, as on the welcome window: the heading below is the title.
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        // Drags that only promise a file (Mail, Photos, chat apps) land anywhere in the window.
        .onDrop(of: OtherAppFiles.promisedTypes, isTargeted: $isPromiseTargeted) { providers in
            guard canAdd else { return false }
            draft.receivePromises(providers)
            return true
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

    // MARK: Heading

    /// The archive's own name and format, as it will be called, with Save at the trailing edge
    /// where the Browser keeps it. A line under the name says it isn't saved and what is planned.
    private var header: some View {
        HStack(alignment: .center, spacing: Space.m) {
            NativeIcon(type: draft.format.contentType)
                .frame(width: 44, height: 44)
                .id(draft.format)
                .transition(.opacity)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                    nameField
                    formatToken
                }
                .font(.title2)
                status
            }
            Spacer(minLength: Space.l)
            saveButton
        }
        .animation(Motion.byKeyboard ? nil : Motion.resolved(Motion.token, reduceMotion: reduceMotion), value: draft.format)
        .disabled(draft.isSaving)
    }

    /// Reads as the title until it's clicked; then it's a field. As wide as the name, so the format
    /// follows straight after it.
    private var nameField: some View {
        let placeholder = String(localized: "Untitled Archive")
        return Text(verbatim: draft.name.isEmpty ? placeholder : draft.name)
            .fontWeight(.semibold)
            .lineLimit(1)
            .hidden()
            .frame(minWidth: 80, alignment: .leading)
            .overlay {
                TextField("Archive Name", text: $draft.name, prompt: Text(placeholder))
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .fontWeight(.semibold)
                    .focused($nameFocused)
                    .onSubmit { nameFocused = false }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background {
                // Hover and editing show it's a field; at rest it's the window's title.
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(nameFocused ? AnyShapeStyle(.background) : AnyShapeStyle(.primary.opacity(isHoveringName ? 0.05 : 0)))
            }
            .focusRing(in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .onHover { isHoveringName = $0 }
            .padding(.leading, -5)
            .help(String(localized: "Rename the archive"))
    }

    @State private var isHoveringName = false

    /// The extension as a sentence token: amber, with the pull-down chevron. Any format can be
    /// chosen here; Save fits the purpose to it.
    private var formatToken: some View {
        Token(title: "." + draft.format.fileExtension) {
            Picker("Archive Format", selection: $draft.format) {
                ForEach(PackFormat.allCases) { format in
                    Text(format.displayName).tag(format)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
        .accessibilityLabel(String(localized: "Archive Format"))
        .accessibilityValue(draft.format.displayName)
    }

    /// Never a final size: these are the originals, before compression. The archive's own size is
    /// known only once it's packed.
    private var status: some View {
        HStack(spacing: Space.xs) {
            if draft.isImporting {
                ProgressView().controlSize(.mini)
                Text("Adding files…")
            } else {
                Text(statusText)
                    .liveNumber()
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private var statusText: String {
        let unsaved = String(localized: "Not saved yet")
        guard !isEmpty else { return unsaved }
        let bytes = draft.files.reduce(Int64(0)) { $0 + ($1.isFolder ? 0 : $1.size) }
        return unsaved + " · " + DraftSummary.text(items: tree.count, bytes: bytes)
    }

    /// Prominent once there's something to save; until then Add Files is the next step and Save
    /// steps back.
    @ViewBuilder private var saveButton: some View {
        let disabled = !draft.canSave || app.packing.isRunning
        if isEmpty {
            Button("Save…") { draft.prepareSave() }
                .buttonStyle(.glass)
                .controlSize(.large)
                .disabled(true)
                .help(String(localized: "Add files to save this archive"))
        } else {
            Button("Save…") { draft.prepareSave() }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(disabled)
                .help(String(localized: "Choose how to pack it and where to save it"))
        }
    }

    // MARK: Problem

    private func problemCard(_ problem: String) -> some View {
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
    }

    // MARK: Contents

    /// The window's drop target, as the Tray's card is: a dashed edge while empty, the accent and a
    /// light tint while something is held over it.
    private var card: some View {
        VStack(spacing: 0) {
            if isEmpty {
                empty.transition(.opacity)
            } else {
                list.transition(.opacity)
                Divider()
                listBar
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .overlay {
            if highlighted { Rectangle().fill(.tint.opacity(0.08)).allowsHitTesting(false) }
        }
        .clipShape(.rect(cornerRadius: Radius.panel))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.panel)
                .strokeBorder(highlighted ? AnyShapeStyle(.tint)
                                : contrastStyle.increased ? AnyShapeStyle(.secondary) : AnyShapeStyle(.separator),
                              style: StrokeStyle(lineWidth: highlighted ? 2 : (isEmpty ? 1.5 : 1),
                                                 dash: isEmpty && !highlighted ? [7, 6] : []))
        }
        .scaleEffect(highlighted && !reduceMotion ? 1.015 : 1)
        .animation(Motion.resolved(Motion.target, reduceMotion: reduceMotion), value: highlighted)
        .dropDestination(for: URL.self) { urls, _ in
            guard canAdd else { return false }
            Task { await draft.add(urls) }
            return true
        } isTargeted: { isTargeted = $0 }
    }

    private var empty: some View {
        VStack(spacing: Space.m) {
            Image(systemName: "archivebox")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(spacing: Space.xs) {
                Text(highlighted ? String(localized: "Let go to add") : String(localized: "Drop files and folders here"))
                    .font(.title3.weight(.semibold))
                    .contentTransition(.opacity)
                Text("Or add them from anywhere on your Mac. Nothing is written until you save, and the originals stay where they are.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 380)
            Button("Add Files…") { draft.chooseSources() }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(!canAdd)
                .padding(.top, Space.xs)
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            List(tree, children: \.children, selection: $draft.selection) { node in
                DraftRow(node: node, hasArrived: arrived.contains(node.id), contrastStyle: contrastStyle)
                    .id(node.id)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
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
            // What an add brought in may be below the fold: bring the last of it into view.
            .onChange(of: arrived) { _, arrived in
                guard let last = tree.last(where: { arrived.contains($0.id) }) else { return }
                withAnimation(reduceMotion ? nil : Motion.current(Motion.status)) { proxy.scrollTo(last.id) }
            }
        }
    }

    /// Changing the list, attached to it: add more, take the selection out. The keys are in the
    /// Edit menu (⇧⌘A, ⌘⌫), and Undo puts anything removed back.
    private var listBar: some View {
        HStack(spacing: Space.m) {
            Button("Add Files…", systemImage: "plus") { draft.chooseSources() }
                .disabled(!canAdd)
                .help(String(localized: "Add more files and folders"))
            Button(draft.selection.count > 1 ? String(localized: "Remove \(draft.selection.count) Items") : String(localized: "Remove"),
                   systemImage: "minus") { draft.removeSelection() }
                .disabled(draft.selection.isEmpty || isBusy)
                .help(String(localized: "Take the selection out of this archive. The originals stay where they are."))
            Spacer()
            Text("Drop more to add them")
                .font(.callout)
                .foregroundStyle(contrastStyle.metadata)
                .lineLimit(1)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
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

/// One planned item: the real file's Finder icon, its name, and what it holds or weighs.
private struct DraftRow: View {
    let node: DraftNode
    let hasArrived: Bool
    let contrastStyle: ContrastStyle

    var body: some View {
        HStack(spacing: Space.s) {
            DraftIcon(file: node.file)
                .frame(width: 20, height: 20)
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
            Spacer(minLength: Space.s)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, Space.xs)
        .background(hasArrived ? AnyShapeStyle(.tint.opacity(0.08)) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 6))
        .overlay {
            // A ring rather than a fill, so it never reads as the selection.
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(.tint, lineWidth: 1.5)
                .opacity(hasArrived ? 1 : 0)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        if node.file.isFolder {
            return String(localized: "\(node.count) items")
        }
        return node.file.size.bytes
    }
}

/// The file's own Finder icon, read once per path.
private struct DraftIcon: View {
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
                guard file.isFolder else { return DraftNode(file: file) }
                let nodes = children.map { $0.node() }
                    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                return DraftNode(file: file, children: nodes.isEmpty ? nil : nodes,
                                 count: nodes.reduce(nodes.count) { $0 + $1.count })
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
