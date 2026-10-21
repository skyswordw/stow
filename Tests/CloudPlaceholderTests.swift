import Foundation
import Testing
@testable import Stow

/// Opening an iCloud placeholder: asked for once, progress shown, opened when it's here, and
/// Cancel stops the wait. The system is faked; a real iCloud download is a manual test (#38).
@Suite("Cloud placeholders")
@MainActor
struct CloudPlaceholderTests {
    /// A placeholder that turns local after `polls` checks, with fractions along the way.
    final class FakeCloud {
        var polls: Int
        var started = 0
        var checks = 0
        var failure: String?
        var refuses = false
        var fractions: [Double?]

        init(polls: Int, fractions: [Double?] = []) {
            self.polls = polls
            self.fractions = fractions
        }

        var probe: CloudPlaceholder.Probe {
            CloudPlaceholder.Probe(
                state: { _ in
                    self.checks += 1
                    return self.checks > self.polls ? .local : .placeholder
                },
                startDownload: { _ in
                    if self.refuses { throw CocoaError(.ubiquitousFileUnavailable) }
                    self.started += 1
                },
                fraction: { _ in self.fractions.isEmpty ? nil : self.fractions.removeFirst() },
                failure: { _ in self.failure }
            )
        }
    }

    let url = URL(filePath: "/Users/me/Library/Mobile Documents/com~apple~CloudDocs/Field Recordings.zip")

    @Test func filesOnThisMacOpenWithoutWaiting() async throws {
        let cloud = FakeCloud(polls: 0)
        var reports = 0
        try await CloudPlaceholder.waitForDownload(url, probe: cloud.probe, interval: .milliseconds(1)) { _ in reports += 1 }
        #expect(cloud.started == 0 && reports == 0)
    }

    @Test func placeholdersDownloadWithProgressThenOpen() async throws {
        let cloud = FakeCloud(polls: 3, fractions: [0.25, nil, 0.75])
        var reports: [Double?] = []
        try await CloudPlaceholder.waitForDownload(url, probe: cloud.probe, interval: .milliseconds(1)) { reports.append($0) }
        #expect(cloud.started == 1)
        // nil first (show the card), then what the system said, in order.
        #expect(reports == [nil, 0.25, nil])
    }

    @Test func cancelStopsWaiting() async {
        let cloud = FakeCloud(polls: .max)
        let download = CloudDownload(url: url)
        await #expect(throws: EngineError(.cancelled)) {
            try await CloudPlaceholder.waitForDownload(self.url, probe: cloud.probe, interval: .milliseconds(1),
                                                       isCancelled: { download.isCancelled }) { _ in download.cancel() }
        }
    }

    @Test func cancellingTheTaskStopsWaitingToo() async {
        let cloud = FakeCloud(polls: .max)
        let task = Task { @MainActor in
            try await CloudPlaceholder.waitForDownload(self.url, probe: cloud.probe, interval: .milliseconds(5)) { _ in }
        }
        try? await Task.sleep(for: .milliseconds(30))
        task.cancel()
        await #expect(throws: EngineError(.cancelled)) { try await task.value }
    }

    @Test func aFailedDownloadSaysWhy() async {
        let cloud = FakeCloud(polls: .max)
        cloud.failure = "You’re offline."
        let error = await #expect(throws: EngineError.self) {
            try await CloudPlaceholder.waitForDownload(self.url, probe: cloud.probe, interval: .milliseconds(1)) { _ in }
        }
        #expect(error?.failure == .failed)
        #expect(error?.message.contains("Field Recordings.zip") == true && error?.message.contains("You’re offline.") == true)

        let refusing = FakeCloud(polls: .max)
        refusing.refuses = true
        await #expect(throws: EngineError.self) {
            try await CloudPlaceholder.waitForDownload(self.url, probe: refusing.probe, interval: .milliseconds(1)) { _ in }
        }
    }

    @Test func ordinaryFilesAreLocal() throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let file = folder.url.appending(path: "a.zip")
        try Data("PK".utf8).write(to: file)
        #expect(CloudPlaceholder.state(of: file) == .local)
    }

    @Test func titlesSayWhereItComesFrom() {
        let icloud = CloudDownload(url: url)
        #expect(icloud.isICloud && icloud.title == "Downloading “Field Recordings.zip” from iCloud")
        let other = CloudDownload(url: URL(filePath: "/Users/me/Library/CloudStorage/Dropbox/a.zip"))
        #expect(!other.isICloud && other.title == "Downloading “a.zip”")
        #expect(icloud.fraction == nil && !icloud.isCancelled)
    }
}
