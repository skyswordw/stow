import AppKit

/// Measures what scrolling costs: `-StowScrollBenchmark YES` moves the browser's main scroll view
/// a fixed distance per step and times the main thread's work for each step — scroll, layout of
/// the newly visible rows, drawing. A step under one frame (8.3 ms at 120 Hz) can't drop a frame
/// on the main thread. A design-review and performance tool, not part of the app's behaviour.
enum ScrollBenchmark {
    static func run(in window: NSWindow, step: CGFloat = 90, steps: Int = 300) async -> String {
        guard let scrollView = largestScrollView(in: window.contentView) else { return "no scroll view" }
        var costs: [Double] = []
        let clip = scrollView.contentView
        for _ in 0..<steps {
            let maxY = (scrollView.documentView?.frame.height ?? 0) - clip.bounds.height
            guard clip.bounds.origin.y < maxY else { break }
            let start = ContinuousClock.now
            clip.scroll(to: CGPoint(x: 0, y: min(maxY, clip.bounds.origin.y + step)))
            scrollView.reflectScrolledClipView(clip)
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            let cost = ContinuousClock.now - start
            costs.append(Double(cost.components.attoseconds) / 1e15 + Double(cost.components.seconds) * 1000)
            // Let SwiftUI settle what the step changed (lazy rows appearing, thumbnails starting).
            await Task.yield()
        }
        guard !costs.isEmpty else { return "nothing to scroll" }
        let sorted = costs.sorted()
        let over = costs.filter { $0 > 8.3 }.count
        return String(format: "%d steps of %.0fpt to %.0fpt — main thread per step: median %.1f ms, p95 %.1f ms, max %.1f ms; %d over 8.3 ms",
                      costs.count, step, clip.bounds.origin.y, sorted[sorted.count / 2],
                      sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))], sorted.last!, over)
    }

    private static func largestScrollView(in view: NSView?) -> NSScrollView? {
        guard let view else { return nil }
        var best = view as? NSScrollView
        for sub in view.subviews {
            if let candidate = largestScrollView(in: sub),
               (candidate.documentView?.frame.height ?? 0) > (best?.documentView?.frame.height ?? 0) {
                best = candidate
            }
        }
        return best
    }
}
