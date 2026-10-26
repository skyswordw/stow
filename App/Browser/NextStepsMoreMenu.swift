import SwiftUI

/// Actions' ⋯ button, a glass circle beside the stack: every action for the selection except the
/// front button's, with the icons and shortcuts the menu bar uses, then a way to choose what
/// Actions suggests. The keyboard's way to every action, whether or not the stack is open.
struct NextStepsMoreMenu: View {
    let model: BrowserModel
    let alternatives: [NextStep]

    var body: some View {
        Menu {
            NextStepsMoreItems(model: model, alternatives: alternatives)
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: ActionButtonStyle.height + 2 * ActionButtonStyle.inset,
                       height: ActionButtonStyle.height + 2 * ActionButtonStyle.inset)
                .accessibleGlass(in: .circle, interactive: true)
                .contentShape(.circle)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More actions for the selection")
        .accessibilityLabel("More actions")
        .accessibilityHint("Every other action for the selection, and Customize Actions")
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { NextStepsDemo.moreButtonFrame = $0 }
    }
}

/// The More menu's items, shared with File › Actions and the design-review scene that shows them open.
struct NextStepsMoreItems: View {
    let model: BrowserModel
    let alternatives: [NextStep]
    /// Off in the menu bar, where Extract, Quick Look and Open already have their keys.
    var showsShortcuts = true
    /// What the steps work on when it isn't the selection: the archive's one app, with nothing selected.
    var entries: [ArchiveEntry]?

    var body: some View {
        ForEach(alternatives) { step in
            Button(step.title, systemImage: step.symbol) { run(step) }
                .labelStyle(.titleAndIcon)
                .keyboardShortcut(showsShortcuts ? step.menuShortcut : nil)
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
        if step == .quickLook { model.toggleQuickLook() } else { model.run(step, on: entries) }
    }
}
