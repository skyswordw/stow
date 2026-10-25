import SwiftUI

/// Actions (#161): the selection's actions as a stack of floating glass buttons. The front one is
/// what this selection is most likely for — installing, for an app, fonts or an installer package,
/// otherwise Extract — and the others wait behind it with their edges showing. Pointing at the
/// stack or clicking its edges fans them out above it; More (⋯) lists every action as a menu, which
/// is also the keyboard's way to all of them. Pointing only reveals: every action takes a click.
/// What the actions apply to is Details' job, so nothing here repeats the selection's name.
/// While a step runs, the front button morphs into its progress capsule in place.
/// (Internal names keep "Next Steps": the feature's settings keys and types predate the rename.)
struct NextStepsBar: View {
    let model: BrowserModel
    @Namespace private var glass
    @AppStorage(SettingsKeys.nextStepsHidden) private var hidden = NextStepsSettings.encode(NextStepsSettings.defaultHidden)

    var body: some View {
        GlassEffectContainer(spacing: Space.xs) {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        let entries = model.selectedEntries
        if let activity = model.activity {
            ActivityCapsule(phase: activity.phase,
                            title: activity.phase == .done ? activity.doneTitle
                                : activity.step.progressTitle(itemCount: activity.itemCount, name: activity.name),
                            glass: glass,
                            stop: model.archive.source != nil ? { model.cancelActivity() } : nil,
                            stopHelp: String(localized: "Stop — nothing is left half-extracted"),
                            showInFinder: activity.placed.isEmpty ? nil : { model.showInFinder() },
                            perform: { model.follow($0) },
                            dismiss: { model.dismissActivity() })
        } else if entries.isEmpty, !model.selection.isEmpty {
            // Search results inside other archives: the one thing to do is go there.
            NestedResultAction(model: model, glass: glass)
        } else {
            let layout = NextStepsSettings(hidden: NextStepsSettings.decode(hidden))
                .layout(for: entries, dropTargets: model.archive.dropTargets)
            HStack(alignment: .bottom, spacing: Space.s) {
                NextStepsMoreMenu(model: model, alternatives: layout.more)
                if let front = layout.front {
                    ActionStack(front: front, behind: layout.behind, selection: model.selection,
                                isOpen: Binding { model.isActionStackOpen } set: { model.isActionStackOpen = $0 },
                                glass: glass) { step in
                        if step == .quickLook { model.toggleQuickLook() } else { model.run(step) }
                    }
                }
            }
            .fixedSize()
        }
    }
}

/// The front action with the others stacked behind it. The stack is as wide as its widest label,
/// so the buttons line up when they fan out; the ones behind rise from under the front button and
/// sink back into it.
private struct ActionStack: View {
    let front: NextStep
    let behind: [NextStep]
    /// A new selection folds the stack again.
    let selection: Set<ArchiveEntry.ID>
    /// Fanned out: by the pointer resting on it or a click on its edges. The model holds it so the
    /// window's Esc can fold it first.
    @Binding var isOpen: Bool
    let glass: Namespace.ID
    let run: (NextStep) -> Void

    @State private var pointerTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Two edges show at most; the rest are as easy to reach from More.
    private var edges: Int { min(behind.count, 2) }
    private static let gap: CGFloat = Space.s

    var body: some View {
        ZStack {
            // The widest label sets the width of every button in the stack.
            ForEach([front] + behind) { step in
                StackLabel(step: step).hidden()
            }
            Button(front.title, systemImage: front.symbol) { fold(); run(front) }
                .buttonStyle(StackButtonStyle(prominent: true))
                // ⌘E as in File › Extract; the others keep their menu-bar keys.
                .keyboardShortcut(front == .extract ? front.menuShortcut : nil)
                .accessibilityLabel(front.title)
                .glassEffectID("summary", in: glass)
        }
        .fixedSize()
        .background(alignment: .bottom) {
            ZStack(alignment: .bottom) {
                if !isOpen { edgesView.transition(.opacity) }
                if isOpen { choices }
            }
        }
        .onHover { pointer(inside: $0) }
        .onKeyPress(.escape) {
            guard isOpen else { return .ignored }
            setOpen(false)
            return .handled
        }
        .onChange(of: selection) { fold() }
        .onDisappear {
            pointerTask?.cancel()
            isOpen = false
        }
        .task {
            guard NextStepsDemo.opensStack else { return }
            try? await Task.sleep(for: .milliseconds(600))
            setOpen(true)
        }
    }

    /// The edges of the buttons behind the front one, a little narrower each step back, like a
    /// stack of cards. Clicking them fans the stack out.
    @ViewBuilder
    private var edgesView: some View {
        if edges > 0 {
            ZStack(alignment: .bottom) {
                ForEach((0..<edges).reversed(), id: \.self) { depth in
                    StackEdge(depth: depth)
                        .scaleEffect(1 - 0.07 * CGFloat(depth + 1), anchor: .top)
                        .offset(y: -CGFloat(depth + 1) * 4.5)
                }
                // What takes the click: the strip above the front button and nothing of the front
                // button itself, so a click or an accessibility press aimed at the middle of this
                // control can never land on the front action instead.
                VStack(spacing: 0) {
                    Button {
                        setOpen(true)
                    } label: {
                        Color.clear
                            .frame(height: Self.edgeStrip)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "Show All Actions"))
                    .accessibilityHint(String(localized: "Shows the other actions for the selection above this one"))
                    .help(String(localized: "Show all actions"))
                    Color.clear
                        .frame(height: StackButtonStyle.height)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    /// The edges show 4–9 pt above the front button; the strip that opens the stack is a little taller.
    private static let edgeStrip: CGFloat = 14

    /// The other actions, nearest the front button at the bottom. They rise out from under it.
    private var choices: some View {
        VStack(spacing: Self.gap) {
            ForEach(Array(behind.enumerated()).reversed(), id: \.element) { index, step in
                Button(step.title, systemImage: step.symbol) { fold(); run(step) }
                    .buttonStyle(StackButtonStyle(prominent: false))
                    .accessibilityLabel(step.title)
                    .transition(rise(from: index))
            }
            // Room for the front button the choices sit on.
            Color.clear
                .frame(height: StackButtonStyle.height)
                .accessibilityHidden(true)
        }
        .onHover { pointer(inside: $0) }
    }

    /// Up from behind the front button (`index` steps away), with the system's fade under Reduce Motion.
    private func rise(from index: Int) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        let distance = CGFloat(index + 1) * (StackButtonStyle.height + Self.gap)
        return .asymmetric(
            insertion: .offset(y: distance).combined(with: .scale(scale: 0.9, anchor: .top)).combined(with: .opacity),
            removal: .offset(y: distance * 0.6).combined(with: .opacity))
    }

    /// Pointing at the stack opens it after a moment, so passing over doesn't flicker it; leaving
    /// closes it after a moment, so crossing the gap between buttons doesn't either.
    private func pointer(inside: Bool) {
        guard !behind.isEmpty else { return }
        pointerTask?.cancel()
        pointerTask = Task {
            try? await Task.sleep(for: .milliseconds(inside ? 140 : 280))
            guard !Task.isCancelled else { return }
            setOpen(inside)
        }
    }

    private func setOpen(_ open: Bool) {
        guard open != isOpen, !behind.isEmpty || !open else { return }
        withAnimation(Motion.presence(open, reduceMotion: reduceMotion)) { isOpen = open }
    }

    /// Closes at once, without motion: an action was chosen or the selection moved on.
    private func fold() {
        pointerTask?.cancel()
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { isOpen = false }
    }
}

/// A stacked action: a glass capsule around a pill holding the label. The front action's pill is
/// filled with the accent; the others light up under the pointer.
private struct StackButtonStyle: ButtonStyle {
    static let height: CGFloat = ActionButtonStyle.height + 2 * ActionButtonStyle.inset
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        StackLabel(label: configuration.label, prominent: prominent, isPressed: configuration.isPressed)
    }
}

/// The stack's button contents. Also measured hidden, with a step's own label, to size the stack.
private struct StackLabel<L: View>: View {
    let label: L
    var prominent = false
    var isPressed = false
    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        label
            .labelStyle(.titleAndIcon)
            .font(.body.weight(prominent ? .semibold : .medium))
            .lineLimit(1)
            .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, Space.l)
            .frame(minWidth: 116, maxWidth: .infinity, minHeight: ActionButtonStyle.height)
            .background {
                if prominent {
                    Capsule()
                        .fill(Color.accentColor)
                        .overlay {
                            Capsule().fill(isPressed ? Color.black.opacity(0.16) : Color.white.opacity(isHovering ? 0.1 : 0))
                        }
                } else {
                    Capsule().fill(.primary.opacity(isPressed ? 0.14 : isHovering ? 0.07 : 0))
                }
            }
            .overlay {
                // Increase Contrast outlines the primary, so it reads by shape as well as by colour.
                if prominent, ContrastStyle.resolve(contrast).increased {
                    Capsule().strokeBorder(.primary.opacity(0.45))
                }
            }
            .padding(ActionButtonStyle.inset)
            .accessibleGlass(in: .capsule)
            .contentShape(.capsule)
            .onHover { isHovering = $0 }
            .opacity(isEnabled ? 1 : 0.45)
    }
}

extension StackLabel where L == Label<Text, Image> {
    init(step: NextStep) {
        self.init(label: Label(step.title, systemImage: step.symbol), prominent: true)
    }
}

/// One edge in the stack: the top of a button waiting behind the front one. Not glass — glass
/// can't sit on glass — but a material with the same hairline rim, so it reads as the same family.
private struct StackEdge: View {
    let depth: Int
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Capsule()
            .fill(reduceTransparency ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor)) : AnyShapeStyle(.regularMaterial))
            .overlay {
                Capsule().fill(Color.accentColor.opacity(depth == 0 ? 0.28 : 0.16))
            }
            .overlay {
                Capsule().strokeBorder(ContrastStyle.resolve(contrast).increased ? AnyShapeStyle(.primary.opacity(0.45))
                                       : AnyShapeStyle(.white.opacity(0.18)), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
            .frame(height: StackButtonStyle.height)
            .accessibilityHidden(true)
    }
}

/// Plain buttons inside a glass capsule (the archive's controls, navigation): a quiet fill under the
/// pointer, and a primary action filled with the accent, concentric with the capsule around it.
struct ActionButtonStyle: ButtonStyle {
    /// The capsule's padding around its buttons; button radius + inset = capsule radius.
    static let inset: CGFloat = 4
    static let height: CGFloat = 30

    var prominent = false
    var iconOnly = false
    var height: CGFloat = Self.height

    func makeBody(configuration: Configuration) -> some View {
        ActionButtonBody(configuration: configuration, prominent: prominent, iconOnly: iconOnly, height: height)
    }
}

private struct ActionButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    let iconOnly: Bool
    let height: CGFloat
    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        configuration.label
            .font(.body.weight(prominent ? .semibold : .regular))
            .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, iconOnly ? 0 : Space.m)
            .frame(minWidth: height, minHeight: height)
            .background { background }
            .overlay {
                // Increase Contrast outlines the primary, so it reads by shape as well as by colour.
                if prominent, ContrastStyle.resolve(contrast).increased {
                    Capsule().strokeBorder(.primary.opacity(0.45))
                }
            }
            .contentShape(.capsule)
            .onHover { isHovering = $0 && isEnabled }
            .opacity(isEnabled ? 1 : 0.4)
    }

    @ViewBuilder private var background: some View {
        if prominent {
            Capsule()
                .fill(Color.accentColor)
                .overlay {
                    Capsule().fill(configuration.isPressed ? Color.black.opacity(0.16)
                                   : Color.white.opacity(isHovering ? 0.1 : 0))
                }
        } else {
            Capsule().fill(.primary.opacity(configuration.isPressed ? 0.14 : isHovering ? 0.07 : 0))
        }
    }
}

/// A search result inside an inner archive: the one action is to go there. A selection of several
/// such results says what to do instead.
private struct NestedResultAction: View {
    let model: BrowserModel
    /// Shared with the regular stack, so it morphs in place like that one does.
    let glass: Namespace.ID

    var body: some View {
        if let hit = model.selectedNestedHit {
            Button(String(localized: "Show in “\(hit.container.name)”"), systemImage: NextStep.openInside.symbol) {
                model.showNested(hit)
            }
            .buttonStyle(StackButtonStyle(prominent: true))
            .accessibilityLabel(String(localized: "Show in “\(hit.container.name)”"))
            .help(String(localized: "Show in “\(hit.container.name)”"))
            .fixedSize()
            .glassEffectID("summary", in: glass)
        } else {
            HStack(spacing: 6) {
                Text("\(model.selection.count) items")
                    .fontWeight(.medium)
                    .liveNumber()
                Text("inside other archives — select one to show it")
                    .foregroundStyle(.secondary)
            }
                .font(.callout)
                .lineLimit(1)
                .fixedSize()
                .accessibilityElement(children: .combine)
                .frame(minHeight: StackButtonStyle.height)
                .padding(.horizontal, Space.l)
                .accessibleGlass(in: .capsule)
                .glassEffectID("summary", in: glass)
        }
    }
}
