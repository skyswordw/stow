import SwiftUI

/// Extraction settings, ready for a pane in the Settings window.
struct ExtractionOptionsView: View {
    @AppStorage(Preferences.Key.extractAllFolder) private var allFolder = Preferences.defaults.extractAllFolder
    @AppStorage(Preferences.Key.afterExtractAll) private var afterExtractAll = Preferences.defaults.afterExtractAll
    @AppStorage(Preferences.Key.closeWindowAfter) private var closeWindow = Preferences.defaults.closeWindowAfter
    @AppStorage(Preferences.Key.folderConflict) private var folderConflict = Preferences.defaults.folderConflict
    @AppStorage(Preferences.Key.fileConflict) private var fileConflict = Preferences.defaults.fileConflict
    @AppStorage(Preferences.Key.skipSystemFiles) private var skipSystemFiles = Preferences.defaults.skipSystemFiles

    var body: some View {
        Form {
            Section {
                Picker("Extract All puts things", selection: $allFolder) {
                    Text("In a folder when there’s more than one item").tag(Preferences.ExtractAllFolder.automatic)
                    Text("Always in a folder named after the archive").tag(Preferences.ExtractAllFolder.always)
                }
                Picker("Afterwards, the archive", selection: $afterExtractAll) {
                    AfterwardsLabels()
                }
                Toggle("Close the window after Extract All or an install", isOn: $closeWindow)
            }
            Section {
                Picker("Same-name folder", selection: $folderConflict) {
                    Text("Ask").tag(Preferences.FolderConflict.ask)
                    Text("Merge").tag(Preferences.FolderConflict.merge)
                    Text("Keep both").tag(Preferences.FolderConflict.keepBoth)
                }
                Picker("Same-name file", selection: $fileConflict) {
                    Text("Ask").tag(Preferences.FileConflict.ask)
                    Text("Replace").tag(Preferences.FileConflict.replace)
                    Text("Keep both").tag(Preferences.FileConflict.keepBoth)
                    Text("Skip").tag(Preferences.FileConflict.skip)
                }
            } header: {
                Text("When something is already there")
            } footer: {
                Text("Replaced files go to the Trash, so nothing is lost.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Leave out system files", isOn: $skipSystemFiles)
            } footer: {
                Text("“__MACOSX”, “.DS_Store”, “._” files, “Thumbs.db” and “desktop.ini”. Dotfiles like “.gitignore” are always kept.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Install settings for the Next Steps.
struct InstallOptionsView: View {
    @AppStorage(Preferences.Key.afterInstall) private var afterInstall = Preferences.defaults.afterInstall
    @AppStorage(Preferences.Key.removeQuarantine) private var removeQuarantine = Preferences.defaults.removeQuarantine
    @State private var applicationsGranted = FolderAccess.isRemembered(FolderAccess.applications)
    @State private var fontsGranted = FolderAccess.isRemembered(FolderAccess.userFonts)

    var body: some View {
        Form {
            Section {
                Picker("After installing, the archive", selection: $afterInstall) {
                    AfterwardsLabels()
                }
            }
            Section {
                Toggle("Remove the quarantine flag from installed apps", isOn: $removeQuarantine)
            } footer: {
                Text("macOS marks apps that came from the internet so Gatekeeper can check them the first time they open. Removing the mark skips that check — only turn this on if you trust everything you install. Unsigned or unnotarized apps still get a warning from Stow first.")
                    .foregroundStyle(.secondary)
            }
            Section {
                grantRow(String(localized: "Applications"), granted: $applicationsGranted, folder: FolderAccess.applications)
                grantRow(String(localized: "Your font library"), granted: $fontsGranted, folder: FolderAccess.userFonts)
            } header: {
                Text("Folders Stow may install into")
            } footer: {
                Text("Stow is sandboxed. It asks once before the first install into a folder and remembers only that folder.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func grantRow(_ title: String, granted: Binding<Bool>, folder: URL) -> some View {
        LabeledContent(title) {
            if granted.wrappedValue {
                Button("Forget") {
                    FolderAccess.forget(folder)
                    granted.wrappedValue = false
                }
            } else {
                Text("Asked on first install").foregroundStyle(.secondary)
            }
        }
    }
}

private struct AfterwardsLabels: View {
    var body: some View {
        Text("Stays where it is").tag(Preferences.AfterwardsArchive.keep)
        Text("Moves to the Trash").tag(Preferences.AfterwardsArchive.trash)
        Text("Ask each time").tag(Preferences.AfterwardsArchive.ask)
    }
}
