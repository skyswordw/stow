import SwiftUI

/// View and Go menus for the browser: view modes, helper items, names, history and opening.
struct BrowseCommands: Commands {
    let app: AppState
    private let routing = EditingUndoCommandsModel.shared
    private let closing = WindowCloseCommand.shared
    private let extracting = ExtractAllCommand.shared
    @AppStorage(SettingsKeys.nextStepsShown) private var showsNextSteps = true
    @AppStorage(SettingsKeys.nextStepsHidden) private var hiddenSteps = NextStepsSettings.encode(NextStepsSettings.defaultHidden)

    var body: some Commands {
        let draft = ArchiveDraft.focused(in: NSApp.keyWindow)
        let browser = draft == nil && app.passwords.question == nil ? app.browser : nil
        let _ = routing.snapshot
        let archiveOwnsFocus = browser.map {
            routing.archiveManager(in: NSApp.keyWindow) === $0.editingUndoManager
        } ?? false
        let draftOwnsFocus = draft.map { routing.archiveManager(in: NSApp.keyWindow) === $0.undoManager } ?? false
        CommandGroup(replacing: .saveItem) {
            // Replacing this group also removes macOS's Close command (#225).
            Button("Close") { closing.perform(in: NSApp.keyWindow, app: app) }
                .keyboardShortcut("w")
                .disabled(!closing.isEnabled)
            Divider()
            Button(draft == nil ? String(localized: "Save") : String(localized: "Pack…")) {
                if let draft { draft.prepareSave() }
                else { app.passwords.performCommand { if let browser { Task { await browser.saveEdits() } } } }
            }
                .disabled(app.passwords.question != nil)
                .keyboardShortcut("s")
                .disabled(draft.map { !$0.canSave || app.packing.isRunning } ?? (browser?.editSession.canSave != true))
            Button("Save a Copy…") { app.passwords.performCommand { if let browser { Task { await browser.saveCopyOfArchive() } } } }
                .disabled(app.passwords.question != nil)
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(browser?.editSession.canSaveCopy != true)
            Button("Revert to Saved") { app.passwords.performCommand { browser?.revertEdits() } }
                .disabled(app.passwords.question != nil)
                .disabled(browser?.editSession.canRevert != true)
            Button("Reload") { app.passwords.performCommand { if let browser { Task { await browser.reloadArchive() } } } }
                .disabled(app.passwords.question != nil)
                .disabled(browser?.archive.source == nil || browser?.editSession.isSaving == true)
            Button("Rename Archive…") { app.passwords.performCommand { if let browser { Task { await browser.renameArchive() } } } }
                .disabled(app.passwords.question != nil)
                .disabled(browser?.archive.source == nil || browser?.editSession.isSaving == true || browser?.levels.count != 1)
            if browser?.editSession.format == nil, browser != nil {
                Button("Extract and Repack as ZIP or 7Z…") { app.passwords.performCommand { if let browser { app.extractAndRepack(browser) } } }
                    .disabled(app.passwords.question != nil)
            }
        }
        CommandGroup(after: .newItem) {
            // Next Steps' Extract, here too so ⌘E works with Next Steps turned off.
            Button("Extract") { app.passwords.performCommand { browser?.run(.extract) } }
                .disabled(app.passwords.question != nil)
                .keyboardShortcut("e")
                .disabled(browser?.selection.isEmpty != false || browser?.activity != nil)
            Button("Extract All") { app.passwords.performCommand { extracting.perform(in: NSApp.keyWindow) } }
                .disabled(app.passwords.question != nil)
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(!extracting.isEnabled)
            // Every action for the selection, the stack's front one first: the way to all of them
            // from the keyboard (⌃F2, or Help's search) without macOS's keyboard navigation turned on.
            // With nothing selected, installing an archive that's one app — on that app, never on
            // whatever comes first.
            let settings = NextStepsSettings(isShown: showsNextSteps, hidden: NextStepsSettings.decode(hiddenSteps))
            let archiveTarget = browser?.archiveTarget
            let layout = browser.map { browser in
                browser.selection.isEmpty ? settings.archiveLayout(installable: archiveTarget)
                    : settings.layout(for: browser.selectedEntries, dropTargets: browser.archive.dropTargets)
            }
            let steps = layout.map { [$0.front].compactMap(\.self) + $0.more } ?? []
            Menu("Actions") {
                if let browser {
                    NextStepsMoreItems(model: browser, alternatives: steps, showsShortcuts: false,
                                       entries: archiveTarget.map { [$0] })
                }
            }
            .disabled(steps.isEmpty || browser?.activity != nil)
        }
        CommandGroup(after: .pasteboard) {
            // Keep menu invocations available in read-only archives so they explain the refusal;
            // item context menus disable mutations and expose the same reason as help.
            Button("Add Files…") {
                if let draft { draft.chooseSources() } else { app.passwords.performCommand { browser?.chooseAddFiles() } }
            }
                .disabled(app.passwords.question != nil)
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(draft.map { $0.isImporting || $0.isSaving } ?? (browser == nil || browser?.editSession.isSaving == true))
                .help(browser?.editSession.format == nil ? browser?.editSession.readOnlyReason ?? "" : String(localized: "Add Files…"))
            // Only from the archive's own window (full or Glance): pressed in the Tray or Settings,
            // ⌘⌫ must not stage deleting whatever is selected in an archive behind it.
            Button("Delete") {
                if let draft, draftOwnsFocus { draft.removeSelection(); return }
                app.passwords.performCommand {
                    if let browser, routing.archiveManager(in: NSApp.keyWindow) === browser.editingUndoManager {
                        browser.editSession.delete(Array(browser.selection))
                    }
                }
            }
                .disabled(app.passwords.question != nil)
                .keyboardShortcut((archiveOwnsFocus || draftOwnsFocus) ? KeyboardShortcut(.delete, modifiers: .command) : nil)
                .disabled(draft.map { !draftOwnsFocus || $0.selection.isEmpty || $0.isImporting || $0.isSaving }
                          ?? (browser?.editSession.canDelete(selectionIsEmpty: browser?.selection.isEmpty ?? true,
                                                            archiveOwnsFocus: archiveOwnsFocus) != true))
                .help(browser?.editSession.refusal(for: Array(browser?.selection ?? [])) ?? (browser?.editSession.format == nil ? browser?.editSession.readOnlyReason ?? "" : String(localized: "Delete")))
            // Return already opens the selected item in all three browser modes.
            Button("Rename") { app.passwords.performCommand { if let browser, let entry = browser.selectedEntries.first { browser.beginRename(entry) } } }
                .disabled(app.passwords.question != nil)
                .disabled(browser?.selection.count != 1 || browser?.editSession.isSaving == true)
            Button("Replace…") { app.passwords.performCommand { if let browser, let entry = browser.selectedEntries.first { browser.chooseReplacement(entry) } } }
                .disabled(app.passwords.question != nil)
                .disabled(browser?.selection.count != 1 || browser?.selectedEntries.first?.isFolder != false || browser?.editSession.isSaving == true)
        }
        CommandGroup(after: .textEditing) {
            // Search is in the full window's title bar (#215). ⌘F focuses it, expanding it
            // first if the window is too narrow to show the field. Glance has none.
            Button("Find…") {
                if let draft { draft.browsing.searchFocusRequest += 1 }
                else { app.passwords.performCommand { browser?.focusSearch() } }
            }
                .disabled(app.passwords.question != nil)
                .keyboardShortcut("f")
                .disabled(draft.map(\.files.isEmpty) ?? (browser == nil || app.glance.isShown))
        }
        CommandGroup(before: .toolbar) {
            Button("as Icons") { if let draft { draft.browsing.viewMode = .grid } else { app.passwords.performCommand { browser?.viewMode = .grid } } }
                .disabled(app.passwords.question != nil)
                .keyboardShortcut("1")
            Button("as List") { if let draft { draft.browsing.viewMode = .list } else { app.passwords.performCommand { browser?.viewMode = .list } } }
                .disabled(app.passwords.question != nil)
                .keyboardShortcut("2")
            Button("as Columns") { if let draft { draft.browsing.viewMode = .columns } else { app.passwords.performCommand { browser?.viewMode = .columns } } }
                .disabled(app.passwords.question != nil)
                .keyboardShortcut("3")
            Divider()
            Toggle("Show macOS Helper Items", isOn: Binding(
                get: { browser?.showHelperItems ?? false },
                set: { value in app.passwords.performCommand { browser?.showHelperItems = value } }
            ))
            .keyboardShortcut(".", modifiers: [.command, .shift])
            .disabled(browser?.archive.hasHelpers != true)
            Button("Read Names As…") { app.passwords.performCommand { browser?.isChoosingEncoding = true } }
                .disabled(app.passwords.question != nil)
                .disabled(browser?.legacyNames.isEmpty != false)
            Divider()
        }
        CommandMenu("Go") {
            Button("Back") { app.passwords.performCommand { browser?.goBack() } }
                .disabled(app.passwords.question != nil)
                .keyboardShortcut("[")
                .disabled(browser?.canGoBack != true)
            Button("Forward") { app.passwords.performCommand { browser?.goForward() } }
                .disabled(app.passwords.question != nil)
                .keyboardShortcut("]")
                .disabled(browser?.canGoForward != true)
            Button("Enclosing Folder") { app.passwords.performCommand { browser?.goUp() } }
                .disabled(app.passwords.question != nil)
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(browser?.canGoUp != true)
            Divider()
            Button("Open") {
                app.passwords.performCommand {
                    if let browser, browser.selectedEntries.count == 1 { browser.open(browser.selectedEntries[0]) }
                    else { browser?.openWithDefaultApp(browser?.selectedEntries ?? []) }
                }
            }
                .disabled(app.passwords.question != nil)
            .keyboardShortcut(.downArrow, modifiers: .command)
            .disabled(browser?.selection.isEmpty != false)
            Button("Quick Look") { app.passwords.performCommand { browser?.toggleQuickLook() } }
                .disabled(app.passwords.question != nil)
                .keyboardShortcut("y")
                .disabled(browser?.selection.isEmpty != false)
            Button("Show Package Contents") {
                app.passwords.performCommand {
                    if let entry = browser?.selectedEntries.first { browser?.showPackageContents(entry) }
                }
            }
                .disabled(app.passwords.question != nil)
            .disabled(browser?.selectedEntries.first.map { $0.isPackage || $0.kind == .archive } != true)
        }
    }
}
