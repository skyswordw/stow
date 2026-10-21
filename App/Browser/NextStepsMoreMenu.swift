import SwiftUI

/// The capsule's ⋯ button: every other step that applies to the selection, with the icons and
/// shortcuts the menu bar uses, then a way to choose what the capsule suggests.
struct NextStepsMoreMenu: View {
    let model: BrowserModel
    let alternatives: [NextStep]
    /// A large glass button's height.
    private static let size: CGFloat = 28

    var body: some View {
        Menu {
            NextStepsMoreItems(model: model, alternatives: alternatives)
        } label: {
            Image(systemName: "ellipsis")
                .fontWeight(.medium)
                .frame(width: Self.size, height: Self.size)
                .contentShape(.circle)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        // A Menu doesn't take the glass button style; this is the same glass, the same height
        // as the capsule's large buttons.
        .glassEffect(.regular.interactive(), in: .circle)
        .help("More actions for the selection")
        .accessibilityLabel("More actions")
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
        Button("Customize Next Steps…", systemImage: "slider.horizontal.3") {
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
