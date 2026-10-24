import AppKit
import SwiftUI

/// SwiftUI's hosting window supplies its own undo manager, even when its delegate supplies
/// another one. Route archive commands explicitly; editable text keeps AppKit's responder action.
struct EditingUndoCommands: Commands {
    private let routing = EditingUndoCommandsModel.shared

    var body: some Commands {
        // AppKit managers and first responders are not observable. Native notifications refresh
        // this snapshot; the live lookup also observes the model's save lock and window ownership.
        let _ = routing.snapshot
        let manager = routing.manager(in: NSApp.keyWindow)
        CommandGroup(replacing: .undoRedo) {
            Button(manager?.undoMenuItemTitle ?? String(localized: "Undo")) { routing.perform(.undo) }
                .keyboardShortcut("z")
                .disabled(manager?.canUndo != true)
            Button(manager?.redoMenuItemTitle ?? String(localized: "Redo")) { routing.perform(.redo) }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(manager?.canRedo != true)
        }
    }
}

@Observable
final class EditingUndoCommandsModel {
    static let shared = EditingUndoCommandsModel()

    enum Action {
        case undo, redo
        var selector: Selector { NSSelectorFromString(self == .undo ? "undo:" : "redo:") }
    }

    struct Snapshot: Equatable {
        var manager: ObjectIdentifier?
        var canUndo = false
        var canRedo = false
        var undoTitle = ""
        var redoTitle = ""
    }

    private(set) var snapshot = Snapshot()
    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        for name in [
            Notification.Name.NSUndoManagerCheckpoint,
            .NSUndoManagerDidCloseUndoGroup, .NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange,
            NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification, NSWindow.didUpdateNotification
        ] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
    }

    isolated deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    func archiveManager(in window: NSWindow?) -> UndoManager? {
        guard let window, window.attachedSheet == nil, NSApp.modalWindow == nil,
              let delegate = window.delegate as? EditingWindowDelegate,
              let model = delegate.model, model.editingWindow === window else { return nil }
        // Field editors own typing undo, even when empty. Never fall back to archive history
        // just because the user has exhausted the text field's own undo stack.
        if let text = window.firstResponder as? NSTextView, text.isEditable { return nil }
        return model.editingUndoManager
    }

    func manager(in window: NSWindow?) -> UndoManager? {
        if let manager = archiveManager(in: window) { return manager }
        let native = NSApp.modalWindow ?? window?.attachedSheet ?? window
        return native?.firstResponder?.undoManager ?? native?.undoManager
    }

    func refresh() {
        let manager = manager(in: NSApp.keyWindow)
        let next = Snapshot(manager: manager.map(ObjectIdentifier.init),
                            canUndo: manager?.canUndo == true, canRedo: manager?.canRedo == true,
                            undoTitle: manager?.undoMenuItemTitle ?? "", redoTitle: manager?.redoMenuItemTitle ?? "")
        // Window updates can follow menu updates. Publish only changes, avoiding a refresh loop.
        if snapshot != next { snapshot = next }
    }

    func perform(_ action: Action) {
        perform(action, in: NSApp.keyWindow)
    }

    func perform(_ action: Action, in window: NSWindow?) {
        // Recheck focus at dispatch time: a menu snapshot may predate a sheet or editor.
        if let manager = archiveManager(in: window) {
            if action == .undo, manager.canUndo { manager.undo() }
            if action == .redo, manager.canRedo { manager.redo() }
        } else {
            let manager = manager(in: window)
            if action == .undo ? manager?.canUndo == true : manager?.canRedo == true {
                NSApp.sendAction(action.selector, to: nil, from: nil)
            }
        }
        refresh()
    }
}
