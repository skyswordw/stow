import SwiftUI

/// Compact progress for a batch of archives: one glass panel in the window's corner, a row per
/// archive. Rows don't animate as numbers change; the panel rises in and out.
///
/// The header says how the batch went in words (a stopped batch never reads as done) and, once
/// anything stopped or failed, tallies each outcome under it. Collapsed, the panel keeps the rows
/// that need someone in view: failures, then the archive being extracted, then the rest in order.
/// Show All lists every row in a short scrolling region; Clear Results sits apart at the bottom.
struct BatchStack: View {
    let queue: BatchQueue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showsAllResults = DemoScene.batchStartsExpanded
    private let visibleRows = 4
    /// Four and a half rows: the cut row says the list scrolls.
    private let expandedHeight: CGFloat = 164

    var body: some View {
        ZStack {
            if !queue.jobs.isEmpty {
                panel.transition(.rise(reduceMotion: reduceMotion))
            }
        }
        .padding(Space.l)
        .animation(Motion.presence(!queue.jobs.isEmpty, reduceMotion: reduceMotion), value: queue.jobs.isEmpty)
        .onChange(of: queue.jobs.count) { _, count in
            if count <= visibleRows { showsAllResults = false }
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            header
            rows
            if hasFooter { footer }
        }
        .padding(Space.m)
        .frame(width: 320)
        .accessibleGlass(in: .rect(cornerRadius: Radius.panel))
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            ActivityGlyph(summary.glyph)
                // The glyph sits on the headline, not between it and the tally.
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(.callout.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                if !tally.isEmpty {
                    HStack(spacing: Space.m) {
                        ForEach(tally, id: \.symbol) { outcome in
                            Label {
                                Text(outcome.words).liveNumber()
                            } icon: {
                                Image(systemName: outcome.symbol).foregroundStyle(outcome.color)
                            }
                            .labelStyle(TallyLabelStyle())
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(([headline] + tally.map(\.words)).joined(separator: ", "))
            Spacer(minLength: Space.s)
            if queue.isActive {
                Button("Stop All") { queue.cancelAll() }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Stop unfinished jobs. Archives already extracted are kept.")
            }
        }
    }

    private var summary: BatchQueue.Summary { queue.summary }

    /// The outcome that matters most, in words. Counts come from `BatchQueue.Summary`.
    private var headline: String {
        if summary.pending > 0 || (summary.stopped == 0 && summary.failed == 0) { return summary.title }
        if summary.failed > 0 { return String(localized: "\(summary.failed) archives need attention") }
        if summary.completed == 0 { return String(localized: "Extraction stopped") }
        return String(localized: "Stopped before all were extracted")
    }

    private struct Outcome {
        let symbol: String
        let color: Color
        let words: String
    }

    /// Every outcome with a count, once anything stopped or failed. All-success batches don't need it.
    private var tally: [Outcome] {
        guard summary.stopped + summary.failed > 0 else { return [] }
        var outcomes: [Outcome] = []
        if summary.completed > 0 {
            outcomes.append(Outcome(symbol: "checkmark.circle.fill", color: .green,
                                    words: String(localized: "\(summary.completed) extracted")))
        }
        if summary.stopped > 0 {
            outcomes.append(Outcome(symbol: "minus.circle", color: .secondary,
                                    words: String(localized: "\(summary.stopped) stopped")))
        }
        if summary.failed > 0 {
            outcomes.append(Outcome(symbol: CheckupFinding.Severity.caution.symbol,
                                    color: CheckupFinding.Severity.caution.color,
                                    words: String(localized: "\(summary.failed) failed")))
        }
        return outcomes
    }

    // MARK: Rows

    @ViewBuilder private var rows: some View {
        if showsAllResults {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s) {
                    ForEach(queue.jobs) { job in BatchRow(job: job, queue: queue) }
                }
            }
            .frame(maxHeight: expandedHeight)
            .fixedSize(horizontal: false, vertical: true)
            .scrollBounceBehavior(.basedOnSize)
            .scrollEdgeEffectStyle(.soft, for: .vertical)
            .transition(.opacity)
        } else {
            ForEach(collapsedJobs) { job in BatchRow(job: job, queue: queue) }
        }
    }

    /// Up to four rows, in queue order, chosen so a failure or the running archive is never the one
    /// hidden behind Show All.
    private var collapsedJobs: [BatchQueue.Job] {
        let jobs = queue.jobs
        guard jobs.count > visibleRows else { return jobs }
        func rank(_ job: BatchQueue.Job) -> Int {
            switch job.phase {
            case .failed: 0
            case .running: 1
            default: 2
            }
        }
        let kept = jobs.indices
            .sorted { (rank(jobs[$0]), $0) < (rank(jobs[$1]), $1) }
            .prefix(visibleRows)
            .sorted()
        return kept.map { jobs[$0] }
    }

    // MARK: Footer

    private var canExpand: Bool { queue.jobs.count > visibleRows }
    private var hasFooter: Bool { canExpand || !queue.isActive }

    /// Show All on the leading side, Clear Results quietly on the trailing side: the batch's
    /// results stay until someone clears them.
    private var footer: some View {
        HStack(spacing: Space.s) {
            if canExpand {
                Button {
                    // Growing the list is movement: none under Reduce Motion or from the keyboard.
                    withAnimation(reduceMotion || Motion.byKeyboard ? nil : Motion.appear) {
                        showsAllResults.toggle()
                    }
                } label: {
                    Label(showsAllResults ? String(localized: "Show Fewer Results")
                          : String(localized: "Show All \(queue.jobs.count) Results"),
                          systemImage: "chevron.down")
                        .labelStyle(DisclosureLabelStyle(isExpanded: showsAllResults))
                }
                .foregroundStyle(.tint)
                .accessibilityLabel(showsAllResults ? String(localized: "Show Fewer Results")
                                    : String(localized: "Show All \(queue.jobs.count) Results"))
            }
            Spacer(minLength: Space.s)
            if !queue.isActive {
                Button("Clear Results") {
                    queue.clearFinished()
                    showsAllResults = false
                }
                .foregroundStyle(.secondary)
                .help("Remove these results from the list. Extracted files are kept.")
            }
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .font(.callout)
        .padding(.top, Space.xs)
    }
}

/// A tally entry: a small glyph hugging its count.
private struct TallyLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.imageScale(.small).accessibilityHidden(true)
            configuration.title
        }
    }
}

/// Words first, then a chevron that turns over when the list is open.
private struct DisclosureLabelStyle: LabelStyle {
    let isExpanded: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon
                .imageScale(.small)
                .fontWeight(.semibold)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                .accessibilityHidden(true)
        }
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
