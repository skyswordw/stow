import AppKit
import SwiftUI

/// A native field so the initial selection excludes the extension, just like Finder.
struct EditingName: View {
    @Bindable var model: BrowserModel
    let entry: ArchiveEntry

    var body: some View {
        HStack(spacing: 4) {
            if model.renamingPath == entry.path {
                RenameField(text: $model.renameText, commit: { model.commitRename() }, cancel: { model.renamingPath = nil })
                    .frame(height: 22)
            } else {
                Text(entry.name).lineLimit(1).truncationMode(.middle)
            }
            if let state = model.editSession.state(for: entry.path) {
                Text(state).font(.caption).fixedSize().foregroundStyle(state == String(localized: "New") ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
        }
        .help(model.editSession.refusal(for: [entry.path]) ?? entry.name)
    }
}

private struct RenameField: NSViewRepresentable {
    @Binding var text: String
    let commit: () -> Void
    let cancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.delegate = context.coordinator
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.focusRingType = .default
        DispatchQueue.main.async { [weak field] in
            guard let field, let window = field.window else { return }
            window.makeFirstResponder(field)
            let stem = (field.stringValue as NSString).deletingPathExtension
            field.currentEditor()?.selectedRange = NSRange(location: 0, length: (stem as NSString).length)
        }
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) { context.coordinator.parent = self }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: RenameField
        init(_ parent: RenameField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSTextField { parent.text = field.stringValue }
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)) { parent.commit(); return true }
            if selector == #selector(NSResponder.cancelOperation(_:)) { parent.cancel(); return true }
            return false
        }
    }
}

struct UnsavedChangesBar: View {
    let model: BrowserModel
    var body: some View {
        HStack {
            if model.editSession.isSaving { ProgressView(value: model.editSession.progress).frame(width: 80) }
            Text(model.editSession.summary).font(.callout).monospacedDigit()
            Spacer()
            Button("Revert") { model.revertEdits() }
            Button("Save") { Task { await model.saveEdits() } }.buttonStyle(.borderedProminent)
        }
        .disabled(model.editSession.isSaving)
        .padding(.horizontal, Space.m).padding(.vertical, Space.s)
        .background(.bar)
    }
}


struct ExternalChangeBar: View {
    let model: BrowserModel
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(EditSession.changedOnDiskSummary)
                .font(.callout)
            Spacer()
            Button("Reload") { Task { await model.reloadArchive() } }
            Button("Save a Copy…") { Task { await model.saveCopyOfArchive() } }
                .buttonStyle(.borderedProminent)
        }
        .disabled(model.editSession.isSaving)
        .padding(.horizontal, Space.m).padding(.vertical, Space.s)
        .background(.bar)
    }
}

private struct ArchiveDrop: ViewModifier {
    let model: BrowserModel
    let folder: String
    @State private var targeted = false
    func body(content: Content) -> some View {
        content
            .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
                guard model.editSession.requireEditable() else { return true }
                // Preserve provider order and register the whole gesture as one undo action.
                Task { @MainActor in
                    var urls: [URL] = []
                    for provider in providers {
                        let url: URL? = await withCheckedContinuation { continuation in
                            provider.loadDataRepresentation(forTypeIdentifier: "public.file-url") { data, _ in
                                continuation.resume(returning: data.flatMap { URL(dataRepresentation: $0, relativeTo: nil) })
                            }
                        }
                        if let url { urls.append(url) }
                    }
                    model.editSession.add(urls, into: folder)
                }
                return true
            }
            .overlay { if targeted { RoundedRectangle(cornerRadius: 8).stroke(.tint, lineWidth: 2).allowsHitTesting(false) } }
    }
}

extension View {
    func archiveDrop(model: BrowserModel, folder: String) -> some View { modifier(ArchiveDrop(model: model, folder: folder)) }
}

/// Retained by the view, forwarding SwiftUI's window delegate methods to its original delegate.
final class EditingWindowDelegate: NSObject, NSWindowDelegate {
    // Strong: NSWindow.delegate is weak, so once we take its place nothing else may keep SwiftUI's delegate alive.
    var original: (any NSWindowDelegate)?
    weak var model: BrowserModel?
    private weak var window: NSWindow?
    private let undo = EditingUndoManager()
    private var approving = false
    private var asking = false

    isolated deinit {
        if let window, window.delegate === self { window.delegate = original }
    }

    func attach(_ window: NSWindow, model: BrowserModel) {
        if self.model !== model { undo.removeAllActions() }
        self.window = window
        self.model = model
        undo.isLocked = { [weak model] in model?.levels.contains(where: { $0.edits.isSaving }) == true }
        model.editingWindow = window
        for level in model.levels { level.edits.undoManager = undo }
        window.isDocumentEdited = model.levels.contains { $0.edits.isEdited }
        if window.delegate !== self { original = window.delegate; window.delegate = self }
    }
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { undo }

    nonisolated override func responds(to selector: Selector!) -> Bool {
        if super.responds(to: selector) { return true }
        return MainActor.assumeIsolated { original?.responds(to: selector) == true }
    }
    private nonisolated struct DelegateBox: @unchecked Sendable {
        let delegate: (any NSWindowDelegate)?
    }
    nonisolated override func forwardingTarget(for selector: Selector!) -> Any? {
        // Like the preview panel's ItemBox: Objective-C dispatch is on the main thread, but the
        // override itself is nonisolated and its return type does not carry actor information.
        MainActor.assumeIsolated { DelegateBox(delegate: original) }.delegate
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if approving || model?.levels.contains(where: { $0.edits.isEdited }) != true { return original?.windowShouldClose?(sender) ?? true }
        guard !asking else { return false }
        asking = true
        Task { [weak self] in
            guard let self else { return }
            defer { asking = false }
            if await model?.confirmDiscardingEdits() == true {
                approving = true
                sender.performClose(nil)
                approving = false
            }
        }
        return false
    }
}

/// Save suspends across XPC calls. Keep the system Edit menu from undoing the plan in flight.
private final class EditingUndoManager: UndoManager {
    var isLocked: () -> Bool = { false }
    nonisolated override var canUndo: Bool {
        let allowed = MainActor.assumeIsolated { !isLocked() }
        return allowed && super.canUndo
    }
    nonisolated override var canRedo: Bool {
        let allowed = MainActor.assumeIsolated { !isLocked() }
        return allowed && super.canRedo
    }
    nonisolated override func undo() {
        guard MainActor.assumeIsolated({ !isLocked() }) else { return }
        super.undo()
    }
    nonisolated override func redo() {
        guard MainActor.assumeIsolated({ !isLocked() }) else { return }
        super.redo()
    }
}
