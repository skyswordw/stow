import Foundation
import Testing
@testable import Stow

@Suite("Batch results")
@MainActor
struct BatchSummaryTests {
    @Test func stoppedJobsNeverReportSuccess() {
        let queue = BatchQueue()
        queue.preview([("a.zip", .cancelled), ("b.zip", .cancelled)])
        #expect(!queue.isActive)
        #expect(queue.summary.completed == 0 && queue.summary.stopped == 2)
        #expect(queue.summary.glyph == .stopped)
        #expect(queue.summary.title == "Completed: 0 · Stopped: 2 · Failed: 0")
    }

    @Test func laterFailuresAndMixedOutcomesRemainInTheResults() {
        let queue = BatchQueue()
        let failure = Failure(EngineError(.missingVolume), .extract, name: "last.7z.001")
        queue.preview([("a.zip", .done), ("b.zip", .done), ("c.zip", .cancelled),
                       ("d.zip", .cancelled), ("last.7z.001", .failed(failure))])
        #expect(queue.jobs.count == 5)
        #expect(queue.jobs.last?.phase == .failed(failure))
        #expect(queue.summary.glyph == .failed)
        #expect(queue.summary.title == "Completed: 2 · Stopped: 2 · Failed: 1")
        queue.clearFinished()
        #expect(queue.jobs.isEmpty)
    }

    @Test func stoppingQueuedWorkPreservesCompletedResults() {
        let queue = BatchQueue()
        queue.preview([("a.zip", .done), ("b.zip", .waiting), ("c.zip", .waiting)])
        let placed = queue.jobs[0].placed
        queue.cancelAll()
        #expect(queue.jobs[0].phase == .done && queue.jobs[0].placed == placed)
        #expect(queue.summary.completed == 1 && queue.summary.stopped == 2)
        #expect(queue.summary.glyph == .stopped)
    }

    @Test func activeAndSuccessfulStatesStayDistinct() {
        let queue = BatchQueue()
        queue.preview([("a.zip", .done), ("b.zip", .running(0.5))])
        #expect(queue.summary.glyph == .running(0.75))
        #expect(queue.summary.title == "1 of 2 archives finished")
        queue.preview([("a.zip", .done), ("b.zip", .done)])
        #expect(queue.summary.glyph == .done)
        #expect(queue.summary.title == "2 archives done")
    }
}
