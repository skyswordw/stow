import SwiftUI

/// Settings › Integration: Finder menu, login item, Dock icon and the folders Stow may write in.
/// Standalone so Settings can host it; also the `integration` demo scene.
struct IntegrationView: View {
    @State var settings = IntegrationSettings.shared
    @State var folders = FolderAccess.shared

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Button("Repair…") { Task { await settings.repairFinderExtension() } }
                        .disabled(settings.isRepairing)
                        .accessibilityLabel(String(localized: "Repair Finder Menu"))
                        .accessibilityHint(settings.finderExtensionEnabled ? String(localized: "Finder menu is on") : String(localized: "Finder menu is off"))
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(settings.finderExtensionEnabled ? String(localized: "Finder menu is on") : String(localized: "Finder menu is off"))
                            Text("Extract Here, Extract To…, Open in Stow and Compress in Finder’s context menu.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: settings.finderExtensionEnabled ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(settings.finderExtensionEnabled ? .green : .yellow)
                    }
                }
                if !settings.repairSteps.isEmpty {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        ForEach(settings.repairSteps) { step in
                            Label(step.text, systemImage: symbol(for: step.outcome))
                                .font(.callout)
                                .foregroundStyle(.primary)
                                .symbolRenderingMode(.hierarchical)
                        }
                    }
                }
                Toggle("Show on external drives", isOn: $settings.showsOnExternalDrives)
                Button("Extension Settings…") { settings.showExtensionSettings() }
                    .buttonStyle(.borderless)
            } header: {
                Text("Finder").accessibilityAddTraits(.isHeader)
            }

            Section {
                Toggle(isOn: Binding(get: { settings.launchesAtLogin }, set: { settings.setLaunchesAtLogin($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open Stow at login")
                        Text(settings.loginItemSummary)
                            .font(.caption)
                            .foregroundStyle(settings.loginItemError == nil ? .secondary : Color.red)
                    }
                }
                .accessibilityLabel(String(localized: "Open Stow at login"))
                .accessibilityHint(settings.loginItemSummary)
                if settings.loginItemStatus == .requiresApproval {
                    Button("Open Login Items Settings") { settings.openLoginItemsSettings() }
                }
                Text("Tray controls whether Stow stays available after its windows close.")
                Button("Tray Settings…") { SettingsRouter.shared.show(.tray) }

            } header: {
                Text("Startup").accessibilityAddTraits(.isHeader)
            }

            Section {
                if folders.displayedGrants.isEmpty {
                    Text("None yet. When opening, extracting or compressing needs folder access, Stow asks you to choose a folder.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(folders.displayedGrants, id: \.self) { folder in
                        SavedItemRow(folder: folder) {
                            Button("Forget") { folders.removeDisplayedGrant(folder) }
                        }
                    }
                }
            } header: {
                Text("Folders Stow may access").accessibilityAddTraits(.isHeader)
            } footer: {
                Text("Access includes the folder’s files and subfolders. Forget removes Stow’s saved authorization; macOS may keep access until Stow quits. Some protected locations may still be unavailable.")
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            settings.refresh()
        }
    }

    private func symbol(for outcome: IntegrationSettings.RepairStep.Outcome) -> String {
        switch outcome {
        case .done: "checkmark.circle"
        case .failed: "xmark.circle"
        case .todo: "arrow.right.circle"
        }
    }
}

/// Something Stow keeps for later, listed the same way in Finder & Permissions, Installing and
/// Passwords: a symbol, the item's name over where it is, and what can be done about it on the
/// trailing edge.
struct SavedItemRow<Trailing: View>: View {
    let name: String
    let path: String
    var symbol = "folder"
    @ViewBuilder let trailing: Trailing

    init(name: String, folder: URL, @ViewBuilder trailing: () -> Trailing) {
        self.name = name
        self.path = Self.displayPath(folder)
        self.trailing = trailing()
    }

    init(folder: URL, @ViewBuilder trailing: () -> Trailing) {
        let path = folder.path(percentEncoded: false)
        self.init(name: FileManager.default.displayName(atPath: path), folder: folder, trailing: trailing)
    }

    /// A file by its name over the folder that holds it (the name isn't repeated in the path).
    init(name: String, file path: String, symbol: String, @ViewBuilder trailing: () -> Trailing) {
        self.name = name
        self.path = path.isEmpty ? "" : Self.displayPath(URL(filePath: path).deletingLastPathComponent())
        self.symbol = symbol
        self.trailing = trailing()
    }

    /// The path with the real home folder as "~" (the sandbox's own home isn't it), no trailing slash.
    static func displayPath(_ folder: URL) -> String {
        var path = folder.path(percentEncoded: false)
        if path.count > 1, path.hasSuffix("/") { path.removeLast() }
        let home = FolderAccess.home.path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let homePath = "/" + home
        if path == homePath { return "~" }
        if path.hasPrefix(homePath + "/") { return "~" + path.dropFirst(homePath.count) }
        return path
    }

    var body: some View {
        LabeledContent {
            trailing
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if !path.isEmpty {
                        Text(path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
            } icon: {
                Image(systemName: symbol)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
    }
}
