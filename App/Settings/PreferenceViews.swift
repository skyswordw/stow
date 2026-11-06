import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage(SettingsKeys.appearance) private var appearance = SettingsKeys.Appearance.system.rawValue
    @AppStorage(SettingsKeys.defaultView) private var viewMode = "grid"
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
                // Round the row: the disclosure's own ring sat over the chevron and cut through "How".
                .focusRing(in: RoundedRectangle(cornerRadius: 6, style: .continuous))
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
            Section("Compression level for each recipient preset") {
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
                Toggle("Verify archive contents after packing", isOn: $verify)
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

/// Settings › Glance (#162): which window archives open in (the last one used, the full Browser or
/// Glance) and how Glance looks. The appearance keys and their defaults are the ones General held before.
struct GlanceSettingsView: View {
    @AppStorage(SettingsKeys.archiveWindowMode) private var archiveWindowMode = SettingsKeys.archiveWindowMode().rawValue
    @AppStorage(SettingsKeys.glanceColourfulControls) private var colourfulControls = false
    @AppStorage(SettingsKeys.glanceMaterial) private var material = SettingsKeys.GlanceMaterialPreference.liquidGlass.rawValue
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Form {
            Section {
                Picker("Open archives in", selection: $archiveWindowMode) {
                    ForEach(SettingsKeys.ArchiveWindowMode.allCases) { Text($0.title).tag($0.rawValue) }
                }
            } footer: {
                Text("Last Used Window opens archives in whichever window you used last — the full Browser or Glance — even after Stow quits. Window › Switch to Glance (⌥⌘G) moves an open archive between the two.")
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
                if DisplayPreferences.reducesTransparency(reduceTransparency) {
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
                        // Listed like folder permissions (#162): the archive's name over its folder.
                        ForEach(entries) { entry in
                            SavedItemRow(name: entry.displayName, file: entry.identity.path, symbol: "lock.doc") {
                                Button("Forget", role: .destructive) {
                                    ArchivePasswordVault.forget(entry)
                                    reload()
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

/// Settings › Tray (#288): the master switch first, with what it means for closing Stow's last
/// window, then how the Tray comes out and goes away, then how it looks. Everything under the
/// switch dims while it's off and keeps its value for when it's turned back on. The switch goes
/// through `TrayController`, the one owner of `tray.enabled`. No idle timer: the user chose
/// outside-click dismissal and the pin instead (#286), so nothing here counts time.
struct TraySettingsView: View {
    @Environment(AppState.self) private var app
    @AppStorage(SettingsKeys.trayMenuBarIcon) private var trayIcon = true
    @AppStorage(SettingsKeys.trayShowWhileDragging) private var trayWhileDragging = true
    @AppStorage(SettingsKeys.trayBorder) private var trayBorder = TrayBorder.accent.rawValue

    private var isEnabled: Bool { app.tray.isEnabled }
    private var enabled: Binding<Bool> {
        Binding(get: { app.tray.isEnabled }, set: { app.tray.setEnabled($0) })
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: enabled) {
                    Text("Enable Tray")
                    Text("Gather files from anywhere to pack, extract or collect into a folder")
                }
            } footer: {
                // What the switch means once Stow's windows are closed (#289), said for the state it's in.
                if isEnabled {
                    Text("When you close Stow’s last window, Stow keeps running without a Dock icon so the Tray stays ready. To open Stow when you log in, use Finder & Permissions.")
                } else {
                    Text("When you close Stow’s last window, Stow quits once its work finishes. To open Stow when you log in, use Finder & Permissions.")
                }
            }
            Section {
                Toggle(isOn: $trayIcon) {
                    Text("Show Tray icon in the menu bar")
                    Text("Click it to show or hide the Tray. Control-click it for Stow’s menu.")
                }
                // Dragging files anywhere else leaves the Tray alone (#180); say where to take them.
                Toggle(isOn: $trayWhileDragging) {
                    Text("Show Tray when files are dragged to it")
                    if trayIcon {
                        Text("Drag files up to the Tray icon in the menu bar.")
                    } else {
                        Text("Drag files to the right edge of the screen.")
                    }
                }
                // Fixed, so it's shown rather than edited: Window › Show Tray uses it.
                LabeledContent {
                    Text(verbatim: "⌥⌘T")
                } label: {
                    Text("Show or hide the Tray")
                    Text("While Stow is in front. It’s also in the Window menu.")
                }
            } header: {
                Text("Showing and Hiding")
            } footer: {
                VStack(alignment: .leading, spacing: Space.m) {
                    // With neither icon nor drag reveal, the shortcut is the only way out: say so.
                    if !trayIcon && !trayWhileDragging {
                        Text("With the icon and dragging both off, show the Tray with ⌥⌘T.")
                    }
                    // Keep Tray Open has no setting of its own (#282): say what happens, and where the pin is.
                    Text("The Tray hides when you click elsewhere or switch apps. Its pin keeps it open until you close it.")
                }
            }
            .dependsOnTray(isEnabled)
            Section {
                Picker("Border colour", selection: $trayBorder) {
                    ForEach(TrayBorder.allCases) { border in
                        Label { Text(border.title) } icon: {
                            Image(systemName: "circle.fill").foregroundStyle(border.color)
                        }
                        .tag(border.rawValue)
                    }
                }
            } header: {
                Text("Appearance")
            }
            .dependsOnTray(isEnabled)
        }
        .formStyle(.grouped)
    }
}

private extension View {
    /// Rows that only matter while Tray is on: disabled, and their words dimmed too, since a grouped
    /// form greys a disabled switch but leaves its title at full strength.
    /// Only off sets a style: any style set while on would flatten the subtitles and footer to primary.
    @ViewBuilder func dependsOnTray(_ enabled: Bool) -> some View {
        if enabled {
            self
        } else {
            disabled(true).foregroundStyle(.tertiary)
        }
    }
}
