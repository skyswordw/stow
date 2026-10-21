import AppKit
import SwiftUI

/// 4-pt spacing scale. See DESIGN.md › Space & shape.
enum Space {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

/// Concentric radii: panel ⊃ card ⊃ chip.
enum Radius {
    static let panel: CGFloat = 16
    static let card: CGFloat = 12
    static let chip: CGFloat = 8
}

/// Motion presets. See DESIGN.md › Motion. Everything goes through `resolved` so
/// Reduce Motion turns movement into a short fade.
enum Motion {
    /// Floating chrome entering because someone clicked or dropped something (Next Steps capsule).
    /// Critically damped — nothing to bounce about.
    static let appear = Animation.spring(response: 0.32, dampingFraction: 1)
    /// Floating chrome leaving: quicker than it came, and eased rather than sprung — nobody is touching it.
    static let exit = Animation.easeOut(duration: 0.18)
    /// A status changing on its own, like a step finishing or failing. Eased, not sprung.
    static let status = Animation.easeOut(duration: 0.2)
    /// Drop target reacting to a drag. A touch of give, because the user is physically moving something.
    static let target = Animation.spring(response: 0.25, dampingFraction: 0.9)
    /// Tray panel sliding along its edge.
    static let panel = Animation.spring(response: 0.35, dampingFraction: 1)
    /// Token text swapping in the Pack sentence.
    static let token = Animation.easeOut(duration: 0.18)
    /// Hover preview fade.
    static let preview = Animation.easeOut(duration: 0.14)

    static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: animation == exit ? 0.1 : 0.15) : animation
    }

    /// For changes made outside a view (models, controllers), which can't read the environment.
    static func current(_ animation: Animation) -> Animation {
        resolved(animation, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    /// Something showing or hiding: `appear` in, `exit` out, and nothing at all when a key press
    /// caused it (DESIGN.md › Motion: keyboard actions never animate).
    static func presence(_ visible: Bool, reduceMotion: Bool) -> Animation? {
        guard !byKeyboard else { return nil }
        return resolved(visible ? appear : exit, reduceMotion: reduceMotion)
    }

    /// True while the app handles a key press. Views re-render in the same turn of the run loop, so
    /// a fresh key-down means the keyboard caused the change; a timer firing later doesn't count.
    static var byKeyboard: Bool {
        guard let event = NSApp.currentEvent, event.type == .keyDown else { return false }
        return ProcessInfo.processInfo.systemUptime - event.timestamp < 0.25
    }

    /// A transaction that animates nothing when a key press caused the change.
    static var keyboardAware: Transaction {
        var transaction = Transaction()
        transaction.disablesAnimations = byKeyboard
        return transaction
    }
}

extension AnyTransition {
    /// Rises from the bottom edge with a slight scale and leaves with a smaller drop, so the exit
    /// stays quieter than the entrance; a plain fade under Reduce Motion.
    static func rise(reduceMotion: Bool) -> AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)).combined(with: .offset(y: 12)),
                          removal: .opacity.combined(with: .offset(y: 6)))
    }
}

extension View {
    /// Monospaced digits that roll instead of jitter when they change.
    func liveNumber() -> some View {
        monospacedDigit().contentTransition(.numericText())
    }
}

extension CheckupFinding.Severity {
    var symbol: String {
        switch self {
        case .fine: "checkmark.circle.fill"
        case .info: "info.circle.fill"
        case .handled: "shield.lefthalf.filled"
        case .caution: "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .fine: .green
        case .info: .secondary
        case .handled: .blue
        case .caution: .yellow
        }
    }
}

extension PackReport.Tone {
    var symbol: String {
        switch self {
        case .fine: "checkmark.circle.fill"
        case .info: "info.circle.fill"
        case .caution: "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .fine: .green
        case .info: .secondary
        case .caution: .yellow
        }
    }
}
