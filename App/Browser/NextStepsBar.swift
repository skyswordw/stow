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
                            unavailable: model.actionsUnavailableReason,
                            isOpen: Binding { model.isActionStackOpen } set: { model.isActionStackOpen = $0 },
                            isGrown: Binding { model.isActionStackGrown } set: { model.isActionStackGrown = $0 },
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
                                unavailable: model.actionsUnavailableReason,
                                isOpen: Binding { model.isActionStackOpen } set: { model.isActionStackOpen = $0 },
                                isGrown: Binding { model.isActionStackGrown } set: { model.isActionStackGrown = $0 },
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
    /// Why the actions can't run yet (the archive is still being listed); they show disabled and
    /// their help tags say so, instead of taking a click that does nothing.
    var unavailable: String?
    /// Fanned out: by the pointer resting on it or a click on its edges. The model holds it so the
    /// window's Esc can fold it first.
    @Binding var isOpen: Bool
    /// `isOpen` for the stack's frame, which changes at once rather than with the motion. The
    /// buttons' places don't depend on it; an animated frame laid them all out lower for a moment,
    /// so the others started below the front button instead of behind it.
    @Binding var isGrown: Bool
    let glass: Namespace.ID
    let run: (NextStep) -> Void

    @State private var pointerTask: Task<Void, Never>?
    @State private var watchTask: Task<Void, Never>?
    @State private var isPointedAt = false
    /// Keyboard navigation is on the strip above the front button: the edges get the ring.
    @FocusState private var stripHasFocus: Bool
    /// The stack's frame in the window, to check the pointer against.
    @State private var frameInWindow: CGRect = .zero
    /// The fanned-out action under the pointer. SwiftUI's hover doesn't reach buttons that appear
    /// inside the stack as it grows, so the stack lights them from where the pointer is.
    @State private var pointedChoice: NextStep?
    @State private var shrinkTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Two edges show at most; the rest are as easy to reach from More.
    private var edges: Int { min(behind.count, 2) }
    private static let gap: CGFloat = Space.s
    /// The edges show 4–9 pt above the front button; the strip that opens the stack is a little taller.
    private static let edgeStrip: CGFloat = 14
    /// A fanned-out action and the gap under it.
    private static let row = StackButtonStyle.height + gap

    /// The front button, with the edge strip or the fanned-out actions above it.
    private var height: CGFloat {
        StackButtonStyle.height + (isGrown ? CGFloat(behind.count) * Self.row : edges > 0 ? Self.edgeStrip : 0)
    }

    var body: some View {
        // Laid out from the bottom, where the front button stays. Each of the others has a fixed
        // place above it, open or not, so the stack growing upward never carries them: they rise
        // from exactly behind the front button. The places take no room while it's folded — the
        // stack's frame is only as tall as what shows (`height`).
        ZStack(alignment: .bottom) {
            // The others' glass in a container of its own, drawn as one layer under the front
            // button. In the bar's container, their glass grew out of the front button's as they
            // appeared and was drawn over it, labels and all, whatever the views' order.
            GlassEffectContainer(spacing: 0) { others }
            if !isOpen, edges > 0 {
                edgeStrip
                    .offset(y: -StackButtonStyle.height)
            }
            frontButton
                .background(alignment: .top) {
                    // Faded in place rather than removed, so the edges stay under the front
                    // button while the others rise out of it.
                    edgesView.opacity(isOpen ? 0 : 1)
                }
                .onContinuousHover(perform: arrival)
                .zIndex(1)
        }
        .frame(height: height, alignment: .bottom)
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
        .onChange(of: isOpen, initial: true) { resize() }
        .onDisappear {
            pointerTask?.cancel()
            watchTask?.cancel()
            shrinkTask?.cancel()
            isOpen = false
            isGrown = false
        }
        .task {
            guard NextStepsDemo.opensStack else { return }
            try? await Task.sleep(for: .milliseconds(600))
            setOpen(true)
        }
    }

    /// The other actions, each in its place above the front button, nearest it at the bottom; the
    /// last place is the front button's own.
    private var others: some View {
        VStack(spacing: 0) {
            ForEach(Array(behind.enumerated()).reversed(), id: \.element) { index, step in
                ZStack {
                    if isOpen {
                        Button(step.title, systemImage: step.symbol) { fold(); run(step) }
                            .buttonStyle(StackButtonStyle(prominent: false, highlighted: pointedChoice == step))
                            .accessibilityLabel(step.title)
                            .transition(rise(from: index))
                            .help(unavailable ?? String(localized: "\(step.title): \(scope)"))
                            .disabled(unavailable != nil)
                    }
                }
                .frame(height: StackButtonStyle.height)
                .padding(.bottom, Self.gap)
                // Each under the one nearer the front button.
                .zIndex(-Double(index + 1))
            }
            Color.clear.frame(height: StackButtonStyle.height)
        }
    }

    private var frontButton: some View {
        ZStack {
            // The widest label sets the width of every button in the stack.
            ForEach([front] + behind) { step in
                StackLabel(step: step).hidden()
            }
            // …up to a limit: a long name ("Copy to “…”") is shortened in the middle rather than
            // pushing the stack into Extract All or under Details.
            .frame(maxWidth: StackButtonStyle.maxWidth)
            Button(front.title, systemImage: front.symbol) { fold(); run(front) }
                .buttonStyle(StackButtonStyle(prominent: true))
                // ⌘E as in File › Extract; the others keep their menu-bar keys.
                .keyboardShortcut(front == .extract ? front.menuShortcut : nil)
                .accessibilityLabel(front.title)
                .help(unavailable ?? String(localized: "\(front.title): \(scope)"))
                .disabled(unavailable != nil)
                .glassMorph("summary", in: glass)
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
        // The strip is invisible, so its own rectangle of a ring floated over nothing; the edges
        // it opens draw the ring instead (`edgesView`).
        .focused($stripHasFocus)
        .focusEffectDisabled()
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
                StackEdge(depth: depth, dimmed: unavailable != nil)
                    .scaleEffect(1 - 0.07 * CGFloat(depth + 1), anchor: .top)
                    .offset(y: -CGFloat(depth + 1) * 4.5)
            }
            if stripHasFocus, edges > 0 {
                // Round the backmost edge, so the part above the front button traces the stack's
                // top; the front button covers the rest.
                Capsule()
                    .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 3)
                    .padding(-3)
                    .frame(height: StackButtonStyle.height)
                    .scaleEffect(x: 1 - 0.07 * CGFloat(edges), y: 1, anchor: .top)
                    .offset(y: -CGFloat(edges) * 4.5)
            }
        }
        .allowsHitTesting(false)
    }

    /// Up from behind the front button (`index` steps away), with the system's fade under Reduce Motion.
    /// Each starts a little smaller and centred on the front button, so its label is hidden under
    /// the front button's accent until it clears the top edge, and sinks back the same way.
    private func rise(from index: Int) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        let distance = CGFloat(index + 1) * Self.row
        return .offset(y: distance).combined(with: .scale(scale: 0.9)).combined(with: .opacity)
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
        let y = point.y - frameInWindow.minY
        let index = Int(y / Self.row)
        guard y.truncatingRemainder(dividingBy: Self.row) < StackButtonStyle.height, index < behind.count else { return nil }
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

    /// Grows the frame as the stack opens, and shrinks it once the others have sunk back: a change
    /// made without motion would cut their exit short.
    private func resize() {
        shrinkTask?.cancel()
        let open = isOpen
        shrinkTask = Task {
            if !open { try? await Task.sleep(for: .milliseconds(300)) }
            guard !Task.isCancelled else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { isGrown = open }
        }
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
    /// The widest a stacked button gets, glass included; longer labels shorten in the middle.
    static let maxWidth: CGFloat = 280
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
            .truncationMode(.middle)
            .foregroundStyle(!isEnabled ? AnyShapeStyle(.secondary) : prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, Space.l)
            .frame(minWidth: 116, maxWidth: .infinity, minHeight: ActionButtonStyle.height)
            .background {
                // Disabled gives up the accent rather than fading: the glass container draws its
                // glass itself, so an opacity here wouldn't reach it.
                if !isEnabled {
                    Capsule().fill(.primary.opacity(prominent ? 0.07 : 0))
                } else if prominent {
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
                if prominent, isEnabled, ContrastStyle.resolve(contrast).increased {
                    Capsule().strokeBorder(.primary.opacity(0.45))
                }
            }
            .padding(ActionButtonStyle.inset)
            .accessibleGlass(in: .capsule)
            .contentShape(.capsule)
            .onHover { isHovering = $0 && isEnabled }
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
    /// The stack can't run yet: the edges give up the accent with the front button. They sit under
    /// its glass, so a tinted edge would wash the dimmed button in the accent.
    var dimmed = false
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Capsule()
            .fill(DisplayPreferences.reducesTransparency(reduceTransparency) ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
                  : AnyShapeStyle(.regularMaterial))
            .overlay {
                Capsule().fill(dimmed ? AnyShapeStyle(.primary.opacity(0.06))
                               : AnyShapeStyle(Color.accentColor.opacity(depth == 0 ? 0.28 : 0.16)))
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
    /// A switch that's on (Glance's Pin on Top): the symbol in the accent with a ring round it.
    var isOn = false

    func makeBody(configuration: Configuration) -> some View {
        ActionButtonBody(configuration: configuration, prominent: prominent, iconOnly: iconOnly, height: height, isOn: isOn)
    }
}

private struct ActionButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    let iconOnly: Bool
    let height: CGFloat
    let isOn: Bool
    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        configuration.label
            .font(.body.weight(prominent ? .semibold : .regular))
            .foregroundStyle(prominent ? AnyShapeStyle(.white) : isOn ? AnyShapeStyle(.accentText) : AnyShapeStyle(.primary))
            .padding(.horizontal, iconOnly ? 0 : Space.m)
            .frame(minWidth: height, minHeight: height)
            .background { background }
            .overlay {
                // Increase Contrast outlines the primary, so it reads by shape as well as by colour.
                if prominent, ContrastStyle.resolve(contrast).increased {
                    Capsule().strokeBorder(.primary.opacity(0.45))
                }
                if isOn {
                    Capsule().strokeBorder(.accentText, lineWidth: 1.5)
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
            // Capped first, then sized to fit: a long archive name shortens in the middle at the
            // stack's limit instead of running under Details (capped after, it overflowed).
            .frame(maxWidth: StackButtonStyle.maxWidth)
            .fixedSize()
            .glassMorph("summary", in: glass)
        } else {
            // The whole sentence while there's room; in a narrow window only what to do (Details
            // already counts the selection).
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    Text("\(model.selection.count) items")
                        .fontWeight(.medium)
                        .liveNumber()
                    Text("inside other archives — select one to show it")
                        .foregroundStyle(.secondary)
                }
                .fixedSize()
                Text("Select one result to show it")
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
                .font(.callout)
                .lineLimit(1)
                .accessibilityElement(children: .combine)
                .frame(minHeight: StackButtonStyle.height)
                .padding(.horizontal, Space.l)
                .accessibleGlass(in: .capsule)
                .glassMorph("summary", in: glass)
        }
    }
}

extension BrowserModel {
    /// Why Actions and Extract All can't run right now, for their disabled state and help tags; nil
    /// when they can. (`run` and `extractAll` already do nothing while the archive is listed.)
    var actionsUnavailableReason: String? {
        isListing ? String(localized: "Available once the whole archive is listed") : nil
    }

    /// Extract All waits for a running step: starting it would stop that step part-way.
    var extractAllUnavailableReason: String? {
        if let reason = actionsUnavailableReason { return reason }
        if case .running = activity?.phase { return String(localized: "Available when the current step finishes") }
        return nil
    }
}
