import SwiftUI

/// The Actions capsule's ⋯ button: every other action that applies to the selection, with the
/// icons and shortcuts the menu bar uses, then a way to choose what Actions suggests.
struct NextStepsMoreMenu: View {
    let model: BrowserModel
    let alternatives: [NextStep]
    @State private var isHovering = false

    var body: some View {
        Menu {
            NextStepsMoreItems(model: model, alternatives: alternatives)
        } label: {
            Image(systemName: "ellipsis")
                .fontWeight(.medium)
                .frame(width: ActionButtonStyle.height, height: ActionButtonStyle.height)
                // Inside the capsule's glass, so a quiet fill under the pointer like its other buttons.
                .background(.primary.opacity(isHovering ? 0.07 : 0), in: .circle)
                .contentShape(.circle)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { isHovering = $0 }
        .help("More actions for the selection")
        .accessibilityLabel("More actions")
        .accessibilityHint("Every other action for the selection, and Customize Actions")
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { NextStepsDemo.moreButtonFrame = $0 }
    }
}

/// The More menu's items, shared with the design-review scene that shows them open.
struct NextStepsMoreItems: View {
    let model: BrowserModel
    let alternatives: [NextStep]

    var body: some View {
        ForEach(alternatives) { step in
            Button(step.title, systemImage: step.symbol) { run(step) }
                .labelStyle(.titleAndIcon)
                .keyboardShortcut(step.menuShortcut)
        }
        if !alternatives.isEmpty { Divider() }
        // The same symbol as Settings › Actions, so the menu item and the pane read as one feature.
        Button("Customize Actions…", systemImage: SettingsPane.nextSteps.systemImage) {
            SettingsRouter.shared.pane = .nextSteps
            SettingsRouter.shared.open()
        }
        .labelStyle(.titleAndIcon)
    }

    /// A key that's also in the menu bar does exactly what the menu bar does.
    private func run(_ step: NextStep) {
        if step == .quickLook { model.toggleQuickLook() } else { model.run(step) }
    }
}
