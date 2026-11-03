import SwiftUI

/// Shared spoken descriptions; keep punctuation and number formatting out of view bodies.
enum AccessibilityText {
    /// "report.pdf, PDF document, 2.4 MB"; a folder says how many items it holds; a search result
    /// inside an inner archive says which one ("…, in Photos.zip").
    static func entry(_ entry: ArchiveEntry, itemCount: Int? = nil, container: String? = nil) -> String {
        let detail = entry.isNavigable ? itemCount.map { String(localized: "\($0) items") } : entry.size.bytes
        let place = container.map { String(localized: "in \($0)") }
        return [entry.name, entry.kindDescription, detail, place].compactMap { $0 }.joined(separator: ", ")
    }

    /// What Next Steps' summary shows, as one sentence: "3 items, 12 MB" or "report.pdf, 2.4 MB".
    static func selectionSummary(_ entries: [ArchiveEntry]) -> String {
        let size = entries.reduce(Int64(0)) { $0 + $1.size }
        let what = entries.count == 1 ? entries[0].name : String(localized: "\(entries.count) items")
        return [what, size.bytes].joined(separator: ", ")
    }

    static func progress(_ fraction: Double) -> String {
        let bounded = fraction.isFinite ? min(1, max(0, fraction)) : 0
        return String(localized: "\(Int((bounded * 100).rounded())) percent")
    }

    /// Spoken label for an activity capsule / failure card. Pure strings — never read observable UI.
    static func activity(title: String, note: String? = nil) -> String {
        [title, note].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// Failure title + advice as one AX label (#93). Empty advice omits the separator.
    static func failure(_ failure: Failure) -> String {
        let advice = failure.advice.trimmingCharacters(in: .whitespacesAndNewlines)
        return advice.isEmpty ? failure.title : "\(failure.title). \(advice)"
    }
}

/// Keep AX attribute resolution independent of the observable browser and visual children.
/// Rename keeps the original subtree so its native text field remains reachable.
private struct ArchiveEntryAccessibility: ViewModifier {
    let label: String
    let isRenaming: Bool
    let activate: @MainActor () -> Void

    func body(content: Content) -> some View {
        if isRenaming {
            content
        } else {
            // A String-titled Button is a true AX leaf: no child Text for label resolution to re-enter.
            content.accessibilityRepresentation {
                Button(label) {
                    // Leave the AX callback before selection, navigation, or sheets mutate the tree.
                    Task { @MainActor in activate() }
                }
            }
        }
    }
}

extension View {
    /// Snapshot rename state during normal body evaluation; the AX leaf reads only a String.
    func archiveEntryAccessibility(entry: ArchiveEntry, isRenaming: Bool = false,
                                   activate: @escaping @MainActor () -> Void) -> some View {
        modifier(ArchiveEntryAccessibility(label: AccessibilityText.entry(entry),
                                           isRenaming: isRenaming, activate: activate))
    }
}

/// The system's display preferences as Stow draws them. A launch argument can't turn on the
/// system's own settings, so design snapshots force them with debug-only overrides
/// (`-StowReduceTransparency YES`, `-StowIncreaseContrast YES`, `-StowReduceMotion YES`); every
/// reader goes through here (or `ContrastStyle.resolve`, or `\.reducesMotion`) so a snapshot shows
/// what the setting shows (#104).
enum DisplayPreferences {
    static func reducesTransparency(_ system: Bool) -> Bool {
        system || UserDefaults.standard.bool(forKey: "StowReduceTransparency")
    }

    nonisolated static func reducesMotion(_ system: Bool) -> Bool {
        system || UserDefaults.standard.bool(forKey: "StowReduceMotion")
    }

    /// For models and controllers, which can't read the environment.
    static var reducesMotionNow: Bool {
        reducesMotion(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }
}

extension EnvironmentValues {
    /// Reduce Motion as Stow honours it: the system setting, or the design-snapshot override.
    /// Views read this rather than `accessibilityReduceMotion` (DESIGN.md › Motion).
    var reducesMotion: Bool { DisplayPreferences.reducesMotion(accessibilityReduceMotion) }
}

/// Glass that morphs between shapes sharing a `GlassEffectContainer` (Actions' front button into
/// its progress capsule, Stop and Show in Finder splitting off it). A morph stretches and moves
/// the glass, so under Reduce Motion the shapes cross-fade instead (DESIGN.md › Motion).
private struct GlassMorph: ViewModifier {
    let id: String
    let namespace: Namespace.ID
    @Environment(\.reducesMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .glassEffectID(id, in: namespace)
            .glassEffectTransition(reduceMotion ? .materialize : .matchedGeometry)
    }
}

extension View {
    func glassMorph(_ id: String, in namespace: Namespace.ID) -> some View {
        modifier(GlassMorph(id: id, namespace: namespace))
    }
}

struct ContrastStyle: Equatable {
    let increased: Bool
    var borderOpacity: Double { increased ? 0.45 : 0.1 }
    var faintBorderOpacity: Double { increased ? 0.45 : 0.06 }
    var metadata: AnyShapeStyle { increased ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary) }

    static func resolve(_ contrast: ColorSchemeContrast,
                        override: Bool = UserDefaults.standard.bool(forKey: "StowIncreaseContrast")) -> Self {
        Self(increased: contrast == .increased || override)
    }
}

/// The accent as words and symbols. In dark mode the accent is deep enough for white words on an
/// accent fill (#104), which leaves it too dim for words on a dark panel; this raises its lightness,
/// keeping hue and saturation, until it reads at 4.5 : 1 against one (7 : 1 under Increase
/// Contrast). An accent that already reads, such as a Mac's own blue, is left as it is. Fills,
/// rings and selection keep `.tint`.
struct AccentText: ShapeStyle {
    nonisolated func resolve(in environment: EnvironmentValues) -> Color {
        guard environment.colorScheme == .dark else { return .accentColor }
        let accent = Color.accentColor.resolve(in: environment)
        // `ContrastStyle.resolve` is main-actor; a shape style resolves off it, so read the same two.
        let increased = environment.colorSchemeContrast == .increased
            || UserDefaults.standard.bool(forKey: "StowIncreaseContrast")
        let target: Double = increased ? 7 : 4.5
        let lifted = Self.lifted(RGB(red: Double(accent.red), green: Double(accent.green), blue: Double(accent.blue)),
                                 toContrast: target)
        return Color(.sRGB, red: lifted.red, green: lifted.green, blue: lifted.blue, opacity: Double(accent.opacity))
    }

    nonisolated struct RGB: Equatable, Sendable {
        var red, green, blue: Double
    }

    /// The darkest panel accent words sit on: Details or a glass capsule over a dark window.
    nonisolated static let darkPanel = RGB(red: 0x2C / 255, green: 0x2C / 255, blue: 0x2C / 255)

    /// WCAG relative luminance of a gamma-encoded sRGB colour.
    nonisolated static func luminance(_ c: RGB) -> Double {
        func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(c.red) + 0.7152 * linear(c.green) + 0.0722 * linear(c.blue)
    }

    nonisolated static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    nonisolated static func lifted(_ color: RGB, toContrast target: Double, against panel: RGB = darkPanel) -> RGB {
        var (hue, saturation, lightness) = hsl(color)
        var result = color
        while contrast(result, panel) < target, lightness < 1 {
            lightness = min(1, lightness + 0.005)
            result = rgb(hue: hue, saturation: saturation, lightness: lightness)
        }
        return result
    }

    nonisolated private static func hsl(_ c: RGB) -> (Double, Double, Double) {
        let (r, g, b) = (min(max(c.red, 0), 1), min(max(c.green, 0), 1), min(max(c.blue, 0), 1))
        let (high, low) = (max(r, g, b), min(r, g, b))
        let lightness = (high + low) / 2
        guard high > low else { return (0, 0, lightness) }
        let delta = high - low
        let saturation = delta / (1 - abs(2 * lightness - 1))
        var hue = high == r ? (g - b) / delta : high == g ? (b - r) / delta + 2 : (r - g) / delta + 4
        hue = (hue * 60).truncatingRemainder(dividingBy: 360)
        return (hue < 0 ? hue + 360 : hue, saturation, lightness)
    }

    nonisolated private static func rgb(hue: Double, saturation: Double, lightness: Double) -> RGB {
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let x = chroma * (1 - abs((hue / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = lightness - chroma / 2
        let (r, g, b): (Double, Double, Double) = switch hue {
        case ..<60: (chroma, x, 0)
        case ..<120: (x, chroma, 0)
        case ..<180: (0, chroma, x)
        case ..<240: (0, x, chroma)
        case ..<300: (x, 0, chroma)
        default: (chroma, 0, x)
        }
        return RGB(red: r + m, green: g + m, blue: b + m)
    }
}

extension ShapeStyle where Self == AccentText {
    /// The accent for words and symbols; see `AccentText`.
    static var accentText: AccentText { AccentText() }
}

/// Glass is chrome; under Reduce Transparency its shape remains, filled with opaque window color.
/// The solid fill matches the content behind it in light mode, so it keeps a hairline edge, like
/// the system's own glass buttons do under Reduce Transparency.
private struct AccessibleGlass<S: Shape>: ViewModifier {
    let shape: S
    /// Lights up under the pointer and when pressed, like the system's glass buttons.
    var interactive = false
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if DisplayPreferences.reducesTransparency(reduceTransparency) {
            content.background(Color(nsColor: .windowBackgroundColor), in: shape)
                .overlay {
                    shape.stroke(ContrastStyle.resolve(contrast).increased ? AnyShapeStyle(.primary.opacity(0.45)) : AnyShapeStyle(.separator), lineWidth: 1)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
        } else {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
                .overlay { shape.stroke(.primary.opacity(ContrastStyle.resolve(contrast).increased ? 0.45 : 0), lineWidth: 1).allowsHitTesting(false).accessibilityHidden(true) }
        }
    }
}

extension View {
    func accessibleGlass(in shape: some Shape, interactive: Bool = false) -> some View {
        modifier(AccessibleGlass(shape: shape, interactive: interactive))
    }
}

private struct AccessibleBar: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content.background(DisplayPreferences.reducesTransparency(reduceTransparency)
                           ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor)) : AnyShapeStyle(.bar))
    }
}

extension View {
    func accessibleBar() -> some View { modifier(AccessibleBar()) }
}

extension BrowserModel {
    /// Rich browser summary. Do not use from entry AX modifiers: it reads observable state.
    func accessibilityLabel(for entry: ArchiveEntry) -> String {
        AccessibilityText.entry(entry,
                                itemCount: entry.isNavigable ? archive.children(of: entry.path, includingHelpers: showHelperItems).count : nil,
                                container: nestedHits[entry.id]?.container.name)
    }
}

extension View {
    /// Keyboard navigation's ring on `shape` instead of the control's own: for a native control
    /// (a disclosure) whose ring hugs only part of a row or crosses its container's edge. Apply it
    /// where `shape` fits the view, after the padding and background the ring should go round.
    /// `outset` 0 keeps the ring inside the view, for one a scroll view would clip.
    func focusRing(in shape: some InsettableShape, outset: CGFloat = 3) -> some View {
        modifier(FocusRingModifier(shape: shape, outset: outset))
    }
}

private struct FocusRingModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let outset: CGFloat
    @FocusState private var hasFocus: Bool

    func body(content: Content) -> some View {
        content
            .focused($hasFocus)
            .focusEffectDisabled()
            .overlay {
                if hasFocus {
                    shape.inset(by: -outset)
                        .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 3)
                        .allowsHitTesting(false)
                }
            }
    }
}
