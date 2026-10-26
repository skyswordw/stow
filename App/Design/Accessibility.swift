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
            content.accessibilityRepresentation {
                Button(action: {
                    // Leave the AX callback before selection, navigation, or sheets mutate the tree.
                    Task { @MainActor in activate() }
                }) {
                    Text(verbatim: label)
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
/// The solid fill matches the content behind it in light mode, so it keeps a hairline edge, like
/// the system's own glass buttons do under Reduce Transparency.
private struct AccessibleGlass<S: Shape>: ViewModifier {
    let shape: S
    /// Lights up under the pointer and when pressed, like the system's glass buttons.
    var interactive = false
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency || UserDefaults.standard.bool(forKey: "StowReduceTransparency") {
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
        content.background(reduceTransparency || UserDefaults.standard.bool(forKey: "StowReduceTransparency")
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
