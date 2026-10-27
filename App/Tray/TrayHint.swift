import AppKit
import SwiftUI

/// While files are dragged, a small piece of Tray glass where the Tray comes out, so the drag
/// knows where to go (#180). Used when the Tray lives at the screen's edge or where people put it;
/// under the menu bar, the icon itself changes instead. It takes no clicks or drops: it sits inside
/// the Tray's approach zone, so by the time a drag reaches it the Tray has come out over it.
final class TrayHint {
    static let size: CGFloat = 44
    /// Room around it for its shadow.
    private static let margin: CGFloat = 16

    private let state = TrayHintState()
    private var panel: NSPanel?
    private var isOut = false

    func present(at center: CGPoint, border: TrayBorder) {
        let side = Self.size + Self.margin * 2
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.setFrame(CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side), display: false)
        state.border = border
        guard !isOut else { return }
        isOut = true
        panel.orderFrontRegardless()
        guard let animation = Motion.presence(true, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) else {
            state.isShown = true
            return
        }
        // The next turn, so the hidden state has been drawn once and there's something to animate from.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isOut else { return }
            withAnimation(animation) { self.state.isShown = true }
        }
    }

    func dismiss() {
        guard let panel, isOut else { return }
        isOut = false
        guard let animation = Motion.presence(false, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) else {
            state.isShown = false
            panel.orderOut(nil)
            return
        }
        withAnimation(animation) { state.isShown = false } completion: { [weak self] in
            // Back out while it was leaving: stay.
            if self?.isOut == false { panel.orderOut(nil) }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        // The view draws the shadow, as the Tray's does.
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        // A drop must never land on the hint: whatever is under it gets the drag until the Tray is out.
        panel.ignoresMouseEvents = true
        let host = NSHostingView(rootView: TrayHintView(state: state))
        host.sizingOptions = []
        panel.contentView = host
        return panel
    }
}

@Observable
private final class TrayHintState {
    var isShown = false
    var border: TrayBorder = .accent
}

/// The Tray in miniature: its glass, its border colour, and the tray taking something in.
private struct TrayHintView: View {
    let state: TrayHintState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card)
        Image(systemName: "tray.and.arrow.down")
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(state.border.color)
            .frame(width: TrayHint.size, height: TrayHint.size)
            .accessibleGlass(in: shape)
            .overlay { shape.strokeBorder(state.border.color.opacity(0.45), lineWidth: 1) }
            .background {
                shape.fill(.black.opacity(0.001))
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
            }
            // Comes up a little as it fades in, like the Tray; a fade alone under Reduce Motion.
            .scaleEffect(state.isShown || reduceMotion ? 1 : 0.9)
            .opacity(state.isShown ? 1 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // A drag can't be steered by VoiceOver; the Tray itself is reachable from the menu bar and ⌥⌘T.
            .accessibilityHidden(true)
    }
}
