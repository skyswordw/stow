import SwiftUI

/// Actions (#161): one floating glass capsule with the right actions for the current selection.
/// What it acts on comes first (the name, or a count, and the size), then the suggestions, More,
/// and the one primary action — Extract unless a step is more specific. While a step runs, the
/// capsule morphs into its progress capsule in place.
/// Labels never truncate: in a narrow window suggestions collapse to icons, then the scope goes.
/// Every other action that applies — including ones hidden in Settings — is in the More menu.
/// (Internal names keep "Next Steps": the feature's settings keys and types predate the rename.)
struct NextStepsBar: View {
    let model: BrowserModel
    @Namespace private var glass
    @AppStorage(SettingsKeys.nextStepsHidden) private var hidden = NextStepsSettings.encode(NextStepsSettings.defaultHidden)

    enum Density { case full, iconSuggestions, actionsOnly }

    var body: some View {
        GlassEffectContainer(spacing: Space.s) {
            ViewThatFits(in: .horizontal) {
                row(.full)
                row(.iconSuggestions)
                row(.actionsOnly)
            }
            .controlSize(.large)
        }
        .padding(.horizontal, Space.l)
    }

    private func row(_ density: Density) -> some View {
        let entries = model.selectedEntries
        let settings = NextStepsSettings(hidden: NextStepsSettings.decode(hidden))
        let layout = settings.layout(for: entries, dropTargets: model.archive.dropTargets)

        return Group {
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
                NestedResultRow(model: model, compact: density == .actionsOnly, glass: glass)
            } else {
                ActionsCapsule {
                    if density != .actionsOnly {
                        SelectionSummary(entries: entries)
                            .scopeSlot()
                    }
                    ForEach(layout.suggestions) { step in
                        Button(step.title, systemImage: step.symbol) { model.run(step) }
                            .labelStyle(density == .full ? AnyLabelStyle(.titleAndIcon) : AnyLabelStyle(.iconOnly))
                            .accessibilityLabel(step.title)
                            .help(step.title)
                            .buttonStyle(ActionButtonStyle(iconOnly: density != .full))
                    }
                    NextStepsMoreMenu(model: model, alternatives: layout.alternatives)
                    if let primary = layout.primary {
                        Button(primary.title, systemImage: primary.symbol) { model.run(primary) }
                            .labelStyle(.titleAndIcon)
                            .buttonStyle(ActionButtonStyle(prominent: true))
                            // ⌘E as in File › Extract; Quick Look and Open keep their menu-bar keys.
                            .keyboardShortcut(primary == .extract ? primary.menuShortcut : nil)
                    }
                }
                .glassEffectID("summary", in: glass)
            }
        }
        .fixedSize()
    }
}

/// The capsule itself: one piece of glass around the scope and the buttons, which have none of
/// their own (never glass on glass). Its height matches the progress capsule it morphs into.
private struct ActionsCapsule<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 2) {
            content
        }
        .padding(ActionButtonStyle.inset)
        .accessibleGlass(in: .capsule)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Actions"))
    }
}

private extension View {
    /// What the actions apply to, under the feature's name (the same name Settings and the More
    /// menu use, so the capsule is easy to find again), set off from the buttons by a hairline.
    func scopeSlot() -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Actions")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                self
            }
                .padding(.leading, Space.m + 2)
                .padding(.trailing, Space.s + 2)
            Rectangle()
                .fill(.separator)
                .frame(width: 1, height: 16)
                .padding(.trailing, Space.xs)
                .accessibilityHidden(true)
        }
    }
}

/// Buttons inside the Actions capsule: a quiet fill under the pointer, and the one primary action
/// filled with the accent, concentric with the capsule around it.
struct ActionButtonStyle: ButtonStyle {
    /// The capsule's padding around its buttons; button radius + inset = capsule radius.
    static let inset: CGFloat = 4
    static let height: CGFloat = 30

    var prominent = false
    var iconOnly = false

    func makeBody(configuration: Configuration) -> some View {
        ActionButtonBody(configuration: configuration, prominent: prominent, iconOnly: iconOnly)
    }
}

private struct ActionButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    let iconOnly: Bool
    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        configuration.label
            .font(.body.weight(prominent ? .semibold : .regular))
            .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, iconOnly ? 7 : Space.m)
            .frame(minWidth: ActionButtonStyle.height, minHeight: ActionButtonStyle.height)
            .background { background }
            .overlay {
                // Increase Contrast outlines the primary, so it reads by shape as well as by colour.
                if prominent, ContrastStyle.resolve(contrast).increased {
                    Capsule().strokeBorder(.primary.opacity(0.45))
                }
            }
            .contentShape(.capsule)
            .onHover { isHovering = $0 }
            .opacity(isEnabled ? 1 : 0.45)
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

/// The capsule for a search result inside an inner archive: its name, where it is, and Show.
private struct NestedResultRow: View {
    let model: BrowserModel
    let compact: Bool
    /// Shared with the regular capsule, so it morphs in place like that one does.
    let glass: Namespace.ID

    var body: some View {
        if let hit = model.selectedNestedHit {
            ActionsCapsule {
                if !compact {
                    HStack(spacing: 6) {
                        Text(hit.inner.name)
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 220)
                            .fixedSize(horizontal: true, vertical: false)
                        Text("in \(hit.container.name)")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 200)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .font(.callout)
                    .accessibilityElement(children: .combine)
                    .scopeSlot()
                }
                // The scope beside it already names the archive; the button stays short so it never truncates.
                Button(String(localized: "Show in Archive"), systemImage: NextStep.openInside.symbol) {
                    model.showNested(hit)
                }
                .accessibilityLabel(String(localized: "Show in “\(hit.container.name)”"))
                .help(String(localized: "Show in “\(hit.container.name)”"))
                .labelStyle(.titleAndIcon)
                .buttonStyle(ActionButtonStyle(prominent: true))
            }
            .glassEffectID("summary", in: glass)
        } else {
            // Shaped like the selection's scope: the count first, then what to do about it.
            ActionsCapsule {
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
                .frame(minHeight: ActionButtonStyle.height)
                .padding(.horizontal, Space.m)
            }
            .glassEffectID("summary", in: glass)
        }
    }
}

/// What the actions apply to: one item's name, or a count, then the size.
private struct SelectionSummary: View {
    let entries: [ArchiveEntry]

    var body: some View {
        let size = entries.reduce(Int64(0)) { $0 + $1.size }
        HStack(spacing: 6) {
            Text(entries.count == 1 ? entries[0].name : String(localized: "\(entries.count) items"))
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 220)
                .fixedSize(horizontal: true, vertical: false)
                .liveNumber()
            Text(size.bytes)
                .foregroundStyle(.secondary)
                .liveNumber()
                .fixedSize()
        }
        .font(.callout)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AccessibilityText.selectionSummary(entries))
    }
}
