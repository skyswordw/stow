import SwiftUI

/// Actions (#161): the selection's actions as a stack of floating glass buttons. The front one is
/// what this selection is most likely for — installing, for an app, fonts or an installer package,
/// otherwise Extract — and the others wait behind it with their edges showing. With nothing
/// selected, an archive that's one app offers installing it, alone (as ArcZip does). Pointing at the
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
        } else if model.selection.isEmpty {
            // Nothing selected: the archive's own step, installing its one app, run on just that
            // app. Alone: Extract All is beside it, and its help tag names the app.
            if let target = model.archiveTarget,
               let front = NextStepsSettings(hidden: NextStepsSettings.decode(hidden)).archiveLayout(installable: target).front {
                ActionStack(front: front, behind: [], selection: model.selection, scope: target.name,
                            isOpen: Binding { model.isActionStackOpen } set: { model.isActionStackOpen = $0 },
                            glass: glass) { step in
                    model.run(step, on: [target])
                }
                .fixedSize()
            }
        } else {
            let layout = NextStepsSettings(hidden: NextStepsSettings.decode(hidden))
                .layout(for: entries, dropTargets: model.archive.dropTargets)
            HStack(alignment: .bottom, spacing: Space.s) {
                NextStepsMoreMenu(model: model, alternatives: layout.more)
                if let front = layout.front {
                    ActionStack(front: front, behind: layout.behind, selection: model.selection,
                                scope: entries.count == 1 ? entries[0].name : String(localized: "\(entries.count) items"),
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
///
/// Everything that takes the pointer is part of the stack's own layout, never drawn outside its
/// frame: the strip with the edges above the front button, and the choices once they fan out. The
/// stack grows upward to hold them and the row keeps its bottom edge.
private struct ActionStack: View {
    let front: NextStep
    let behind: [NextStep]
    /// A new selection folds the stack again.
    let selection: Set<ArchiveEntry.ID>
    /// What the actions apply to ("notes.txt", "3 items"), for their help tags: the buttons don't
    /// repeat it, Details shows it, and the tag answers "on what?" right where the pointer is.
    let scope: String
    /// Fanned out: by the pointer resting on it or a click on its edges. The model holds it so the
    /// window's Esc can fold it first.
    @Binding var isOpen: Bool
    let glass: Namespace.ID
    let run: (NextStep) -> Void

    @State private var pointerTask: Task<Void, Never>?
    @State private var watchTask: Task<Void, Never>?
    @State private var isPointedAt = false
    /// The stack's frame in the window, to check the pointer against.
    @State private var frameInWindow: CGRect = .zero
    /// The fanned-out action under the pointer. SwiftUI's hover doesn't reach buttons that appear
    /// inside the stack as it grows, so the stack lights them from where the pointer is.
    @State private var pointedChoice: NextStep?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Two edges show at most; the rest are as easy to reach from More.
    private var edges: Int { min(behind.count, 2) }
    private static let gap: CGFloat = Space.s
    /// The edges show 4–9 pt above the front button; the strip that opens the stack is a little taller.
    private static let edgeStrip: CGFloat = 14

    var body: some View {
        VStack(spacing: 0) {
            if isOpen {
                // The other actions, nearest the front button at the bottom.
                ForEach(Array(behind.enumerated()).reversed(), id: \.element) { index, step in
                    Button(step.title, systemImage: step.symbol) { fold(); run(step) }
                        .buttonStyle(StackButtonStyle(prominent: false, highlighted: pointedChoice == step))
                        .accessibilityLabel(step.title)
                        .padding(.bottom, Self.gap)
                        .transition(rise(from: index))
                        .help(String(localized: "\(step.title): \(scope)"))
                }
            } else if edges > 0 {
                edgeStrip
            }
            frontButton
                .background(alignment: .top) {
                    if !isOpen { edgesView.transition(.opacity) }
                }
                .onContinuousHover(perform: arrival)
        }
        .fixedSize()
        // The pointer arrives over the front button or the edges (`arrival`). Once it's here,
        // leaving is decided by where it really is against the stack's whole frame, gaps included:
        // after the stack grows under it, SwiftUI's hover reports the pointer gone at its next
        // move while it's still on the stack. No hover handler sits over the choices, so they keep
        // their own highlight and help tags.
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frameInWindow = $0 }
        .onKeyPress(.escape) {
            guard isOpen else { return .ignored }
            setOpen(false)
            return .handled
        }
        .onChange(of: selection) { fold() }
        .onDisappear {
            pointerTask?.cancel()
            watchTask?.cancel()
            isOpen = false
        }
        .task {
            guard NextStepsDemo.opensStack else { return }
            try? await Task.sleep(for: .milliseconds(600))
            setOpen(true)
        }
    }

    private var frontButton: some View {
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
                .help(String(localized: "\(front.title): \(scope)"))
                .glassEffectID("summary", in: glass)
        }
    }

    /// What takes the click on the edges: the strip above the front button and nothing of the
    /// front button itself, so a click or an accessibility press aimed at its middle can never land
    /// on the front action instead.
    private var edgeStrip: some View {
        Button {
            setOpen(true)
        } label: {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: Self.edgeStrip)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onContinuousHover(perform: arrival)
        .accessibilityLabel(String(localized: "Show All Actions"))
        .accessibilityHint(String(localized: "Shows the other actions for the selection above this one"))
        .help(String(localized: "Show all actions"))
    }

    /// The edges of the buttons behind the front one, a little narrower each step back, like a
    /// stack of cards. Drawing only: the strip above takes the click.
    private var edgesView: some View {
        ZStack(alignment: .top) {
            ForEach((0..<edges).reversed(), id: \.self) { depth in
                StackEdge(depth: depth)
                    .scaleEffect(1 - 0.07 * CGFloat(depth + 1), anchor: .top)
                    .offset(y: -CGFloat(depth + 1) * 4.5)
            }
        }
        .allowsHitTesting(false)
    }

    /// Up from behind the front button (`index` steps away), with the system's fade under Reduce Motion.
    private func rise(from index: Int) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        let distance = CGFloat(index + 1) * (StackButtonStyle.height + Self.gap)
        return .asymmetric(
            insertion: .offset(y: distance).combined(with: .scale(scale: 0.9, anchor: .top)).combined(with: .opacity),
            removal: .offset(y: distance * 0.6).combined(with: .opacity))
    }

    /// Where the pointer is in the window, from the window's own idea of it (top-left origin, like
    /// the stack's frame).
    private var pointerInWindow: CGPoint? {
        guard let window = NSApp.keyWindow, let content = window.contentView else { return nil }
        var point = content.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        if !content.isFlipped { point.y = content.bounds.height - point.y }
        return point
    }

    private var pointerIsOverStack: Bool {
        pointerInWindow.map(frameInWindow.contains) ?? false
    }

    /// The fanned-out action at a point: rows of button + gap from the top, the front button last.
    private func choice(at point: CGPoint?) -> NextStep? {
        guard isOpen, let point, frameInWindow.contains(point) else { return nil }
        let row = StackButtonStyle.height + Self.gap
        let y = point.y - frameInWindow.minY
        let index = Int(y / row)
        guard y.truncatingRemainder(dividingBy: row) < StackButtonStyle.height, index < behind.count else { return nil }
        return behind.reversed()[index]
    }

    private func arrival(_ phase: HoverPhase) {
        if case .active = phase { pointer(inside: true) } else { pointer(inside: pointerIsOverStack) }
    }

    private func pointer(inside: Bool) {
        guard inside != isPointedAt else { return }
        isPointedAt = inside
        pointerMoved()
        watchTask?.cancel()
        guard inside else {
            pointedChoice = nil
            return
        }
        // SwiftUI may not say when the pointer leaves, so look now and then while it's here, and
        // light the action under it.
        watchTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
                let point = pointerInWindow
                let pointed = choice(at: point)
                if pointed != pointedChoice { pointedChoice = pointed }
                if !(point.map(frameInWindow.contains) ?? false) { return pointer(inside: false) }
            }
        }
    }

    /// Pointing at the stack opens it after a moment, so passing over doesn't flicker it (ArcZip's
    /// opens at once and flashes on every pass). Leaving closes it after a longer moment, so a
    /// pointer that overshoots and comes back finds it still open (ArcZip lingers 0.5–1 s).
    private func pointerMoved() {
        guard !behind.isEmpty else { return }
        let inside = isPointedAt
        pointerTask?.cancel()
        pointerTask = Task {
            try? await Task.sleep(for: .milliseconds(inside ? 140 : 450))
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
    /// Lit as if under the pointer, for buttons the stack tracks itself.
    var highlighted = false

    func makeBody(configuration: Configuration) -> some View {
        StackLabel(label: configuration.label, prominent: prominent, isPressed: configuration.isPressed,
                   highlighted: highlighted)
    }
}

/// The stack's button contents. Also measured hidden, with a step's own label, to size the stack.
private struct StackLabel<L: View>: View {
    let label: L
    var prominent = false
    var isPressed = false
    var highlighted = false
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
                            Capsule().fill(isPressed ? Color.black.opacity(0.16) : Color.white.opacity(isLit ? 0.1 : 0))
                        }
                } else {
                    Capsule().fill(.primary.opacity(isPressed ? 0.16 : isLit ? 0.1 : 0))
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

    private var isLit: Bool { isHovering || highlighted }
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
