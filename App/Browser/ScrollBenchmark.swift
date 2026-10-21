import AppKit
import QuartzCore

/// Measures how smoothly the content scrolls: `-StowScrollBenchmark YES` scrolls the browser's
/// main scroll view a fixed distance every display frame for a few seconds and prints frame
/// pacing (a design-review and performance tool, not part of the app's behaviour).
final class ScrollBenchmark: NSObject {
    private let scrollView: NSScrollView
    private var link: CADisplayLink?
    private var stamps: [CFTimeInterval] = []
    private var done: (String) -> Void = { _ in }
    private let step: CGFloat
    private let frames: Int

    init(scrollView: NSScrollView, step: CGFloat = 60, frames: Int = 240) {
        self.scrollView = scrollView
        self.step = step
        self.frames = frames
    }

    static func run(in window: NSWindow) async -> String {
        guard let scrollView = largestScrollView(in: window.contentView) else { return "no scroll view" }
        guard window.screen != nil || NSScreen.main != nil else { return "no screen" }
        let benchmark = ScrollBenchmark(scrollView: scrollView)
        return await withCheckedContinuation { continuation in
            benchmark.done = { continuation.resume(returning: $0) }
            benchmark.start()
        }
    }

    private func start() {
        let screen = scrollView.window?.screen ?? NSScreen.main
        link = screen?.displayLink(target: self, selector: #selector(tick(_:)))
        link?.add(to: .main, forMode: .common)
    }

    @objc private func tick(_ link: CADisplayLink) {
        stamps.append(link.timestamp)
        let clip = scrollView.contentView
        let maxY = (scrollView.documentView?.frame.height ?? 0) - clip.bounds.height
        var origin = clip.bounds.origin
        origin.y = min(maxY, origin.y + step)
        clip.scroll(to: origin)
        scrollView.reflectScrolledClipView(clip)
        if stamps.count >= frames || origin.y >= maxY {
            link.invalidate()
            done(report(link.duration))
        }
    }

    private func report(_ frame: CFTimeInterval) -> String {
        let intervals = zip(stamps.dropFirst(), stamps).map { $0 - $1 }
        guard !intervals.isEmpty else { return "no frames" }
        let sorted = intervals.sorted()
        let average = intervals.reduce(0, +) / Double(intervals.count)
        let hitches = intervals.filter { $0 > frame * 1.5 }.count
        let distance = Int(scrollView.contentView.bounds.origin.y)
        return String(format: "scrolled %dpt in %d frames — mean %.1f ms, p95 %.1f ms, max %.1f ms, %d hitches (> %.1f ms)",
                      distance, intervals.count, average * 1000, sorted[Int(Double(sorted.count) * 0.95)] * 1000,
                      sorted.last! * 1000, hitches, frame * 1500)
    }

    private static func largestScrollView(in view: NSView?) -> NSScrollView? {
        guard let view else { return nil }
        var best: NSScrollView? = (view as? NSScrollView).flatMap { $0.hasVerticalScroller || $0.documentView != nil ? $0 : nil }
        for sub in view.subviews {
            if let candidate = largestScrollView(in: sub),
               (candidate.documentView?.frame.height ?? 0) > (best?.documentView?.frame.height ?? 0) {
                best = candidate
            }
        }
        return best
    }
}
