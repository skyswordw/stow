import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage(SettingsKeys.appearance) private var appearance = SettingsKeys.Appearance.system.rawValue
    @AppStorage(SettingsKeys.defaultView) private var viewMode = "grid"
    @AppStorage("PackCPUCores") private var cores = 0
    @AppStorage(SettingsKeys.openInGlance) private var openInGlance = false
    @AppStorage(SettingsKeys.trayMenuBarIcon) private var trayIcon = true
    @AppStorage(SettingsKeys.trayShowWhileDragging) private var trayWhileDragging = true
    @AppStorage(SettingsKeys.trayIdleSeconds) private var trayIdle = 30
    @AppStorage(SettingsKeys.trayBorder) private var trayBorder = TrayBorder.accent.rawValue
    var body: some View {
        Form {
            Picker("Appearance", selection: $appearance) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            Picker("Open Browser in", selection: $viewMode) {
                Text("Grid").tag("grid")
                Text("List").tag("list")
                Text("Columns").tag("columns")
            }
            Toggle("Open archives from Finder and Quick Look in Glance", isOn: $openInGlance)
            Picker("CPU cores for packing", selection: $cores) {
                Text("All").tag(0)
                ForEach(1...ProcessInfo.processInfo.activeProcessorCount, id: \.self) { Text("\($0)").tag($0) }
            }
            Section("Tray") {
                Toggle("Show Tray icon in the menu bar", isOn: $trayIcon)
                Toggle("Show Tray while dragging files", isOn: $trayWhileDragging)
                Picker("Hide Tray when idle", selection: $trayIdle) {
                    ForEach(TrayRules.idleChoices, id: \.self) { seconds in
                        Text(Self.idleTitle(seconds)).tag(seconds)
                    }
                }
                Picker("Tray border", selection: $trayBorder) {
                    ForEach(TrayBorder.allCases) { border in
                        Label { Text(border.title) } icon: {
                            Image(systemName: "circle.fill").foregroundStyle(border.color)
                        }
                        .tag(border.rawValue)
                    }
                }
            }
            UpdateSettingsSection(updater: AppUpdater.shared)
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }

    private static func idleTitle(_ seconds: Int) -> String {
        switch seconds {
        case 0: String(localized: "Never")
        case 10: String(localized: "After 10 seconds")
        case 30: String(localized: "After 30 seconds")
        case 60: String(localized: "After 1 minute")
        default: String(localized: "After 5 minutes")
        }
    }
}

/// Sparkle's two choices (#35). Off, and dimmed, in builds that never check (Debug, ad-hoc, tests).
private struct UpdateSettingsSection: View {
    let updater: AppUpdater
    var body: some View {
        Section {
            Toggle("Check for updates automatically", isOn: Binding(
                get: { updater.automaticallyChecks }, set: { updater.setAutomaticallyChecks($0) }))
            Toggle("Download and install updates automatically", isOn: Binding(
                get: { updater.automaticallyDownloads }, set: { updater.setAutomaticallyDownloads($0) }))
                .disabled(!updater.automaticallyChecks)
        } header: {
            Text("Updates")
        } footer: {
            if updater.isAvailable {
                Text("An update waits until extracting or packing finishes before Stow restarts.")
            } else {
                Text("This build doesn’t check for updates. Signed releases from GitHub do.")
            }
        }
        .disabled(!updater.isAvailable)
    }
}

struct PackingSettingsView: View {
    @AppStorage("PackAudience") private var audience = Audience.windows.rawValue
    @AppStorage("PackVerify") private var verify = false
    @AppStorage(SettingsKeys.volumeSize) private var volume = 0
    var body: some View {
        Form {
            Picker("Pack for", selection: $audience) {
                ForEach(Audience.allCases) { item in Text(item.phrase.sentenceCased).tag(item.rawValue) }
            }
            Section("Compression level for each destination") {
                ForEach(Audience.allCases) { item in LevelSetting(audience: item) }
            }
            Picker("Split archives", selection: $volume) {
                ForEach(SplitSize.allCases) { item in Text(item.phrase.sentenceCased).tag(Int(item.rawValue)) }
            }
            Toggle("Check archives after packing", isOn: $verify)
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct LevelSetting: View {
    let audience: Audience
    @AppStorage private var level: Int
    init(audience: Audience) {
        self.audience = audience
        _level = AppStorage(wrappedValue: CompressionLevel.balanced.rawValue, "PackLevel.\(audience.rawValue)")
    }
    var body: some View {
        Picker(audience.phrase.sentenceCased, selection: $level) {
            ForEach(CompressionLevel.allCases) { item in Text(item.title).tag(item.rawValue) }
        }
    }
}

struct PreviewSettingsView: View {
    @AppStorage(SettingsKeys.hoverPreviews) private var hover = true
    var body: some View {
        Form { Toggle("Show previews when hovering over files", isOn: $hover) }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct PasswordSettingsView: View {
    @AppStorage(SettingsKeys.showPassword) private var show = false
    var body: some View {
        Form {
            Section {
                Toggle("Show passwords by default", isOn: $show)
            } footer: {
                Text("Visible passwords support Chinese and Japanese input methods. You can hide a password in the password sheet.")
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct AdvancedSettingsView: View {
    @Environment(AppState.self) private var app
    @State private var usedBytes: Int64 = 0
    @State private var confirmsReset = false
    private var busy: Bool { app.isBusy }
    var body: some View {
        Form {
            Section("Temporary files") {
                LabeledContent("Preview cache", value: usedBytes.bytes)
                    .monospacedDigit()
                Button("Clean Up") {
                    guard !busy else { return }
                    PreviewCache.cleanUp()
                    usedBytes = PreviewCache.directoryBytes
                }
                .disabled(busy)
            }
            Section {
                Button("Reset All Preferences…", role: .destructive) { confirmsReset = true }
            } footer: {
                Text("File types keep their previous apps so you can still switch back. Folder permissions and login items are managed separately.")
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { usedBytes = PreviewCache.directoryBytes }
        .alert("Reset all preferences?", isPresented: $confirmsReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                SettingsKeys.reset(in: .standard)
                IntegrationSettings.shared.reloadPreferences()
                AppUpdater.shared.reload()
                SettingsAppearance.apply()
            }
        } message: {
            Text("Restore Stow’s settings to their defaults. Your archives and remembered previous apps are kept.")
        }
    }
}

private extension String {
    /// `Audience` and `SplitSize` phrases are written to sit inside a sentence; a label starts upper-case.
    var sentenceCased: String { prefix(1).uppercased() + dropFirst() }
}
