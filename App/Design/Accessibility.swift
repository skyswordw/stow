import SwiftUI

/// Shared spoken descriptions; keep punctuation and number formatting out of view bodies.
enum AccessibilityText {
    static func entry(_ entry: ArchiveEntry, itemCount: Int? = nil) -> String {
        let detail = entry.isNavigable ? itemCount.map { String(localized: "\($0) items") } : entry.size.bytes
        return [entry.name, entry.kindDescription, detail].compactMap { $0 }.joined(separator: ", ")
    }

    static func progress(_ fraction: Double) -> String {
        let bounded = fraction.isFinite ? min(1, max(0, fraction)) : 0
        return String(localized: "\(Int((bounded * 100).rounded())) percent")
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

/// Glass is chrome; under Reduce Transparency its shape remains, filled with opaque window color.
private struct AccessibleGlass<S: Shape>: ViewModifier {
    let shape: S
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency || UserDefaults.standard.bool(forKey: "StowReduceTransparency") {
            content.background(Color(nsColor: .windowBackgroundColor), in: shape)
                .overlay { shape.stroke(.primary.opacity(ContrastStyle.resolve(contrast).increased ? 0.45 : 0), lineWidth: 1).allowsHitTesting(false).accessibilityHidden(true) }
        } else {
            content.glassEffect(.regular, in: shape)
                .overlay { shape.stroke(.primary.opacity(ContrastStyle.resolve(contrast).increased ? 0.45 : 0), lineWidth: 1).allowsHitTesting(false).accessibilityHidden(true) }
        }
    }
}

extension View {
    func accessibleGlass(in shape: some Shape) -> some View {
        modifier(AccessibleGlass(shape: shape))
    }
}

private struct AccessibleBar: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content.background(reduceTransparency || UserDefaults.standard.bool(forKey: "StowReduceTransparency")
                           ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor)) : AnyShapeStyle(.bar))
    }
}

extension View {
    func accessibleBar() -> some View { modifier(AccessibleBar()) }
}
