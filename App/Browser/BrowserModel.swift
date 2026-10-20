import SwiftUI

@Observable
final class BrowserModel {
    enum ViewMode: String, CaseIterable, Identifiable {
        case grid, list
        var id: Self { self }
    }

    struct Activity: Equatable {
        enum Phase: Equatable { case running(Double), done, failed(String) }
        let step: NextStep
        let itemCount: Int
        var phase: Phase
        /// What a finished extraction put on disk, for Show in Finder.
        var placed: [URL] = []

        var doneTitle: String {
            guard step == .extract, let folder = placed.first?.deletingLastPathComponent() else {
                return step.doneTitle
            }
            return "Extracted to \(FileManager.default.displayName(atPath: folder.path))"
        }
    }

    var archive: Archive
    var folder = ""
    var selection: Set<ArchiveEntry.ID> = []
    var viewMode: ViewMode = .grid
    var query = ""
    var showInspector = true
    private(set) var activity: Activity?

    private var activityTask: Task<Void, Never>?

    init(archive: Archive) {
        self.archive = archive
    }

    var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var visibleEntries: [ArchiveEntry] {
        isSearching ? archive.search(query) : archive.children(of: folder)
    }

    var selectedEntries: [ArchiveEntry] {
        visibleEntries.filter { selection.contains($0.id) }
    }

    var title: String {
        if isSearching { return "Search" }
        return folder.isEmpty ? archive.name : (folder as NSString).lastPathComponent
    }

    var subtitle: String {
        let count = visibleEntries.count
        return isSearching ? "\(count) results in \(archive.name)" : "\(count) items"
    }

    func open(_ entry: ArchiveEntry) {
        if entry.isFolder {
            query = ""
            folder = entry.path
            selection = []
        } else if entry.kind == .archive {
            run(.openInside, on: [entry])
        } else {
            selection = [entry.id]
            run(.quickLook, on: [entry])
        }
    }

    func goUp() {
        guard !folder.isEmpty else { return }
        let previous = folder
        folder = (folder as NSString).deletingLastPathComponent
        selection = [previous]
    }

    /// Extracts the selection, or everything when nothing is selected.
    func run(_ step: NextStep, on entries: [ArchiveEntry]? = nil) {
        let items = entries ?? (selectedEntries.isEmpty ? archive.files : selectedEntries)
        if step == .extract, archive.source != nil {
            extract(selectedEntries.isEmpty && entries == nil ? nil : items)
        } else {
            simulate(step, itemCount: items.count)
        }
    }

    func extractAll() {
        if archive.source != nil {
            extract(nil)
        } else {
            simulate(.extract, itemCount: archive.files.count)
        }
    }

    /// Asks where, then extracts through the engine; nil extracts everything.
    private func extract(_ selection: [ArchiveEntry]?) {
        activityTask?.cancel()
        let itemCount = selection?.count ?? archive.files.count
        activityTask = Task { [weak self] in
            guard let self, let destination = await ExtractDestination.choose(for: archive) else { return }
            activity = Activity(step: .extract, itemCount: itemCount, phase: .running(0))
            do {
                let result = try await Extraction.run(archive, selection: selection, to: destination) { fraction in
                    Task { @MainActor in self.advance(to: fraction) }
                }
                archive.record(Checkup.findings(for: result.report))
                activity?.placed = result.placed
                withAnimation(Motion.appear) { activity?.phase = .done }
            } catch {
                let error = EngineError(error)
                withAnimation(Motion.appear) {
                    if error.failure == .cancelled {
                        activity = nil
                    } else {
                        activity?.phase = .failed(error.message)
                    }
                }
                return
            }
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(Motion.appear) { activity = nil }
        }
    }

    private func advance(to fraction: Double) {
        guard case .running(let current) = activity?.phase, fraction > current else { return }
        withAnimation(.linear(duration: 0.1)) { activity?.phase = .running(fraction) }
    }

    /// Steps that don't have an engine behind them yet (and every step on sample data) run a
    /// stand-in progress so the capsule's states can be designed and reviewed.
    private func simulate(_ step: NextStep, itemCount: Int) {
        activityTask?.cancel()
        activity = Activity(step: step, itemCount: itemCount, phase: .running(0))
        activityTask = Task { [weak self] in
            for tick in 1...20 {
                try? await Task.sleep(for: .milliseconds(55))
                guard !Task.isCancelled else { return }
                withAnimation(.linear(duration: 0.055)) {
                    self?.activity?.phase = .running(Double(tick) / 20)
                }
            }
            withAnimation(Motion.appear) { self?.activity?.phase = .done }
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            withAnimation(Motion.appear) { self?.activity = nil }
        }
    }

    /// Stops a running step; a cancelled extraction leaves nothing behind.
    func cancelActivity() {
        activityTask?.cancel()
        withAnimation(Motion.appear) { activity = nil }
    }

    func showInFinder() {
        if let placed = activity?.placed, !placed.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(placed)
        }
        dismissActivity()
    }

    func dismissActivity() {
        activityTask?.cancel()
        activity = nil
    }
}
