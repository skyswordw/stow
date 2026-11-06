import AppKit
import SwiftUI

/// Functional draft surface. Claude Code owns the final workspace and configuration design (#293).
struct ArchiveDraftView: View {
    @Bindable var draft: ArchiveDraft
    @Environment(AppState.self) private var app
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var delegate = CreationWindowDelegate()

    var body: some View {
        VStack {
            HStack {
                TextField("Archive Name", text: $draft.name)
                Picker("Archive Format", selection: $draft.format) {
                    ForEach(PackFormat.allCases) { Text($0.displayName).tag($0) }
                }
                Text("Unsaved archive")
            }
            .disabled(draft.isSaving)
            if draft.files.isEmpty {
                Text("Add files or folders to create an archive.")
            }
            List(selection: $draft.selection) {
                ForEach(draft.files, id: \.path) { file in
                    HStack {
                        Text(verbatim: file.path)
                        Spacer()
                        if !file.isFolder { Text(file.size.bytes) }
                    }.tag(file.path)
                }
            }
            .disabled(draft.isImporting || draft.isSaving)
            .dropDestination(for: URL.self) { urls, _ in
                guard !draft.isImporting, !draft.isChoosingSources, !draft.isSaving else { return false }
                Task { await draft.add(urls) }
                return true
            }
            if draft.isImporting { ProgressView("Adding files…") }
            if let problem = draft.problem { Text(verbatim: problem).textSelection(.enabled) }
            if draft.isSaving, let activity = app.packing.activity {
                PackActivityBar(packing: app.packing).id(activity.name)
            }
            HStack {
                Button("Add Files…") { draft.chooseSources() }
                    .disabled(draft.isImporting || draft.isChoosingSources || draft.isSaving)
                Button("Remove") { draft.removeSelection() }
                    .disabled(draft.selection.isEmpty || draft.isImporting || draft.isSaving)
                Spacer()
                Button("Save…") { draft.prepareSave() }
                    .disabled(!draft.canSave || app.packing.isRunning)
            }
        }
        .onDrop(of: OtherAppFiles.promisedTypes, isTargeted: nil) { providers in
            guard !draft.isImporting, !draft.isChoosingSources, !draft.isSaving else { return false }
            draft.receivePromises(providers)
            return true
        }
        .padding()
        .frame(minWidth: 600, minHeight: 400)
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
