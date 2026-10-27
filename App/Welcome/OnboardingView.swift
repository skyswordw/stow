import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var associations = Associations()
    @State private var integration = IntegrationSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            Text("Welcome to Stow")
                .font(.title.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: Space.l) {
                ForEach(OnboardingStep.allCases) { step in
                    HStack(alignment: .top, spacing: Space.m) {
                        Image(systemName: step.systemImage)
                            .font(.title2)
                            .foregroundStyle(.tint)
                            .frame(width: 28)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: Space.xs) {
                            Text(step.title).font(.headline).accessibilityAddTraits(.isHeader)
                            Text(detail(for: step))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if step == .archives {
                                VStack(alignment: .leading, spacing: Space.xs) {
                                    Text("Preview without extracting")
                                    Text("Extract safely")
                                    Text("Pack for Windows, Mac, Linux and the web")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            action(for: step)
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Skip", action: finish).buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                Button("Get Started", action: finish)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.xl)
        .frame(width: 560)
        .fixedSize(horizontal: true, vertical: true)
        .onAppear(perform: refresh)
        // Closing the window counts as skipping: it never comes back by itself (Help › Welcome to Stow does).
        .onDisappear { Onboarding.markCompleted() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    private func detail(for step: OnboardingStep) -> String {
        switch step {
        case .fileTypes:
            let names = associations.rows.filter { $0.type.suggested && $0.opensWithStow }.map(\.type.name)
            return Onboarding.fileTypeSummary(names)
        case .finder:
            return integration.finderExtensionEnabled
                ? String(localized: "Finder menu is on") : String(localized: "Finder menu is off")
        default: return step.detail
        }
    }

    @ViewBuilder private func action(for step: OnboardingStep) -> some View {
        switch step {
        case .archives:
            Button("Try the Sample") {
                app.openArchive(named: SampleArchive.make().name)
                app.showMainWindow()
            }
        case .fileTypes:
            Button("Choose File Types…") { showSettings(.fileTypes) }
        case .finder:
            Button("Integration Settings…") { showSettings(.integration) }
        case .tray:
            Button("Show Tray") { app.tray.show() }
        }
    }

    private func showSettings(_ pane: SettingsPane) {
        SettingsRouter.shared.show(pane)
    }

    private func refresh() {
        associations.refresh()
        integration.refresh()
    }

    private func finish() {
        Onboarding.markCompleted()
        dismissWindow(id: "onboarding")
    }
}
