import SwiftUI

/// Settings › Actions: whether the capsule appears, and which actions it suggests.
struct NextStepsSettingsView: View {
    @AppStorage(SettingsKeys.nextStepsShown) private var isShown = true
    @AppStorage(SettingsKeys.nextStepsHidden) private var hidden = NextStepsSettings.encode(NextStepsSettings.defaultHidden)

    private var settings: NextStepsSettings {
        NextStepsSettings(isShown: isShown, hidden: NextStepsSettings.decode(hidden))
    }

    var body: some View {
        Form {
            Section {
                Toggle("Show Actions when you select something", isOn: $isShown)
            } footer: {
                Text("Actions float above the files you select, with the right one first. When they’re off, every action is still in the menus.")
            }
            Section {
                ForEach(NextStep.Kind.allCases) { kind in
                    Toggle(isOn: binding(for: kind)) {
                        Label {
                            Text(kind.title)
                            Text(kind.when)
                        } icon: {
                            Image(systemName: kind.symbol)
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                                .accessibilityHidden(true)
                        }
                    }
                    .accessibilityLabel(kind.title)
                    .accessibilityHint(kind.when)
                }
                .disabled(!isShown)
            } header: {
                Text("Suggested Actions")
            } footer: {
                VStack(alignment: .leading, spacing: Space.m) {
                    Text("Up to two suggestions appear beside Extract, most specific first. Suggestions you turn off stay in the More menu.")
                    // Also brings Actions back when it's turned off, so it stays enabled.
                    Button("Restore Defaults") { NextStepsSettings.restoreDefaults() }
                        .disabled(settings.isDefault)
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func binding(for kind: NextStep.Kind) -> Binding<Bool> {
        Binding {
            settings.shows(kind)
        } set: { shown in
            var changed = settings
            changed.set(kind, shown: shown)
            hidden = NextStepsSettings.encode(changed.hidden)
        }
    }
}
