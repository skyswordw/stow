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
                if settings.loginItemStatus == .requiresApproval {
                    Button("Open Login Items Settings") { settings.openLoginItemsSettings() }
                }
                Toggle(isOn: $settings.hidesDockIconWithoutWindows) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hide Dock icon when no windows are open")
                        Text("Stow keeps running for Finder and Services actions. Open Stow from Finder or Spotlight to bring it back.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Startup").accessibilityAddTraits(.isHeader)
            }

            Section {
                if folders.grants.isEmpty {
                    Text("None yet. The first time you extract or compress somewhere new from Finder, Stow asks once for that folder.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(folders.grants, id: \.self) { folder in
                        LabeledContent {
                            Button("Remove") { folders.revoke(folder) }
                        } label: {
                            Label(folder.path(percentEncoded: false), systemImage: "folder")
                                .lineLimit(1)
                                .truncationMode(.head)
                        }
                    }
                }
            } header: {
                Text("Folders Stow may write in").accessibilityAddTraits(.isHeader)
            } footer: {
                Text("Stow is sandboxed: it only reads and writes where you allow it. No Full Disk Access needed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
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
