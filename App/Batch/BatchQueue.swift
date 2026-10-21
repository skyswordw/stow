import SwiftUI

/// Several archives extracted one after another into one folder, each into its own (Extract All)
/// place. Conflict answers with "do the same" hold for the whole batch, and keeping or trashing the
/// archives is asked once at the end.
@Observable
final class BatchQueue {
    struct Job: Identifiable, Equatable {
        enum Phase: Equatable { case waiting, running(Double), done, failed(Failure), cancelled }

        let id = UUID()
        let url: URL
        var destination: URL
        var phase: Phase = .waiting
        var placed: [URL] = []

        var name: String { url.lastPathComponent }
        var isFinished: Bool {
            switch phase {
            case .waiting, .running: false
            case .done, .failed, .cancelled: true
            }
        }
    }

    private(set) var jobs: [Job] = []
    private var worker: Task<Void, Never>?
    private var running: [Job.ID: Task<Extraction.Result, any Error>] = [:]
    /// Open-panel URLs need their scope claimed for reading — and for the Trash afterwards.
    private var scoped: [URL] = []

    /// Opens an archive in Stow's window (set by `AppState`), where its password can be entered.
    var onOpen: ((URL) -> Void)?

    var isActive: Bool { jobs.contains { !$0.isFinished } }
    var finishedCount: Int { jobs.filter(\.isFinished).count }

    func enqueue(_ urls: [URL], into destination: URL) {
        for url in urls where url.startAccessingSecurityScopedResource() { scoped.append(url) }
        jobs += urls.map { Job(url: $0, destination: destination) }
        startWorker()
    }

    private func startWorker() {
        guard worker == nil else { return }
        worker = Task { [weak self] in
            await self?.drain()
            self?.worker = nil
        }
    }

    /// Design review only: shows rows without running anything.
    func preview(_ rows: [(String, Job.Phase)]) {
        let folder = URL(filePath: "/Users/Shared/Downloads", directoryHint: .isDirectory)
        jobs = rows.map { name, phase in
            var job = Job(url: folder.appending(path: name), destination: folder, phase: phase)
            if phase == .done { job.placed = [folder] }
            return job
        }
    }

    func cancel(_ id: Job.ID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        if jobs[index].phase == .waiting {
            jobs[index].phase = .cancelled
        } else {
            running[id]?.cancel()
        }
    }

    func cancelAll() {
        for job in jobs where !job.isFinished { cancel(job.id) }
    }

    func clearFinished() {
        jobs.removeAll(where: \.isFinished)
    }

    /// A failed archive's one next step.
    func follow(_ action: Failure.Action, for id: Job.ID) {
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        switch action {
        case .tryAgain:
            retry(id)
        case .chooseFolder:
            Task {
                guard let folder = await ExtractDestination.choose(count: 1, near: job.url) else { return }
                update(id) { $0.destination = folder }
                retry(id)
            }
        case .showInFinder:
            NSWorkspace.shared.activateFileViewerSelecting([job.url])
        case .openInFinder:
            NSWorkspace.shared.open(job.url)
        case .openInStow:
            jobs.removeAll { $0.id == id }
            onOpen?(job.url)
        }
    }

    private func retry(_ id: Job.ID) {
        // The first run gave its scope back when the batch finished.
        if let url = jobs.first(where: { $0.id == id })?.url, url.startAccessingSecurityScopedResource() { scoped.append(url) }
        update(id) { $0.phase = .waiting }
        startWorker()
    }

    func showInFinder(_ id: Job.ID) {
        guard let job = jobs.first(where: { $0.id == id }), !job.placed.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(job.placed)
    }

    private func drain() async {
        let policy = ConflictPolicy()
        var extracted: [URL] = []
        while let next = jobs.first(where: { $0.phase == .waiting }) {
            if await run(next, policy) { extracted.append(next.url) }
        }
        let count = extracted.count
        _ = await ArchiveAftercare.apply(Preferences.current.afterExtractAll, key: Preferences.Key.afterExtractAll,
                                         to: extracted, action: count == 1 ? String(localized: "It was extracted.") : String(localized: "All \(count) were extracted."))
        for url in scoped { url.stopAccessingSecurityScopedResource() }
        scoped.removeAll()
        // Leave the results up for a moment, then tidy away if nothing failed.
        try? await Task.sleep(for: .seconds(6))
        if !isActive, !jobs.contains(where: { if case .failed = $0.phase { true } else { false } }) {
            withAnimation(Motion.current(Motion.exit)) { clearFinished() }
        }
    }

    /// True when the archive was extracted.
    private func run(_ job: Job, _ policy: ConflictPolicy) async -> Bool {
        update(job.id) { $0.phase = .running(0) }
        let task = Task<Extraction.Result, any Error> { [weak self] in
            let listing = try await ArchiveEngine.shared.list(job.url)
            let archive = Archive(listing: listing, url: job.url)
            return try await Extraction.run(archive, selection: nil, to: job.destination,
                                            options: .current(resolve: policy.resolver)) { fraction in
                Task { @MainActor in self?.advance(job.id, to: fraction) }
            }
        }
        running[job.id] = task
        defer { running[job.id] = nil }
        do {
            let result = try await task.value
            update(job.id) {
                $0.placed = result.placed
                $0.phase = .done
            }
            return true
        } catch {
            let error = EngineError(error)
            let failure = Failure(error, .extract, name: job.name, destination: job.destination)
            update(job.id) { $0.phase = error.failure == .cancelled ? .cancelled : .failed(failure) }
            return false
        }
    }

    private func advance(_ id: Job.ID, to fraction: Double) {
        update(id) { job in
            if case .running(let current) = job.phase, fraction > current { job.phase = .running(fraction) }
        }
    }

    private func update(_ id: Job.ID, _ change: (inout Job) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[index])
    }
}
