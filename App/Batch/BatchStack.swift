import SwiftUI

/// Compact progress for a batch of archives: one glass panel in the window's corner, a row per
/// archive. Rows don't animate as numbers change; the panel rises in and out.
struct BatchStack: View {
    let queue: BatchQueue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showsAllResults = false
    private let visibleRows = 4

    var body: some View {
        ZStack {
            if !queue.jobs.isEmpty {
                panel.transition(.rise(reduceMotion: reduceMotion))
            }
        }
        .padding(Space.l)
        .animation(Motion.presence(!queue.jobs.isEmpty, reduceMotion: reduceMotion), value: queue.jobs.isEmpty)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                HStack(spacing: Space.s) {
                    ActivityGlyph(queue.summary.glyph)
                    Text(queue.summary.title).font(.callout.weight(.medium))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(queue.summary.title)
                Spacer()
                if queue.isActive {
                    Button("Stop All") { queue.cancelAll() }
                        .help("Stop unfinished jobs. Archives already extracted are kept.")
                } else {
                    Button("Clear Results") { queue.clearFinished(); showsAllResults = false }
                        .help("Remove these results from the list. Extracted files are kept.")
                }
            }
            .buttonStyle(.borderless)
            .controlSize(.small)

            if showsAllResults {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Space.s) {
                        ForEach(queue.jobs) { job in BatchRow(job: job, queue: queue) }
                    }
                }
                .frame(maxHeight: 240)
            } else {
                ForEach(queue.jobs.prefix(visibleRows)) { job in
                    BatchRow(job: job, queue: queue)
                }
            }
            if queue.jobs.count > visibleRows {
                Button(showsAllResults ? String(localized: "Show Fewer Results")
                       : String(localized: "Show All \(queue.jobs.count) Results")) {
                    showsAllResults.toggle()
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(Space.m)
        .frame(width: 320)
        .accessibleGlass(in: .rect(cornerRadius: Radius.panel))
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
                    .accessibilityLabel(String(localized: "Stop"))
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Stop extracting “\(job.name)”")
            case .failed(let failure):
                if let action = failure.action {
                    Button(action.title, systemImage: action.symbol) { queue.follow(action, for: job.id) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .accessibilityLabel(action.title)
                        .help(action.title)
                }
            case .done where !job.placed.isEmpty:
                Button("Show in Finder", systemImage: "folder") { queue.showInFinder(job.id) }
                    .accessibilityLabel(String(localized: "Show in Finder"))
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Show in Finder")
            default:
                EmptyView()
            }
        }
        // #93: same leaf pattern as ActivityLabel / TrayRow — nested name+detail Texts under
        // contain re-enter AX label resolution on failure rows.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityValue(progressValue)
        .accessibilityActions {
            switch job.phase {
            case .waiting, .running:
                Button("Stop") { queue.cancel(job.id) }
            case .failed(let failure):
                if let action = failure.action {
                    Button(action.title) { queue.follow(action, for: job.id) }
                }
                Button("Copy Details") { ErrorReport.Copyable(failure).copy() }
            case .done where !job.placed.isEmpty:
                Button("Show in Finder") { queue.showInFinder(job.id) }
            default:
                EmptyView()
            }
        }
        .contextMenu {
            if case .failed(let failure) = job.phase {
                Button("Copy Error Details (\(failure.code.description))") { ErrorReport.Copyable(failure).copy() }
            }
        }
    }

    private var spokenLabel: String {
        switch job.phase {
        case .failed(let failure):
            return AccessibilityText.activity(title: job.name, note: AccessibilityText.failure(failure))
        case .running:
            return job.name
        default:
            return AccessibilityText.activity(title: job.name, note: detail)
        }
    }

    private var progressValue: String {
        if case .running(let progress) = job.phase {
            return AccessibilityText.progress(progress)
        }
        return ""
    }

    private var glyph: ActivityGlyph.State {
        switch job.phase {
        case .waiting: .waiting
        case .running(let progress): .running(progress)
        case .done: .done
        case .failed: .failed
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
