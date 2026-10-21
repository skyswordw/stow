import SwiftUI

/// Floating glass capsule with the right next steps for the current selection.
/// While a step runs, the summary morphs into a progress capsule in place.
/// Labels never truncate: in a narrow window suggestions collapse to icons, then the summary goes.
struct NextStepsBar: View {
    let model: BrowserModel
    @Namespace private var glass

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
        let steps = NextStep.suggestions(for: entries, dropTargets: model.archive.dropTargets)

        return HStack(spacing: Space.s) {
            if let activity = model.activity {
                ActivityCapsule(phase: activity.phase,
                                title: activity.phase == .done ? activity.doneTitle
                                    : String(localized: "\(activity.step.progressTitle) \(activity.itemCount) items"),
                                glass: glass,
                                stop: model.archive.source != nil ? { model.cancelActivity() } : nil,
                                stopHelp: String(localized: "Stop — nothing is left half-extracted"),
                                showInFinder: activity.placed.isEmpty ? nil : { model.showInFinder() },
                                perform: { model.follow($0) },
                                dismiss: { model.dismissActivity() })
            } else {
                if density != .actionsOnly {
                    SelectionSummary(entries: entries)
                        .accessibleGlass(in: .capsule)
                        .glassEffectID("summary", in: glass)
                }
                ForEach(steps.dropLast()) { step in
                    Button(step.title, systemImage: step.symbol) { model.run(step) }
                        .labelStyle(density == .full ? AnyLabelStyle(.titleAndIcon) : AnyLabelStyle(.iconOnly))
                        .accessibilityLabel(step.title)
                        .help(step.title)
                        .buttonStyle(.glass)
                        .glassEffectID(step, in: glass)
                }
                Button(NextStep.extract.title, systemImage: NextStep.extract.symbol) { model.run(.extract) }
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut("e", modifiers: [.command])
                    .glassEffectID(NextStep.extract, in: glass)
            }
        }
        .fixedSize()
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
    }
}
