import SwiftUI

/// Says that an encrypted file is being read for Quick Look (#104). The panel waits until the read
/// is done, so the window can ask for the password; for a big file that takes a while, and without
/// this Space would seem to do nothing.
///
/// A small glass capsule over the top of the files, under the path: the ring turns until the engine
/// measures something, then fills with the percentage beside it, as Actions' progress does, and ×
/// stops it (so does Escape). It waits 0.4 s before showing, so a quick read never flashes it, and
/// it stays out of the way while the password is asked for. It doesn't take the Actions slot: a
/// preview isn't a step, and Extract All stays ready meanwhile.
struct QuickLookPreparingCapsule: View {
    let model: BrowserModel
    let passwords: PasswordPrompt
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: UUID?

    private struct Wait: Equatable {
        let request: UUID?
        let asking: Bool
    }

    var body: some View {
        let preparation = model.quickLook.preparation
        let request = preparation.request
        let asking = passwords.question != nil
        let visible = request != nil && request?.id == shown && !asking
        ZStack {
            if visible, let request {
                capsule(request, progress: preparation.progress)
                    .transition(reduceMotion ? .opacity
                                : .asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
                                                .combined(with: .offset(y: -4)),
                                              removal: .opacity))
            }
        }
        // It comes and goes on its own (a read finishing), so it eases rather than springs.
        .animation(Motion.resolved(visible ? Motion.status : Motion.exit, reduceMotion: reduceMotion), value: visible)
        // The wait starts again once a password has been typed: a quick read after it shows nothing.
        .task(id: Wait(request: request?.id, asking: asking)) {
            shown = nil
            guard let id = request?.id, !asking else { return }
            try? await Task.sleep(for: .milliseconds(400))
            if !Task.isCancelled { shown = id }
        }
    }

    private func capsule(_ request: QuickLookPreparation.Request, progress: Double) -> some View {
        let title = request.count == 1
            ? String(localized: "Preparing “\(request.name)” for Quick Look")
            : String(localized: "Preparing \(request.count) files for Quick Look")
        return HStack(spacing: Space.s) {
            ProgressRing(progress: progress)
            Text(title)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 360)
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityValue(progress > 0 ? Text(progress, format: .percent.precision(.fractionLength(0))) : Text(""))
            // Nothing measured yet: the ring turns and no "0%" claims a start.
            if progress > 0 {
                Text(progress, format: .percent.precision(.fractionLength(0)))
                    .foregroundStyle(.secondary)
                    .liveNumber()
                    .frame(minWidth: 36, alignment: .trailing)
                    .accessibilityHidden(true)
            }
            Button("Stop", systemImage: "xmark") { model.quickLook.close() }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .fontWeight(.semibold)
                .accessibilityLabel(String(localized: "Stop"))
                .help("Stop preparing the preview (Esc)")
        }
        .font(.callout)
        .padding(.leading, Space.m)
        .padding(.trailing, Space.s + 2)
        .frame(height: 32)
        .accessibleGlass(in: .capsule)
        .padding(.horizontal, Space.m)
        .padding(.top, Space.s)
    }
}
