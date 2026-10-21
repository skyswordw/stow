import SwiftUI

/// Compact progress for a batch of archives: one glass panel in the window's corner, a row per
/// archive. Rows don't animate as numbers change; the panel rises in and out.
struct BatchStack: View {
    let queue: BatchQueue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let visibleRows = 4

    var body: some View {
        ZStack {
            if !queue.jobs.isEmpty {
                panel.transition(.rise(reduceMotion: reduceMotion))
            }
        }
        .padding(Space.l)
        .animation(Motion.resolved(Motion.appear, reduceMotion: reduceMotion), value: queue.jobs.isEmpty)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                ActivityLabel(phase: overall, title: header)
                Spacer()
                if queue.isActive {
                    Button("Stop All") { queue.cancelAll() }
                        .help("Stop — nothing is left half-extracted")
                } else {
                    Button("Clear") { queue.clearFinished() }
                }
            }
            .buttonStyle(.borderless)
            .controlSize(.small)

            ForEach(queue.jobs.prefix(visibleRows)) { job in
                BatchRow(job: job, queue: queue)
            }
            if queue.jobs.count > visibleRows {
                Text("+ \(queue.jobs.count - visibleRows) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .liveNumber()
            }
        }
        .padding(Space.m)
        .frame(width: 320)
        .glassEffect(.regular, in: .rect(cornerRadius: Radius.panel))
    }

    private var header: String {
        let total = queue.jobs.count
        let failed = queue.jobs.filter { if case .failed = $0.phase { true } else { false } }.count
        if queue.isActive { return String(localized: "Extracting \(min(queue.finishedCount + 1, total)) of \(total)") }
        if failed > 0 { return failed == 1 ? String(localized: "1 archive needs attention") : String(localized: "\(failed) archives need attention") }
        return total == 1 ? String(localized: "1 archive done") : String(localized: "\(total) archives done")
    }

    /// The whole batch as one capsule state: a ring over every archive while it runs.
    private var overall: ActivityPhase {
        let total = Double(max(queue.jobs.count, 1))
        if queue.isActive {
            let current = queue.jobs.reduce(0.0) { sum, job in
                if case .running(let progress) = job.phase { return sum + progress }
                return job.isFinished ? sum + 1 : sum
            }
            return .running(current / total)
        }
        if let failure = queue.jobs.lazy.compactMap({ job -> Failure? in
            if case .failed(let failure) = job.phase { failure } else { nil }
        }).first {
            return .failed(Failure(kind: failure.kind, title: header, advice: ""))
        }
        return .done
    }
}

private struct BatchRow: View {
    let job: BatchQueue.Job
    let queue: BatchQueue

    var body: some View {
        HStack(spacing: Space.s) {
            ActivityGlyph(glyph)
            VStack(alignment: .leading, spacing: 1) {
                Text(job.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .liveNumber()
                    .help(advice)
            }
            Spacer(minLength: 0)
            switch job.phase {
            case .waiting, .running:
                Button("Stop", systemImage: "xmark") { queue.cancel(job.id) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Stop extracting “\(job.name)”")
            case .failed(let failure):
                if let action = failure.action {
                    Button(action.title, systemImage: action.symbol) { queue.follow(action, for: job.id) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help(action.title)
                }
            case .done where !job.placed.isEmpty:
                Button("Show in Finder", systemImage: "folder") { queue.showInFinder(job.id) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Show in Finder")
            default:
                EmptyView()
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var glyph: ActivityGlyph.State {
        switch job.phase {
        case .waiting: .waiting
        case .running(let progress): .running(progress)
        case .done: .done
        case .failed(let failure): .failed(failure.symbol)
        case .cancelled: .stopped
        }
    }

    /// The whole explanation, for the pointer.
    private var advice: String {
        if case .failed(let failure) = job.phase { failure.title + ". " + failure.advice } else { "" }
    }

    private var detail: String {
        switch job.phase {
        case .waiting: String(localized: "Waiting")
        case .running(let progress): progress.formatted(.percent.precision(.fractionLength(0)))
        case .done:
            job.placed.isEmpty ? String(localized: "Nothing new to extract")
                : String(localized: "Extracted to \(FileManager.default.displayName(atPath: job.destination.path))")
        case .failed(let failure): failure.brief
        case .cancelled: String(localized: "Stopped")
        }
    }
}
