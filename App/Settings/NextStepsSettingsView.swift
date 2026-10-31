import SwiftUI

/// Settings › Actions: whether the stack appears, what it would hold for a sample selection, and
/// which actions it suggests.
struct NextStepsSettingsView: View {
    @AppStorage(SettingsKeys.nextStepsShown) private var isShown = true
    @AppStorage(SettingsKeys.nextStepsHidden) private var hidden = NextStepsSettings.encode(NextStepsSettings.defaultHidden)
    @State private var example = ActionsExample.photos

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
            // What the toggles below add up to, for a selection people can pick (#162). Read-only
            // words, not buttons: nothing here runs an action.
            Section {
                Picker("When you select", selection: $example) {
                    ForEach(ActionsExample.allCases) { Text($0.title).tag($0) }
                }
                ActionsExampleRows(layout: settings.layout(for: example.entries))
            } header: {
                Text("Preview")
            } footer: {
                Text("Resting the pointer on the stack fans out the actions behind the front one. More (⋯) and File › Actions list every action.")
            }
            .disabled(!isShown)
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

/// Sample selections for the Actions preview: between them they reach the specific steps.
private enum ActionsExample: String, CaseIterable, Identifiable {
    case photos, app, fonts, installer, archive
    var id: Self { self }

    var title: String {
        switch self {
        case .photos: String(localized: "Two photos")
        case .app: String(localized: "An app")
        case .fonts: String(localized: "Two fonts")
        case .installer: String(localized: "An installer package")
        case .archive: String(localized: "An archive")
        }
    }

    var entries: [ArchiveEntry] {
        let paths = switch self {
        case .photos: ["Photos/Lighthouse.jpg", "Photos/Pier at Dawn.jpg"]
        case .app: ["Harbor Prototype.app"]
        case .fonts: ["Fonts/Harbor Sans.otf", "Fonts/Harbor Serif.ttf"]
        case .installer: ["Harbor Setup.pkg"]
        case .archive: ["Earlier Rounds.zip"]
        }
        return paths.map { ArchiveEntry(path: $0, isFolder: false, size: 1, packedSize: 1, modified: .now) }
    }
}

/// The stack for one selection, in words: the front action, what fans out behind it, what waits in More.
private struct ActionsExampleRows: View {
    let layout: NextStepsSettings.Layout

    var body: some View {
        LabeledContent("In front") {
            if let front = layout.front {
                Label(front.title, systemImage: front.symbol)
                    .foregroundStyle(.tint)
                    .fontWeight(.medium)
            } else {
                Text("Nothing")
            }
        }
        LabeledContent("Behind it", value: Self.list(layout.behind))
        LabeledContent("Only in More (⋯)", value: Self.list(layout.alternatives))
    }

    private static func list(_ steps: [NextStep]) -> String {
        steps.isEmpty ? String(localized: "Nothing") : steps.map(\.title).formatted(.list(type: .and))
    }
}
