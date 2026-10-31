import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage(SettingsKeys.appearance) private var appearance = SettingsKeys.Appearance.system.rawValue
    @AppStorage(SettingsKeys.defaultView) private var viewMode = "grid"
    @AppStorage(SettingsKeys.trayMenuBarIcon) private var trayIcon = true
    @AppStorage(SettingsKeys.trayShowWhileDragging) private var trayWhileDragging = true
    @AppStorage(SettingsKeys.trayIdleSeconds) private var trayIdle = 30
    @AppStorage(SettingsKeys.trayBorder) private var trayBorder = TrayBorder.accent.rawValue
    var body: some View {
        Form {
            Section {
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
            }
            // macOS chooses an app's language: say which one is in use and keep the how-to folded
            // away until someone wants it (#162). No in-app picker, since Stow can't switch itself.
            Section {
                LabeledContent("App Language", value: Self.languageName)
                DisclosureGroup("How to change the language") {
                    Text("To use English or Simplified Chinese just for Stow, open System Settings → General → Language & Region → Applications. Add Stow and choose its language. Quit and reopen Stow after your current tasks and unsaved changes are finished.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
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

    /// The language Stow is showing, named the way macOS lists it in the current language.
    private static var languageName: String {
        let code = Bundle.main.preferredLocalizations.first ?? "en"
        return Locale.current.localizedString(forIdentifier: code) ?? code
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
    @AppStorage("PackCPUCores") private var cores = 0
    @AppStorage("PackAudience") private var audience = Audience.windows.rawValue
    @AppStorage("PackVerify") private var verify = false
    @AppStorage(SettingsKeys.volumeSize) private var volume = 0
    /// The Pack sheet's part-size editor, popping out of this menu (#153).
    @State private var editingCustom = false

    private var current: SplitSize { SplitSize.stored(Int64(volume)) }
    /// The Custom… item's tag: no real size is negative.
    private static let customTag = -1

    var body: some View {
        Form {
            Section {
                Picker("Pack for", selection: $audience) {
                    ForEach(Audience.allCases) { item in Text(item.phrase.sentenceCased).tag(item.rawValue) }
                }
            }
            Section("Compression level for each destination") {
                ForEach(Audience.allCases) { item in LevelSetting(audience: item) }
            }
            // What comes out, then how hard the Mac works on it: the order of the Pack sheet's More Options.
            Section {
                Picker("Split archives", selection: volumeSelection) {
                    ForEach(SplitSize.allCases) { item in Text(item.phrase.sentenceCased).tag(Int(item.rawValue)) }
                    if current.isCustom {
                        Text(current.phrase.sentenceCased).tag(Int(current.rawValue))
                    }
                    Divider()
                    Text("Custom…").tag(Self.customTag)
                }
                .popover(isPresented: $editingCustom, arrowEdge: .trailing) {
                    SplitSizeEditor(initial: current) { volume = Int($0.rawValue) }
                }
                Toggle("Check archives after packing", isOn: $verify)
                Picker("CPU cores for packing", selection: $cores) {
                    Text("All").tag(0)
                    ForEach(1...ProcessInfo.processInfo.activeProcessorCount, id: \.self) { Text("\($0)").tag($0) }
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Presets and the custom size in use pick themselves; Custom… opens the editor and leaves the
    /// menu on what's in use until the editor's Use.
    private var volumeSelection: Binding<Int> {
        Binding(
            get: { volume },
            set: { chosen in
                if chosen == Self.customTag { editingCustom = true } else { volume = chosen }
            }
        )
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
        Form {
            Section {
                Toggle("Show previews when hovering over files", isOn: $hover)
            } footer: {
                Text("Rest the pointer on a file in the Browser to see a larger preview beside it. Space opens Quick Look either way.")
            }
        }
        .formStyle(.grouped)
    }
}

/// Settings › Glance (#162): whether Finder opens archives in Glance, and how its window looks.
/// The keys and their defaults are the ones General held before.
struct GlanceSettingsView: View {
    @AppStorage(SettingsKeys.openInGlance) private var openInGlance = false
    @AppStorage(SettingsKeys.glanceColourfulControls) private var colourfulControls = false
    @AppStorage(SettingsKeys.glanceMaterial) private var material = SettingsKeys.GlanceMaterialPreference.liquidGlass.rawValue
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Form {
            Section {
                Toggle("Open archives from Finder and Quick Look in Glance", isOn: $openInGlance)
            } footer: {
                Text("When this is off, they open in the full Browser window. Glance is the Browser made small, for a quick look or Extract All. Window › Switch to Glance (⌥⌘G) moves an open archive between the two.")
            }
            Section {
                Picker("Window material", selection: $material) {
                    ForEach(SettingsKeys.GlanceMaterialPreference.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Toggle(isOn: $colourfulControls) {
                    Text("Colourful window controls")
                    Text("Use red for Close, yellow for Pin on Top, and green for Open in Full Window")
                }
            } header: {
                Text("Appearance")
            } footer: {
                // The choice is kept either way; the system setting only wins while it's on.
                if reduceTransparency {
                    Text("Reduce Transparency is on, so Glance uses a solid window whichever material you choose.")
                } else {
                    Text("Liquid Glass is the default. Classic frosted uses a traditional material. Reduce Transparency always uses a solid window.")
                }
            }
        }
        .formStyle(.grouped)
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
    @State private var confirmsResetAll = false
    @State private var confirmsResetPage = false
    /// Page whose preferences "Reset This Page" clears (#162). Defaults to General.
    @State private var pageToReset: SettingsPane = .general
    private var busy: Bool { app.isBusy }
    private var resettablePages: [SettingsPane] {
        SettingsPane.allCases.filter { !SettingsKeys.resettableEntries(for: $0).isEmpty }
    }
    var body: some View {
        Form {
            // Each action sits on the row it acts on, beside what it acts on (#162).
            Section("Temporary files") {
                LabeledContent("Preview cache") {
                    HStack(spacing: Space.m) {
                        Text(usedBytes.bytes)
                            .monospacedDigit()
                        Button("Clean Up") {
                            guard !busy else { return }
                            PreviewCache.cleanUp()
                            usedBytes = PreviewCache.directoryBytes
                        }
                        .disabled(busy)
                    }
                }
            }
            Section {
                LabeledContent("Page") {
                    HStack(spacing: Space.m) {
                        Picker("Page", selection: $pageToReset) {
                            ForEach(resettablePages) { pane in
                                Text(pane.title).tag(pane)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        Button("Reset This Page…", role: .destructive) { confirmsResetPage = true }
                            .disabled(SettingsKeys.resettableEntries(for: pageToReset).isEmpty)
                    }
                }
                LabeledContent("Every page") {
                    Button("Reset All Preferences…", role: .destructive) { confirmsResetAll = true }
                }
            } header: {
                Text("Reset")
            } footer: {
                Text("Reset This Page clears only that page’s preferences. Reset All restores every Stow preference. File types keep their previous apps so you can still switch back. Folder permissions, Keychain passwords and login items are managed separately.")
            }
        }
        .formStyle(.grouped)
        .onAppear { usedBytes = PreviewCache.directoryBytes }
        .alert("Reset this page’s preferences?", isPresented: $confirmsResetPage) {
            Button("Cancel", role: .cancel) {}
            Button("Reset Page", role: .destructive) {
                SettingsKeys.reset(.pane(pageToReset), in: .standard)
                if pageToReset == .integration { IntegrationSettings.shared.reloadPreferences() }
                if pageToReset == .general {
                    AppUpdater.shared.reload()
                    SettingsAppearance.apply()
                }
            }
        } message: {
            Text("Restore this page to its defaults. Other pages, archives, folder grants and remembered previous apps are kept.")
        }
        .alert("Reset all preferences?", isPresented: $confirmsResetAll) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                SettingsKeys.reset(.all, in: .standard)
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
