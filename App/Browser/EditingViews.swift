import AppKit
import SwiftUI

/// A native field so the initial selection excludes the extension, just like Finder. Staged
/// entries carry a quiet tag ("New" in the accent, "Renamed", "Replaced"); the grid shows it on
/// the size line instead (`showsState: false`), so it doesn't take the name's room.
struct EditingName: View {
    @Bindable var model: BrowserModel
    let entry: ArchiveEntry
    var showsState = true

    var body: some View {
        HStack(spacing: Space.xs) {
            if model.renamingPath == entry.path {
                RenameField(text: $model.renameText, commit: { model.commitRename() }, cancel: { model.renamingPath = nil })
                    .frame(height: 22)
            } else {
                Text(entry.name).truncationMode(.middle)
            }
            if showsState, let state = model.editSession.state(for: entry.path) {
                EditingTag(state: state)
            }
        }
        .help(model.editSession.refusal(for: [entry.path]) ?? entry.name)
    }
}

/// "New" in the accent (something you added); "Renamed" and "Replaced" stay secondary.
struct EditingTag: View {
    let state: String

    var body: some View {
        Text(state)
            .font(.caption)
            .fixedSize()
            .foregroundStyle(Self.style(for: state))
    }

    static func style(for state: String) -> AnyShapeStyle {
        state == String(localized: "New") ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary)
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
        field.setAccessibilityLabel(String(localized: "Rename"))
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

/// The bars that sit over the path bar while an archive has staged edits. A plain solid bar,
/// like the legacy-names banner: it's part of the window, not a floating control.
enum EditingBar {
    static let height: CGFloat = 44
}

/// "3 unsaved changes" with Revert and Save, the one prominent button. While saving, the bar
/// shows the shared activity label instead, and nothing else can be pressed.
struct UnsavedChangesBar: View {
    let model: BrowserModel

    var body: some View {
        let edits = model.editSession
        HStack(spacing: Space.s) {
            if edits.isSaving {
                // The shared label sizes to its words; a narrow window gets the short ones.
                ViewThatFits(in: .horizontal) {
                    ActivityLabel(phase: .running(edits.progress), title: String(localized: "Saving “\(edits.name)”"))
                    ActivityLabel(phase: .running(edits.progress), title: String(localized: "Saving…"))
                }
                Spacer(minLength: 0)
            } else {
                // Longest first; the icon goes before the words are cut.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Space.s) {
                        icon
                        Text(edits.summary).fontWeight(.medium)
                        Text("Nothing changes on disk until you save.").foregroundStyle(.secondary)
                    }
                    .fixedSize()
                    HStack(spacing: Space.s) {
                        icon
                        Text(edits.summary).fontWeight(.medium)
                    }
                    .fixedSize()
                    Text(edits.summary).fontWeight(.medium).fixedSize()
                    Text(edits.summary).fixedSize()
                    Text(edits.summary).truncationMode(.tail)
                }
                .help(edits.summary + " " + String(localized: "Nothing changes on disk until you save."))
                Spacer(minLength: 0)
                Group {
                    Button("Revert") { model.revertEdits() }
                        .help("Drop every unsaved change")
                    Button("Save") { Task { await model.saveEdits() } }
                        .buttonStyle(.borderedProminent)
                        .help("Write the changes into “\(edits.name)”")
                }
                .fixedSize()
            }
        }
        .font(.callout)
        .lineLimit(1)
        .padding(.horizontal, Space.m)
        .frame(height: EditingBar.height)
        .frame(minWidth: 0, maxWidth: .infinity)
        .accessibleBar()
        .overlay(alignment: .top) { Divider() }
    }

    private var icon: some View {
        Image(systemName: "pencil.circle.fill")
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }
}

/// The file changed under Stow while edits were staged. Saving a copy keeps the edits and leaves
/// the changed original alone, so it's the prominent choice; Reload drops the edits.
struct ExternalChangeBar: View {
    let model: BrowserModel

    var body: some View {
        HStack(spacing: Space.s) {
            Image(systemName: CheckupFinding.Severity.caution.symbol)
                .foregroundStyle(CheckupFinding.Severity.caution.color)
                .accessibilityHidden(true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.s) {
                    Text("“\(model.editSession.name)” changed on disk.").fontWeight(.medium)
                    Text("Save a copy to keep your changes.").foregroundStyle(.secondary)
                }
                .fixedSize()
                Text("“\(model.editSession.name)” changed on disk.").fontWeight(.medium).fixedSize()
                Text("Changed on disk").fontWeight(.medium).fixedSize()
                Text("Changed on disk").fixedSize()
                Text("Changed on disk").truncationMode(.tail)
            }
            .help(String(localized: "“\(model.editSession.name)” changed on disk.") + " " + String(localized: "Save a copy to keep your changes."))
            Spacer(minLength: 0)
            Group {
                Button("Reload") { Task { await model.reloadArchive() } }
                    .help("Show the archive as it is on disk now — your unsaved changes are dropped")
                Button("Save a Copy…") { Task { await model.saveCopyOfArchive() } }
                    .buttonStyle(.borderedProminent)
                    .help("Save the archive with your changes as a new file")
            }
            .fixedSize()
        }
        .font(.callout)
        .lineLimit(1)
        .disabled(model.editSession.isSaving)
        .padding(.horizontal, Space.m)
        .frame(height: EditingBar.height)
        .frame(minWidth: 0, maxWidth: .infinity)
        .accessibleBar()
        .overlay(alignment: .top) { Divider() }
    }
}

/// What editing stops to tell: an edit Stow can't make, or that this archive can't be changed.
/// Shown with the shared prompt card, like every other question.
enum EditingNotice: Identifiable {
    case refused(String)
    case readOnly(reason: String)

    var id: String {
        switch self {
        case .refused(let message): "refused-" + message
        case .readOnly(let reason): "readOnly-" + reason
        }
    }

    var prompt: Prompt {
        switch self {
        case .refused(let message):
            Prompt(symbol: CheckupFinding.Severity.caution.symbol, tint: CheckupFinding.Severity.caution.color,
                   title: message, message: "",
                   choices: [Prompt.Choice(title: String(localized: "OK"), role: .primary)])
        case .readOnly(let reason):
            Prompt(symbol: "lock.fill", tint: .secondary, title: reason,
                   message: String(localized: "Extract and Repack makes a new ZIP or 7Z with the same files, which you can change. This archive stays as it is."),
                   choices: [Prompt.Choice(title: String(localized: "OK"), role: .cancel),
                             Prompt.Choice(title: String(localized: "Extract and Repack…"), role: .primary)])
        }
    }

    /// The next step the answer asks for: only Extract and Repack has one.
    func wantsRepack(_ answer: Prompt.Answer) -> Bool {
        if case .readOnly = self { answer.choice == 1 } else { false }
    }
}

extension Prompt {
    /// File › Rename Archive…: the name field, Cancel (Escape) and Rename (Return).
    static func renameArchive(_ name: String) -> Prompt {
        Prompt(symbol: "pencil", title: String(localized: "Rename Archive"),
               message: String(localized: "Choose a new name for “\(name)”. The browsing position is kept."),
               choices: [Choice(title: String(localized: "Cancel"), role: .cancel),
                         Choice(title: String(localized: "Rename"), role: .primary)],
               field: Field(text: name, label: String(localized: "Name")))
    }

    /// Closing or quitting with staged edits: Don’t Save (⌘D), Cancel (Escape), Save (Return).
    static func saveChanges(_ name: String) -> Prompt {
        Prompt(symbol: "square.and.arrow.down", title: String(localized: "Save changes to “\(name)”?"),
               message: String(localized: "Your changes will be lost if you don’t save them."),
               choices: [Choice(title: String(localized: "Don’t Save"), shortcut: KeyboardShortcut("d", modifiers: .command)),
                         Choice(title: String(localized: "Cancel"), role: .cancel),
                         Choice(title: String(localized: "Save"), role: .primary)])
    }

    /// Indexes into `saveChanges`' choices.
    enum SaveChoice { static let discard = 0, cancel = 1, save = 2 }
}

extension EditSession {
    /// The notice to show now, if any; setting nil clears it.
    var notice: EditingNotice? {
        get {
            if showsReadOnly { return .readOnly(reason: readOnlyReason) }
            return message.map(EditingNotice.refused)
        }
        set {
            guard newValue == nil else { return }
            showsReadOnly = false
            message = nil
        }
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
    /// Only the active archive presentation owns editing notices. A retained hidden full
    /// window must neither present nor clear a compact window's validation or save failure.
    func editingNotice(_ model: BrowserModel, isActive: Bool, repack: @escaping () -> Void) -> some View {
        sheet(item: Binding(
            get: { isActive ? model.editSession.notice : nil },
            set: { if isActive { model.editSession.notice = $0 } }
        )) { notice in
            PromptView(prompt: notice.prompt) { answer in
                model.editSession.notice = nil
                if notice.wantsRepack(answer) { repack() }
            }
        }
    }

    func archiveDrop(model: BrowserModel, folder: String) -> some View { modifier(ArchiveDrop(model: model, folder: folder)) }
}

/// Retained by the view, forwarding SwiftUI's window delegate methods to its original delegate.
final class EditingWindowDelegate: NSObject, NSWindowDelegate {
    // Strong: NSWindow.delegate is weak, so once we take its place nothing else may keep SwiftUI's delegate alive.
    var original: (any NSWindowDelegate)?
    weak var model: BrowserModel?
    private weak var window: NSWindow?
    private var approving = false
    private var asking = false

    isolated deinit {
        if let window, window.delegate === self { window.delegate = original }
    }

    func attach(_ window: NSWindow, model: BrowserModel) {
        if self.model !== model, self.model?.editingWindow === window {
            self.model?.editingWindow = nil
        }
        if let previous = self.window, previous !== window, previous.delegate === self {
            previous.delegate = original
        }
        self.window = window
        self.model = model
        // A hidden full/Glance view can rebuild after another archive opens. It must not
        // take editing ownership from the model's current key window.
        if window.isKeyWindow || model.editingWindow?.isKeyWindow != true {
            model.editingWindow = window
        }
        for level in model.levels { level.edits.undoManager = model.editingUndoManager }
        window.isDocumentEdited = model.levels.contains { $0.edits.isEdited }
        if window.delegate !== self { original = window.delegate; window.delegate = self }
        EditingUndoCommandsModel.shared.refresh()
    }
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { model?.editingUndoManager }

    func windowDidBecomeKey(_ notification: Notification) {
        // Full and Glance retain separate delegates and hosted views. Reopening either window
        // does not move WindowReader into it again, so reclaim editing ownership on activation.
        if let window = notification.object as? NSWindow, window === self.window, let model {
            attach(window, model: model)
        }
        original?.windowDidBecomeKey?(notification)
    }

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
final class EditingUndoManager: UndoManager {
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
