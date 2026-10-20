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
        let steps = NextStep.suggestions(for: entries)

        return HStack(spacing: Space.s) {
            if let activity = model.activity {
                ActivityCapsule(activity: activity)
                    .glassEffect(.regular, in: .capsule)
                    .glassEffectID("summary", in: glass)
                if activity.phase == .done {
                    Button("Show in Finder", systemImage: "folder") { model.dismissActivity() }
                        .buttonStyle(.glass)
                        .glassEffectID("finder", in: glass)
                }
            } else {
                if density != .actionsOnly {
                    SelectionSummary(entries: entries)
                        .glassEffect(.regular, in: .capsule)
                        .glassEffectID("summary", in: glass)
                }
                ForEach(steps.dropLast()) { step in
                    Button(step.title, systemImage: step.symbol) { model.run(step) }
                        .labelStyle(density == .full ? AnyLabelStyle(.titleAndIcon) : AnyLabelStyle(.iconOnly))
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
            Text(entries.count == 1 ? entries[0].name : "\(entries.count) items")
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

private struct ActivityCapsule: View {
    let activity: BrowserModel.Activity

    var body: some View {
        HStack(spacing: Space.s) {
            switch activity.phase {
            case .running(let progress):
                ProgressRing(progress: progress)
                Text("\(activity.step.progressTitle) \(activity.itemCount) \(activity.itemCount == 1 ? "item" : "items")")
                    .fontWeight(.medium)
                Text(progress, format: .percent.precision(.fractionLength(0)))
                    .foregroundStyle(.secondary)
                    .liveNumber()
                    .frame(minWidth: 36, alignment: .trailing)
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                Text(activity.step.doneTitle)
                    .fontWeight(.medium)
            }
        }
        .font(.callout)
        .padding(.horizontal, Space.l)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }
}

private struct ProgressRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(.tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 15, height: 15)
    }
}
