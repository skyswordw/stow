import SwiftUI

/// View and Go menus for the browser: view modes, helper items, names, history and opening.
struct BrowseCommands: Commands {
    let app: AppState
    private let routing = EditingUndoCommandsModel.shared

    var body: some Commands {
        let browser = app.browser
        let _ = routing.snapshot
        let archiveOwnsFocus = browser.map {
            routing.archiveManager(in: NSApp.keyWindow) === $0.editingUndoManager
        } ?? false
        CommandGroup(replacing: .saveItem) {
            Button("Save") { if let browser { Task { await browser.saveEdits() } } }
                .keyboardShortcut("s")
                .disabled(browser?.editSession.isEdited != true || browser?.editSession.isSaving == true || browser?.editSession.changedOnDisk == true)
            Button("Save a Copy…") { if let browser { Task { await browser.saveCopyOfArchive() } } }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(browser?.editSession.isEdited != true || browser?.editSession.isSaving == true)
            Button("Revert to Saved") { browser?.revertEdits() }
                .disabled(browser?.editSession.isEdited != true || browser?.editSession.isSaving == true)
            Button("Reload") { if let browser { Task { await browser.reloadArchive() } } }
                .disabled(browser?.archive.source == nil || browser?.editSession.isSaving == true)
            Button("Rename Archive…") { if let browser { Task { await browser.renameArchive() } } }
                .disabled(browser?.archive.source == nil || browser?.editSession.isSaving == true || browser?.levels.count != 1)
            if browser?.editSession.format == nil, browser != nil {
                Button("Extract and Repack as ZIP or 7Z…") { if let browser { app.extractAndRepack(browser) } }
            }
        }
        CommandGroup(after: .newItem) {
            // Next Steps' Extract, here too so ⌘E works with Next Steps turned off.
            Button("Extract") { browser?.run(.extract) }
                .keyboardShortcut("e")
                .disabled(browser?.selection.isEmpty != false || browser?.activity != nil)
        }
        CommandGroup(after: .pasteboard) {
            // Keep menu invocations available in read-only archives so they explain the refusal;
            // item context menus disable mutations and expose the same reason as help.
            Button("Add Files…") { browser?.chooseAddFiles() }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(browser == nil || browser?.editSession.isSaving == true)
                .help(browser?.editSession.format == nil ? browser?.editSession.readOnlyReason ?? "" : String(localized: "Add Files…"))
            // Only from the archive's own window (full or Glance): pressed in the Tray or Settings,
            // ⌘⌫ must not stage deleting whatever is selected in an archive behind it.
            Button("Delete") {
                if let browser, routing.archiveManager(in: NSApp.keyWindow) === browser.editingUndoManager {
                    browser.editSession.delete(Array(browser.selection))
                }
            }
                .keyboardShortcut(archiveOwnsFocus ? KeyboardShortcut(.delete, modifiers: .command) : nil)
                .disabled(!archiveOwnsFocus || browser?.selection.isEmpty != false || browser?.editSession.isSaving == true)
                .help(browser?.editSession.refusal(for: Array(browser?.selection ?? [])) ?? (browser?.editSession.format == nil ? browser?.editSession.readOnlyReason ?? "" : String(localized: "Delete")))
            // Return already opens the selected item in all three browser modes.
            Button("Rename") { if let browser, let entry = browser.selectedEntries.first { browser.beginRename(entry) } }
                .disabled(browser?.selection.count != 1 || browser?.editSession.isSaving == true)
            Button("Replace…") { if let browser, let entry = browser.selectedEntries.first { browser.chooseReplacement(entry) } }
                .disabled(browser?.selection.count != 1 || browser?.selectedEntries.first?.isFolder != false || browser?.editSession.isSaving == true)
        }
        CommandGroup(after: .textEditing) {
            // The Browser's search lives in the toolbar, where a narrow window folds it into a
            // button; ⌘F reaches it either way. Glance has no search of its own.
            Button("Find…") { browser?.focusSearch() }
                .keyboardShortcut("f")
                .disabled(browser == nil || app.glance.isShown)
        }
        CommandGroup(before: .toolbar) {
            Button("as Icons") { browser?.viewMode = .grid }
                .keyboardShortcut("1")
            Button("as List") { browser?.viewMode = .list }
                .keyboardShortcut("2")
            Button("as Columns") { browser?.viewMode = .columns }
                .keyboardShortcut("3")
            Divider()
            Toggle("Show macOS Helper Items", isOn: Binding(
                get: { browser?.showHelperItems ?? false },
                set: { browser?.showHelperItems = $0 }
            ))
            .keyboardShortcut(".", modifiers: [.command, .shift])
            .disabled(browser?.archive.hasHelpers != true)
            Button("Read Names As…") { browser?.isChoosingEncoding = true }
                .disabled(browser?.legacyNames.isEmpty != false)
            Divider()
        }
        CommandMenu("Go") {
            Button("Back") { browser?.goBack() }
                .keyboardShortcut("[")
                .disabled(browser?.canGoBack != true)
            Button("Forward") { browser?.goForward() }
                .keyboardShortcut("]")
                .disabled(browser?.canGoForward != true)
            Button("Enclosing Folder") { browser?.goUp() }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(browser?.canGoUp != true)
            Divider()
            Button("Open") {
                if let browser, browser.selectedEntries.count == 1 { browser.open(browser.selectedEntries[0]) }
                else { browser?.openWithDefaultApp(browser?.selectedEntries ?? []) }
            }
            .keyboardShortcut(.downArrow, modifiers: .command)
            .disabled(browser?.selection.isEmpty != false)
            Button("Quick Look") { browser?.toggleQuickLook() }
                .keyboardShortcut("y")
                .disabled(browser?.selection.isEmpty != false)
            Button("Show Package Contents") {
                if let entry = browser?.selectedEntries.first { browser?.showPackageContents(entry) }
            }
            .disabled(browser?.selectedEntries.first.map { $0.isPackage || $0.kind == .archive } != true)
        }
    }
}
