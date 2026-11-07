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
    var passwords = PasswordHook.none
    /// Production aftercare remains preference-driven. Tests inject a recorder instead of Trash.
    var aftercare: ([ArchiveAftercare.Source], String) async -> Void = { sources, action in
        _ = await ArchiveAftercare.apply(Preferences.current.afterExtractAll, key: Preferences.Key.afterExtractAll,
                                         sources: sources, action: action)
    }

    var isActive: Bool { jobs.contains { !$0.isFinished } }
    var finishedCount: Int { jobs.filter(\.isFinished).count }

    /// Terminal outcomes are distinct: stopping a job never counts as successful extraction.
    struct Summary {
        var completed = 0
        var stopped = 0
        var failed = 0
        var pending = 0
        var progress = 0.0

        init(_ jobs: [Job]) {
            for job in jobs {
                switch job.phase {
                case .done: completed += 1; progress += 1
                case .cancelled: stopped += 1; progress += 1
                case .failed: failed += 1; progress += 1
                case .waiting: pending += 1
                case .running(let fraction): pending += 1; progress += fraction
                }
            }
            progress /= Double(max(jobs.count, 1))
        }

        var title: String {
            let finished = completed + stopped + failed
            if pending > 0 { return String(localized: "\(finished) of \(finished + pending) archives finished") }
            if stopped == 0, failed == 0 {
                return completed == 1 ? String(localized: "1 archive done") : String(localized: "\(completed) archives done")
            }
            return String(localized: "Completed: \(completed) · Stopped: \(stopped) · Failed: \(failed)")
        }

        var glyph: ActivityGlyph.State {
            if pending > 0 { return .running(progress) }
            if failed > 0 { return .failed }
            if stopped > 0 { return .stopped }
            return .done
        }
    }

    var summary: Summary { Summary(jobs) }

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
            // A retry or another drop can arrive while the aftercare prompt is open.
            if self?.jobs.contains(where: { $0.phase == .waiting }) == true { self?.startWorker() }
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
        let session = BatchPasswordSession()
        var extracted: [ArchiveAftercare.Source] = []
        while let next = jobs.first(where: { $0.phase == .waiting }) {
            if let source = await run(next, policy, session) { extracted.append(source) }
        }
        session.clear()
        let count = extracted.count
        // A new enqueue during aftercare owns its own grants until its worker finishes.
        let completedScopes = scoped
        scoped.removeAll()
        await aftercare(extracted, count == 1 ? String(localized: "It was extracted.") : String(localized: "All \(count) were extracted."))
        for url in completedScopes { url.stopAccessingSecurityScopedResource() }
        // Results remain available until Clear, including stopped jobs and offscreen rows.
    }

    /// Only a complete extraction returns a source eligible for cleanup.
    private func run(_ job: Job, _ policy: ConflictPolicy, _ session: BatchPasswordSession) async -> ArchiveAftercare.Source? {
        update(job.id) { $0.phase = .running(0) }
        var source: ArchiveAftercare.Source?
        let passwords = passwords
        let task = Task<Extraction.Result, any Error> { [weak self] in
            try await session.retrying(job.url, passwords: passwords) { password in
                let listing = try await ArchiveEngine.shared.list(job.url, password: password)
                var archive = Archive(listing: listing, url: job.url)
                archive.source?.password = password
                // Listing acquires any required split-folder grant. Capture before extraction,
                // not afterward: replaced archives must never be mistaken for the extracted input.
                source = ArchiveAftercare.Source.capture(job.url)
                return try await Extraction.run(archive, selection: nil, to: job.destination,
                                                options: .current(resolve: policy.resolver)) { fraction in
                    Task { @MainActor in self?.advance(job.id, to: fraction) }
                }
            }
        }
        running[job.id] = task
        defer { running[job.id] = nil }
        do {
            let result = try await task.value
            update(job.id) {
                $0.placed = result.placed
                $0.phase = result.isComplete ? .done : .failed(Failure(
                    String(localized: "Some items were not extracted."),
                    advice: String(localized: "The original archive was kept. Review the extracted files before trying again."),
                    action: .tryAgain, code: ErrorCode(.extract, .unknown)))
            }
            return result.isComplete ? source : nil
        } catch {
            let error = EngineError(error)
            let failure = Failure(error, .extract, name: job.name, destination: job.destination)
            update(job.id) { $0.phase = error.failure == .cancelled ? .cancelled : .failed(failure) }
            return nil
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

/// Successful passwords belong to one drain of the queue, never to another batch or a static
/// cache. Validate listing AND extraction before reusing one: a ZIP's public names prove nothing.
final class BatchPasswordSession {
    private(set) var successful: [String] = []

    func clear() { successful.removeAll() }

    func retrying<T>(_ url: URL, passwords: PasswordHook,
                     _ operation: (String?) async throws -> T) async throws(EngineError) -> T {
        var candidates = successful
        let recalled = ArchivePasswordVault.recalled(for: url)
        if let recalled, !candidates.contains(recalled) { candidates.insert(recalled, at: 0) }
        var password: String?
        var manual = false
        while true {
            do {
                if Task.isCancelled { throw EngineError(.cancelled) }
                let result = try await operation(password)
                if Task.isCancelled { throw EngineError(.cancelled) }
                if let password {
                    successful.removeAll { $0 == password }
                    successful.insert(password, at: 0)
                    ArchivePasswordVault.remember(password, for: url)
                }
                return result
            } catch {
                let error = EngineError(error)
                guard !Task.isCancelled else { throw EngineError(.cancelled) }
                guard error.needsPassword else { throw error }
                if let password, password == recalled { ArchivePasswordVault.forget(url: url) }
                if !candidates.isEmpty {
                    password = candidates.removeFirst()
                    continue
                }
                guard passwords.isWired else { throw error }
                // A Browser request in this session owns its question until answered. Never
                // replace it, and cancellation while waiting must not dismiss somebody else's UI.
                while passwords.isAsking {
                    do { try await Task.sleep(for: .milliseconds(40)) }
                    catch { throw EngineError(.cancelled) }
                }
                if Task.isCancelled { throw EngineError(.cancelled) }
                guard let next = await passwords.ask(url.lastPathComponent, .batchExtract, manual) else {
                    throw EngineError(.cancelled)
                }
                password = next
                manual = true
            }
        }
    }
}
