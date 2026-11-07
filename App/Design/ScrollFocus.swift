import SwiftUI

/// Opt-in focus following for scrolling forms. Native SwiftUI controls on macOS can receive
/// keyboard focus without revealing themselves in a ScrollView (including on reverse traversal).
struct ScrollFocusRegion: ViewModifier {
    var margin: CGFloat
    @Namespace private var space
    @State private var height: CGFloat = 0

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .coordinateSpace(name: space)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { height = $0 }
                .environment(\.scrollFocusContext, ScrollFocusContext(
                    space: space, height: height, margin: margin, proxy: proxy))
        }
    }
}

private struct ScrollFocusContext {
    let space: Namespace.ID
    let height: CGFloat
    let margin: CGFloat
    let proxy: ScrollViewProxy
}

private struct ScrollFocusContextKey: EnvironmentKey {
    static let defaultValue: ScrollFocusContext? = nil
}

private extension EnvironmentValues {
    var scrollFocusContext: ScrollFocusContext? {
        get { self[ScrollFocusContextKey.self] }
        set { self[ScrollFocusContextKey.self] = newValue }
    }
}

extension View {
    /// Apply to a ScrollView. The margin keeps focused controls out of its fading edges.
    func followsKeyboardFocus(margin: CGFloat) -> some View {
        modifier(ScrollFocusRegion(margin: margin))
    }

    /// For controls that do not already own a FocusState or use our custom focus ring.
    func revealsKeyboardFocus() -> some View { modifier(RevealKeyboardFocus()) }

    /// Reuse an existing focus binding; do not attach competing FocusState bindings to a field.
    func revealsKeyboardFocus(_ focused: Bool) -> some View {
        background(alignment: .top) { ScrollFocusTarget(focused: focused) }
    }
}

private struct RevealKeyboardFocus: ViewModifier {
    @FocusState private var focused: Bool
    func body(content: Content) -> some View {
        content.focused($focused).revealsKeyboardFocus(focused)
    }
}

private struct ScrollFocusTarget: View {
    let focused: Bool
    @Environment(\.scrollFocusContext) private var context
    @State private var id = UUID()
    @State private var frame = CGRect.zero

    var body: some View {
        if let context {
            GeometryReader { geometry in
                // An expanded disclosure includes its children. Reveal its heading, not the
                // middle of the entire expanded form, when the disclosure itself has focus.
                Color.clear
                    .frame(height: min(geometry.size.height, 32))
                    .id(id)
                    .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(context.space)) }) { frame = $0 }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: focused) { _, focused in
                guard focused, context.height > 0, frame.height > 0,
                      frame.minY < context.margin || frame.maxY > context.height - context.margin else { return }
                // Keyboard navigation is immediate, even when the surrounding disclosure animates.
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) { context.proxy.scrollTo(id, anchor: .center) }
            }
        }
    }
}
