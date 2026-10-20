import SwiftUI

/// The pack's progress, then its result, in the same floating glass capsule as Next Steps.
struct PackActivityBar: View {
    let packing: PackController
    @Namespace private var glass

    var body: some View {
        if let activity = packing.activity {
            GlassEffectContainer(spacing: Space.s) {
                HStack(spacing: Space.s) {
                    PackCapsule(activity: activity)
                        .glassEffect(.regular, in: .capsule)
                        .glassEffectID("summary", in: glass)
                    switch activity.phase {
                    case .running where !activity.isSample:
                        Button("Stop", systemImage: "xmark") { packing.cancel() }
                            .labelStyle(.iconOnly)
                            .help("Stop — nothing is left half-written")
                            .buttonStyle(.glass)
                            .glassEffectID("stop", in: glass)
                    case .done where !activity.placed.isEmpty:
                        Button("Show in Finder", systemImage: "folder") { packing.showInFinder() }
                            .buttonStyle(.glass)
                            .glassEffectID("finder", in: glass)
                    case .failed:
                        Button("Dismiss", systemImage: "xmark") { packing.dismiss() }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.glass)
                            .glassEffectID("stop", in: glass)
                    default:
                        EmptyView()
                    }
                }
                .fixedSize()
                .controlSize(.large)
            }
            .padding(.horizontal, Space.l)
        }
    }
}

private struct PackCapsule: View {
    let activity: PackController.Activity

    var body: some View {
        HStack(spacing: Space.s) {
            switch activity.phase {
            case .running(let progress):
                ProgressRing(progress: progress)
                Text("Packing “\(activity.name)”")
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 280)
                    .fixedSize(horizontal: true, vertical: false)
                Text(progress, format: .percent.precision(.fractionLength(0)))
                    .foregroundStyle(.secondary)
                    .liveNumber()
                    .frame(minWidth: 36, alignment: .trailing)
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                Text(activity.doneTitle)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 320)
                    .fixedSize(horizontal: true, vertical: false)
                if activity.verified {
                    Text("· tested")
                        .foregroundStyle(.secondary)
                        .help("Stow opened the new archive and checked every file")
                }
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text(message)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .frame(maxWidth: 360, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.callout)
        .padding(.horizontal, Space.l)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }
}
