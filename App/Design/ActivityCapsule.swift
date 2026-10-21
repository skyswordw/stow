import SwiftUI

/// Where a long job is: packing, extracting, installing, opening, or one archive of a batch.
enum ActivityPhase: Equatable {
    case running(Double), done, failed(Failure)
}

/// The floating glass capsule every long job reports in — packing, extracting, installing — with
/// its one trailing control: Stop while it runs, Show in Finder when done, the failure's own next
/// step (and Dismiss) when it fails. Sits inside the caller's `GlassEffectContainer` so the
/// capsule morphs with whatever shares `glass` (Next Steps' selection summary).
struct ActivityCapsule: View {
    let phase: ActivityPhase
    /// "Packing “Handoff.zip”", "Extracting 12 items" while running; "Extracted to Downloads" when done.
    let title: String
    /// Quiet words after the done title ("· tested").
    var note: String?
    var noteHelp: String?
    let glass: Namespace.ID
    /// Nil when the job can't be stopped (sample runs).
    var stop: (() -> Void)?
    var stopHelp = String(localized: "Stop — nothing is left half-written")
    /// Nil when nothing was put on disk.
    var showInFinder: (() -> Void)?
    /// Runs a failure's next step.
    var perform: ((Failure.Action) -> Void)?
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: Space.s) {
            ActivityLabel(phase: phase, title: title, note: note, noteHelp: noteHelp, perform: perform, dismiss: dismiss)
                .padding(.leading, Space.l)
                .padding(.trailing, isFailure ? Space.m : Space.l)
                .padding(.vertical, isFailure ? Space.m : 9)
                .glassEffect(.regular, in: isFailure ? AnyShape(.rect(cornerRadius: Radius.panel + 4)) : AnyShape(.capsule))
                .glassEffectID("summary", in: glass)
            switch phase {
            case .running:
                if let stop {
                    Button("Stop", systemImage: "xmark", action: stop)
                        .labelStyle(.iconOnly)
                        .help(stopHelp)
                        .buttonStyle(.glass)
                        .glassEffectID("stop", in: glass)
                }
            case .done:
                if let showInFinder {
                    Button("Show in Finder", systemImage: "folder", action: showInFinder)
                        .buttonStyle(.glass)
                        .glassEffectID("finder", in: glass)
                }
            case .failed:
                // Dismiss sits inside the failure card (see `ActivityLabel`).
                EmptyView()
            }
        }
    }

    private var isFailure: Bool {
        if case .failed = phase { true } else { false }
    }
}

/// The capsule's contents without the glass: glyph, words, and the percentage while running; a
/// failure's title, advice and its one action. The batch panel's header uses it too.
struct ActivityLabel: View {
    let phase: ActivityPhase
    let title: String
    var note: String?
    var noteHelp: String?
    var perform: ((Failure.Action) -> Void)?
    /// A failure's close button, in the card's top-trailing corner.
    var dismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: isFailure ? .firstTextBaseline : .center, spacing: Space.s) {
            ActivityGlyph(phase)
            switch phase {
            case .running(let progress):
                Text(title)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 320)
                    .fixedSize(horizontal: true, vertical: false)
                Text(progress, format: .percent.precision(.fractionLength(0)))
                    .foregroundStyle(.secondary)
                    .liveNumber()
                    .frame(minWidth: 36, alignment: .trailing)
            case .done:
                Text(title)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 320)
                    .fixedSize(horizontal: true, vertical: false)
                if let note {
                    Text(note)
                        .foregroundStyle(.secondary)
                        .help(noteHelp ?? "")
                }
            case .failed(let failure):
                VStack(alignment: .leading, spacing: Space.s) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(failure.title)
                            .fontWeight(.medium)
                        if !failure.advice.isEmpty {
                            Text(failure.advice)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: Space.m) {
                        // Inside the glass, so it can't take a glass style of its own.
                        if let action = failure.action, let perform {
                            Button(action.title) { perform(action) }
                                .buttonStyle(.bordered)
                                .controlSize(.regular)
                        }
                        CopyErrorDetails(report: ErrorReport.Copyable(failure))
                    }
                }
                .frame(maxWidth: 340, alignment: .leading)
                if let dismiss {
                    Button("Dismiss", systemImage: "xmark", action: dismiss)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .fontWeight(.semibold)
                        .help("Dismiss")
                }
            }
        }
        .font(.callout)
        .accessibilityElement(children: perform == nil ? .combine : .contain)
    }

    private var isFailure: Bool {
        if case .failed = phase { true } else { false }
    }
}

/// One glyph per state, shared by the capsule and the batch rows: a ring while running, a green
/// check when done, and Checkup's caution triangle for every failure.
struct ActivityGlyph: View {
    enum State: Equatable { case waiting, running(Double), done, failed, stopped }

    let state: State
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ state: State) { self.state = state }

    init(_ phase: ActivityPhase) {
        switch phase {
        case .running(let progress): state = .running(progress)
        case .done: state = .done
        case .failed: state = .failed
        }
    }

    var body: some View {
        Group {
            switch state {
            case .waiting:
                Image(systemName: "clock").foregroundStyle(.secondary)
            case .running(let progress):
                ProgressRing(progress: progress)
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    // A small settle, not a pop from nothing; just the fade under Reduce Motion.
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.85).combined(with: .opacity))
            case .failed:
                Image(systemName: CheckupFinding.Severity.caution.symbol)
                    .foregroundStyle(CheckupFinding.Severity.caution.color)
            case .stopped:
                Image(systemName: "minus.circle").foregroundStyle(.secondary)
            }
        }
        .frame(width: 18)
        .accessibilityHidden(true)
    }
}

struct ProgressRing: View {
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
