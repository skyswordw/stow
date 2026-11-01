import SwiftUI

/// The pack's progress, then its result, in the same floating glass capsule as Next Steps.
struct PackActivityBar: View {
    let packing: PackController
    @Namespace private var glass

    var body: some View {
        if let activity = packing.activity {
            GlassEffectContainer(spacing: Space.s) {
                ActivityCapsule(phase: activity.phase,
                                title: activity.phase == .done ? activity.doneTitle : String(localized: "Packing “\(activity.name)”"),
                                note: activity.verified ? String(localized: "· contents verified") : nil,
                                noteHelp: String(localized: "Stow read back the new archive to verify its contents"),
                                glass: glass,
                                stop: activity.isSample ? nil : { packing.cancel() },
                                showInFinder: activity.placed.isEmpty ? nil : { packing.showInFinder() },
                                perform: { packing.follow($0) },
                                dismiss: { packing.dismiss() })
                .fixedSize()
                .controlSize(.large)
            }
            .padding(.horizontal, Space.l)
        }
    }
}
