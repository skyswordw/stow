import SwiftUI

/// Floating glass capsule with the right next steps for the current selection.
/// While a step runs, the summary morphs into a progress capsule in place.
struct NextStepsBar: View {
    let model: BrowserModel
    @Namespace private var glass

    var body: some View {
        let entries = model.selectedEntries
        let steps = NextStep.suggestions(for: entries)

        GlassEffectContainer(spacing: Space.s) {
            HStack(spacing: Space.s) {
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
                    SelectionSummary(entries: entries)
                        .glassEffect(.regular, in: .capsule)
                        .glassEffectID("summary", in: glass)

                    ForEach(steps.dropLast()) { step in
                        Button(step.title, systemImage: step.symbol) { model.run(step) }
                            .buttonStyle(.glass)
                            .glassEffectID(step, in: glass)
                    }
                    Button(NextStep.extract.title, systemImage: NextStep.extract.symbol) { model.run(.extract) }
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut("e", modifiers: [.command])
                        .glassEffectID(NextStep.extract, in: glass)
                }
            }
            .controlSize(.large)
        }
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
