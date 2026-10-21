import SwiftUI

/// View and Go menus for the browser: view modes, helper items, names, history and opening.
struct BrowseCommands: Commands {
    let app: AppState

    var body: some Commands {
        let browser = app.browser
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
