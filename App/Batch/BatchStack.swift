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
                Text(header)
                    .font(.callout.weight(.semibold))
                    .liveNumber()
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
        return queue.isActive
            ? String(localized: "Extracting \(min(queue.finishedCount + 1, total)) of \(total)")
            : total == 1 ? String(localized: "1 archive done") : String(localized: "\(total) archives done")
    }
}

private struct BatchRow: View {
    let job: BatchQueue.Job
    let queue: BatchQueue

    var body: some View {
        HStack(spacing: Space.s) {
            status.frame(width: 18)
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
            }
            Spacer(minLength: 0)
            switch job.phase {
            case .waiting, .running:
                Button("Stop", systemImage: "xmark") { queue.cancel(job.id) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Stop extracting “\(job.name)”")
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

    @ViewBuilder
    private var status: some View {
        switch job.phase {
        case .waiting:
            Image(systemName: "clock").foregroundStyle(.secondary)
        case .running(let progress):
            ProgressView(value: progress).progressViewStyle(.circular).controlSize(.mini)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
        case .cancelled:
            Image(systemName: "minus.circle").foregroundStyle(.secondary)
        }
    }

    private var detail: String {
        switch job.phase {
        case .waiting: String(localized: "Waiting")
        case .running(let progress): progress.formatted(.percent.precision(.fractionLength(0)))
        case .done:
            job.placed.isEmpty ? String(localized: "Nothing new to extract")
                : String(localized: "Extracted to \(FileManager.default.displayName(atPath: job.destination.path))")
        case .failed(let message): message
        case .cancelled: String(localized: "Stopped")
        }
    }
}
