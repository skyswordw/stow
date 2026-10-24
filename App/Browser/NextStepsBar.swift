import SwiftUI

/// Floating glass capsule with the right next steps for the current selection.
/// While a step runs, the summary morphs into a progress capsule in place.
/// Labels never truncate: in a narrow window suggestions collapse to icons, then the summary goes.
/// Every other step that applies — including ones hidden in Settings — is in the More menu.
struct NextStepsBar: View {
    let model: BrowserModel
    @Namespace private var glass
    @AppStorage(SettingsKeys.nextStepsHidden) private var hidden = NextStepsSettings.encode(NextStepsSettings.defaultHidden)

    private enum Density { case full, iconSuggestions, actionsOnly }

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

        return HStack(spacing: Space.s) {
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
                if density != .actionsOnly {
                    SelectionSummary(entries: entries)
                        .accessibleGlass(in: .capsule)
                        .glassEffectID("summary", in: glass)
                }
                ForEach(layout.suggestions) { step in
                    Button(step.title, systemImage: step.symbol) { model.run(step) }
                        .labelStyle(density == .full ? AnyLabelStyle(.titleAndIcon) : AnyLabelStyle(.iconOnly))
                        .accessibilityLabel(step.title)
                        .help(step.title)
                        .buttonStyle(.glass)
                        .glassEffectID(step, in: glass)
                }
                NextStepsMoreMenu(model: model, alternatives: layout.alternatives)
                    .glassEffectID("more", in: glass)
                if let primary = layout.primary {
                    Button(primary.title, systemImage: primary.symbol) { model.run(primary) }
                        .labelStyle(.titleAndIcon)
                        .buttonStyle(.glassProminent)
                        // ⌘E as in File › Extract; Quick Look and Open keep their menu-bar keys.
                        .keyboardShortcut(primary == .extract ? primary.menuShortcut : nil)
                        .glassEffectID(primary, in: glass)
                }
            }
        }
        .fixedSize()
    }
}

/// The bar for a search result inside an inner archive: its name, where it is, and Show.
private struct NestedResultRow: View {
    let model: BrowserModel
    let compact: Bool
    /// Shared with the regular row, so the summary capsule morphs in place like it does there.
    let glass: Namespace.ID

    var body: some View {
        if let hit = model.selectedNestedHit {
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
                .padding(.horizontal, Space.l)
                .padding(.vertical, 9)
                .accessibleGlass(in: .capsule)
                .glassEffectID("summary", in: glass)
                .accessibilityElement(children: .combine)
            }
            // The capsule beside it already names the archive; the button stays short so it never truncates.
            Button(String(localized: "Show in Archive"), systemImage: NextStep.openInside.symbol) {
                model.showNested(hit)
            }
            .accessibilityLabel(String(localized: "Show in “\(hit.container.name)”"))
            .help(String(localized: "Show in “\(hit.container.name)”"))
            .labelStyle(.titleAndIcon)
            .buttonStyle(.glassProminent)
            .glassEffectID("showNested", in: glass)
        } else {
            // Shaped like the selection summary: the count first, then what to do about it.
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
            .padding(.horizontal, Space.l)
            .padding(.vertical, 9)
            .accessibleGlass(in: .capsule)
            .glassEffectID("summary", in: glass)
        }
    }
}

/// Type-erased label style so density can switch between title+icon and icon-only.
private struct AnyLabelStyle: LabelStyle {
    private let make: (Configuration) -> AnyView

    init(_ style: some LabelStyle) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View {
        make(configuration)
    }
}

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
        .padding(.horizontal, Space.l)
        .padding(.vertical, 9)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AccessibilityText.selectionSummary(entries))
    }
}
