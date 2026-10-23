import SwiftUI

/// Settings › Next Steps: whether the capsule appears, and which steps it suggests.
struct NextStepsSettingsView: View {
    @AppStorage(SettingsKeys.nextStepsShown) private var isShown = true
    @AppStorage(SettingsKeys.nextStepsHidden) private var hidden = NextStepsSettings.encode(NextStepsSettings.defaultHidden)

    private var settings: NextStepsSettings {
        NextStepsSettings(isShown: isShown, hidden: NextStepsSettings.decode(hidden))
    }

    var body: some View {
        Form {
            Section {
                Toggle("Show Next Steps when you select something", isOn: $isShown)
            } footer: {
                Text("Next Steps floats above the files you select and offers the right next step. When it’s off, every action is still in the menus.")
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
                Text("Suggested Steps")
            } footer: {
                VStack(alignment: .leading, spacing: Space.m) {
                    Text("Next Steps shows up to two suggestions beside Extract, most specific first. Steps you turn off stay in its More menu.")
                    // Also brings Next Steps back when it's turned off, so it stays enabled.
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
