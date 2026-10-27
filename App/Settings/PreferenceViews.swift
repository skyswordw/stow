import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage(SettingsKeys.appearance) private var appearance = SettingsKeys.Appearance.system.rawValue
    @AppStorage(SettingsKeys.defaultView) private var viewMode = "grid"
    @AppStorage("PackCPUCores") private var cores = 0
    @AppStorage(SettingsKeys.openInGlance) private var openInGlance = false
    @AppStorage(SettingsKeys.glanceColourfulControls) private var colourfulGlanceControls = false
    @AppStorage(SettingsKeys.glanceMaterial) private var glanceMaterial = SettingsKeys.GlanceMaterialPreference.liquidGlass.rawValue
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
            Toggle("Colourful Glance window controls", isOn: $colourfulGlanceControls)
                .help("Use red for Close, yellow for Pin on Top, and green for Open in Full Window")
            Picker("Glance material", selection: $glanceMaterial) {
                ForEach(SettingsKeys.GlanceMaterialPreference.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .help("Liquid Glass is the default. Classic frosted uses a traditional material. Reduce Transparency always uses a solid window.")
            Picker("CPU cores for packing", selection: $cores) {
                Text("All").tag(0)
                ForEach(1...ProcessInfo.processInfo.activeProcessorCount, id: \.self) { Text("\($0)").tag($0) }
            }
            Section("App Language") {
                Text("To use English or Simplified Chinese just for Stow, open System Settings → General → Language & Region → Applications. Add Stow and choose its language. Quit and reopen Stow after your current tasks and unsaved changes are finished.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Tray") {
                Toggle("Show Tray icon in the menu bar", isOn: $trayIcon)
                // Dragging files anywhere else leaves the Tray alone (#180); say where to take them.
                Toggle(isOn: $trayWhileDragging) {
                    Text("Show Tray when files are dragged to it")
                    Text(trayIcon ? String(localized: "Drag files up to the Tray icon in the menu bar.")
                                  : String(localized: "Drag files to the right edge of the screen."))
                }
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
    @State private var showCustom = false
    @State private var customText = ""
    @State private var customUnit: SplitSize.CustomUnit = .megabyte

    private var current: SplitSize { SplitSize.stored(Int64(volume)) }

    var body: some View {
        Form {
            Picker("Pack for", selection: $audience) {
                ForEach(Audience.allCases) { item in Text(item.phrase.sentenceCased).tag(item.rawValue) }
            }
            Section("Compression level for each destination") {
                ForEach(Audience.allCases) { item in LevelSetting(audience: item) }
            }
            Picker("Split archives", selection: volumeSelection) {
                ForEach(SplitSize.allCases) { item in Text(item.phrase.sentenceCased).tag(Int(item.rawValue)) }
                if current.isCustom {
                    Text(current.phrase.sentenceCased).tag(Int(current.rawValue))
                }
                Text("Custom…").tag(-1)
            }
            if showCustom || current.isCustom {
                HStack {
                    TextField("Size", text: $customText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 88)
                        .onSubmit(applyCustom)
                    Picker("Unit", selection: $customUnit) {
                        ForEach(SplitSize.CustomUnit.allCases) { Text($0.symbol).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Button("Use") { applyCustom() }
                        .disabled(SplitSize.parseCustom(customText, unit: customUnit) == nil)
                }
            }
            Toggle("Check archives after packing", isOn: $verify)
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            if current.isCustom {
                showCustom = true
                seedCustom(from: current)
            }
        }
    }

    private var volumeSelection: Binding<Int> {
        Binding(
            get: { showCustom && !current.isCustom ? -1 : volume },
            set: { chosen in
                if chosen == -1 {
                    showCustom = true
                    seedCustom(from: current)
                    return
                }
                showCustom = false
                volume = chosen
            }
        )
    }

    private func seedCustom(from size: SplitSize) {
        guard size.rawValue > 0 else {
            customText = ""
            customUnit = .megabyte
            return
        }
        if size.rawValue >= 1_000_000_000, size.rawValue % 1_000_000_000 == 0 {
            customText = String(size.rawValue / 1_000_000_000)
            customUnit = .gigabyte
        } else if size.rawValue % 1_000_000 == 0 {
            customText = String(size.rawValue / 1_000_000)
            customUnit = .megabyte
        } else {
            customText = String(format: "%g", Double(size.rawValue) / 1_000_000)
            customUnit = .megabyte
        }
    }

    private func applyCustom() {
        guard let size = SplitSize.parseCustom(customText, unit: customUnit) else { return }
        volume = Int(size.rawValue)
        showCustom = true
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
    @AppStorage(SettingsKeys.rememberPasswords) private var remember = false
    @State private var entries: [ArchivePasswordEntry] = []
    @State private var confirmsWipe = false

    var body: some View {
        Form {
            Section {
                Toggle("Show passwords by default", isOn: $show)
            } footer: {
                Text("Visible passwords support Chinese and Japanese input methods. You can hide a password in the password sheet.")
            }
            Section {
                Toggle("Remember passwords in Keychain", isOn: $remember)
            } footer: {
                Text("When on, a password that unlocks an archive is saved in your Keychain — nowhere else, and only this app can read it. When off, Stow keeps passwords only while the archive is open.")
            }
            if remember {
                Section {
                    if entries.isEmpty {
                        Text("No saved passwords yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(entries) { entry in
                            LabeledContent {
                                Button("Forget", role: .destructive) {
                                    ArchivePasswordVault.forget(entry)
                                    reload()
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.displayName)
                                    if !entry.identity.path.isEmpty {
                                        Text(entry.identity.path)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                            }
                        }
                    }
                    if !entries.isEmpty {
                        Button("Remove All Saved Passwords…", role: .destructive) { confirmsWipe = true }
                    }
                } header: {
                    Text("Saved passwords")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: reload)
        .onChange(of: remember) { reload() }
        .alert("Remove all saved passwords?", isPresented: $confirmsWipe) {
            Button("Cancel", role: .cancel) {}
            Button("Remove All", role: .destructive) {
                ArchivePasswordVault.wipe()
                reload()
            }
        } message: {
            Text("Stow forgets every archive password stored in your Keychain. Archives already open keep their passwords until you close them.")
        }
    }

    private func reload() {
        entries = ArchivePasswordVault.entries()
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
