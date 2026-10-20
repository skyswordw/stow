import SwiftUI

@Observable
final class BrowserModel {
    enum ViewMode: String, CaseIterable, Identifiable {
        case grid, list
        var id: Self { self }
    }

    struct Activity: Equatable {
        enum Phase: Equatable { case running(Double), done }
        let step: NextStep
        let itemCount: Int
        var phase: Phase
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

    /// Simulated until the engine lands: drives the progress capsule through its states.
    func run(_ step: NextStep, on entries: [ArchiveEntry]? = nil) {
        let items = entries ?? (selectedEntries.isEmpty ? archive.files : selectedEntries)
        activityTask?.cancel()
        activity = Activity(step: step, itemCount: items.count, phase: .running(0))
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

    func dismissActivity() {
        activityTask?.cancel()
        activity = nil
    }
}
