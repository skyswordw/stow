import SwiftUI

@Observable
final class BrowserModel {
    enum ViewMode: String, CaseIterable, Identifiable {
        case grid, list, columns
        var id: Self { self }
    }

    enum Direction { case up, down, left, right }

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

    /// One archive in the chain being browsed: the one opened, then any opened inside it.
    @Observable
    final class Level: Identifiable {
        let id = UUID()
        var archive: Archive
        var password: String?
        /// Where this archive sits in the level above; nil for the archive that was opened.
        let entryPath: String?
        fileprivate(set) var search: SearchIndex
        fileprivate(set) var indexed = 0

        init(archive: Archive, password: String? = nil, entryPath: String? = nil) {
            self.archive = archive
            self.password = password
            self.entryPath = entryPath
            search = SearchIndex(total: archive.index.visible.count + archive.index.helpers.count)
        }
    }

    /// A place in the history: which chain of archives, and which folder in the innermost.
    struct Location: Equatable {
        let levels: [Level]
        let folder: String

        static func == (lhs: Location, rhs: Location) -> Bool {
            lhs.folder == rhs.folder && lhs.levels.map(\.id) == rhs.levels.map(\.id)
        }
    }

    /// Archives inside archives open up to this deep — enough for real nesting, not for a zip quine.
    static let maxDepth = 8

    private(set) var levels: [Level]
    var folder = "" { didSet { if folder != oldValue { refresh() } } }
    var selection: Set<ArchiveEntry.ID> = []
    var viewMode: ViewMode = .grid
    var query = "" { didSet { if query != oldValue { runSearch() } } }
    var showInspector = true
    var showHelperItems = false { didSet { if showHelperItems != oldValue { refresh(); runSearch() } } }
    var isChoosingEncoding = false
    /// A hover preview to show without a pointer (design review: `-StowHover`).
    var demoHover: ArchiveEntry.ID?
    private(set) var visibleEntries: [ArchiveEntry] = []
    private(set) var activity: Activity?

    /// Where Shift-selection extends from, and where the keyboard is.
    private(set) var anchor: ArchiveEntry.ID?
    private(set) var cursor: ArchiveEntry.ID?
    /// Set when the keyboard moved somewhere off screen; views scroll to it without animating.
    var scrollTarget: ArchiveEntry.ID?
    /// Columns in the icon grid right now, for Up and Down.
    var gridColumns = 1

    private(set) var history: [Location] = []
    private(set) var historyIndex = 0

    let previews: PreviewService
    let quickLook = QuickLookController()
    let dragOut = DragOutController()
    var passwords: PasswordHook = .none

    private var positions: [ArchiveEntry.ID: Int] = [:]
    private var searchResults: [ArchiveEntry] = []
    private var searchTask: Task<Void, Never>?
    private var activityTask: Task<Void, Never>?
    private var typeahead = (text: "", at: Date.distantPast)

    init(archive: Archive, previews: PreviewService = PreviewService()) {
        let root = Level(archive: archive)
        levels = [root]
        self.previews = previews
        history = [Location(levels: levels, folder: "")]
        previews.password = { [weak self] archive in
            self?.levels.first { $0.archive.id == archive.id }?.password
        }
        quickLook.model = self
        dragOut.model = self
        refresh()
        startIndexing(root)
    }

    var level: Level { levels[levels.count - 1] }

    var archive: Archive {
        get { level.archive }
        set { level.archive = newValue }
    }

    var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Selected entries in path order (looked up, not filtered: the list may hold 100,000 rows).
    var selectedEntries: [ArchiveEntry] {
        selection.compactMap(archive.entry(at:)).sorted { $0.path < $1.path }
    }

    var title: String {
        if isSearching { return "Search" }
        return folder.isEmpty ? archive.name : (folder as NSString).lastPathComponent
    }

    var subtitle: String {
        let count = visibleEntries.count
        let items = "\(count.formatted()) \(count == 1 ? "item" : "items")"
        return isSearching ? "\(count.formatted()) results in \(archive.name)" : items
    }

    /// "Indexing… 12,000 of 40,000" while a big archive's search index builds.
    var indexingProgress: String? {
        let search = level.search
        guard level.indexed < search.total, search.total > 2_000 else { return nil }
        return "Indexing… \(level.indexed.formatted()) of \(search.total.formatted())"
    }

    // MARK: - Contents

    private func refresh() {
        visibleEntries = isSearching ? searchResults
            : archive.children(of: folder, includingHelpers: showHelperItems)
        positions = Dictionary(visibleEntries.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func runSearch() {
        searchTask?.cancel()
        guard isSearching else {
            searchResults = []
            refresh()
            return
        }
        let level = level, query = query, helpers = showHelperItems
        searchTask = Task {
            let results = await level.search.search(query, includingHelpers: helpers)
            guard !Task.isCancelled, level === self.level else { return }
            searchResults = results
            refresh()
        }
    }

    private func startIndexing(_ level: Level) {
        let entries = level.archive.index.visible + level.archive.index.helpers
        let search = level.search
        Task { [weak self, weak level] in
            await search.build(entries) { count in
                await MainActor.run {
                    level?.indexed = count
                    // Results grow as the index does; search the newly indexed part too.
                    if let self, self.isSearching, self.level === level { self.runSearch() }
                }
            }
        }
    }

    // MARK: - Navigation

    var canGoBack: Bool { historyIndex > 0 }
    var canGoForward: Bool { historyIndex < history.count - 1 }
    var canGoUp: Bool { !folder.isEmpty || levels.count > 1 }

    private var location: Location { Location(levels: levels, folder: folder) }

    /// Shows `folder` (in `levels`, default the current chain), selecting `selecting`.
    func navigate(to folder: String, levels newLevels: [Level]? = nil, selecting: Set<ArchiveEntry.ID> = [],
                  record: Bool = true) {
        let target = Location(levels: newLevels ?? levels, folder: folder)
        if record, target != location {
            history = Array(history.prefix(historyIndex + 1)) + [target]
            if history.count > 200 { history.removeFirst(history.count - 200) }
            historyIndex = history.count - 1
        }
        apply(target, selecting: selecting)
    }

    private func apply(_ target: Location, selecting: Set<ArchiveEntry.ID>) {
        searchTask?.cancel()
        query = ""
        searchResults = []
        let levelChanged = target.levels.map(\.id) != levels.map(\.id)
        levels = target.levels
        if folder != target.folder {
            folder = target.folder
        } else if levelChanged {
            refresh()
        }
        if levelChanged { quickLook.close() }
        select(selecting.isEmpty ? [] : selecting, scroll: true)
    }

    func goBack() {
        guard canGoBack else { return }
        let from = location
        historyIndex -= 1
        apply(history[historyIndex], selecting: cameFrom(from, to: history[historyIndex]))
    }

    func goForward() {
        guard canGoForward else { return }
        let from = location
        historyIndex += 1
        apply(history[historyIndex], selecting: cameFrom(from, to: history[historyIndex]))
    }

    /// Up One Level: the enclosing folder, or out of a nested archive to where it sits.
    func goUp() {
        if !folder.isEmpty {
            navigate(to: (folder as NSString).deletingLastPathComponent, selecting: [folder])
        } else if levels.count > 1, let entryPath = level.entryPath {
            navigate(to: (entryPath as NSString).deletingLastPathComponent, levels: Array(levels.dropLast()),
                     selecting: [entryPath])
        }
    }

    /// Going back out of somewhere selects the thing you went into, like Finder.
    private func cameFrom(_ from: Location, to: Location) -> Set<ArchiveEntry.ID> {
        if from.levels.count > to.levels.count, from.levels.prefix(to.levels.count).map(\.id) == to.levels.map(\.id),
           let path = from.levels[to.levels.count].entryPath {
            return Set([childOnTheWay(to: path, from: to.folder)].compactMap(\.self))
        }
        guard from.levels.map(\.id) == to.levels.map(\.id) else { return [] }
        return Set([childOnTheWay(to: from.folder, from: to.folder)].compactMap(\.self))
    }

    private func childOnTheWay(to path: String, from folder: String) -> String? {
        let prefix = folder.isEmpty ? "" : folder + "/"
        guard path.hasPrefix(prefix), path.count > prefix.count else { return nil }
        let rest = path.dropFirst(prefix.count)
        return prefix + (rest.split(separator: "/").first.map(String.init) ?? "")
    }

    /// The path bar: each archive in the chain, then the folders inside it.
    struct PathSegment: Identifiable {
        let id: String
        let title: String
        let isArchive: Bool
        let levelCount: Int
        let folder: String
        let format: ArchiveFormat?
    }

    var pathSegments: [PathSegment] {
        var segments: [PathSegment] = []
        for (index, level) in levels.enumerated() {
            segments.append(PathSegment(id: "\(index):", title: level.archive.name, isArchive: true,
                                        levelCount: index + 1, folder: "", format: level.archive.format))
            let inside = index == levels.count - 1 ? folder
                : ((levels[index + 1].entryPath ?? "") as NSString).deletingLastPathComponent
            var path = ""
            for component in inside.split(separator: "/") {
                path = path.isEmpty ? String(component) : path + "/" + component
                segments.append(PathSegment(id: "\(index):\(path)", title: String(component), isArchive: false,
                                            levelCount: index + 1, folder: path, format: nil))
            }
        }
        return segments
    }

    func go(to segment: PathSegment) {
        let target = Array(levels.prefix(segment.levelCount))
        let inside = segment.levelCount < levels.count ? levels[segment.levelCount].entryPath : (folder.isEmpty ? nil : folder)
        let came = inside.flatMap { childOnTheWay(to: $0, from: segment.folder) }
        navigate(to: segment.folder, levels: target, selecting: Set([came].compactMap(\.self)))
    }

    // MARK: - Selection

    func select(_ ids: Set<ArchiveEntry.ID>, scroll: Bool = false) {
        selection = ids
        let first = ids.min { (positions[$0] ?? .max) < (positions[$1] ?? .max) }
        anchor = first
        cursor = first
        if scroll { scrollTarget = first }
    }

    /// A click, with Finder's modifiers: ⌘ toggles, ⇧ extends from the anchor.
    func click(_ entry: ArchiveEntry, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.command) {
            if selection.contains(entry.id) { selection.remove(entry.id) } else { selection.insert(entry.id) }
            anchor = entry.id
            cursor = entry.id
        } else if modifiers.contains(.shift), let anchor, let from = positions[anchor], let to = positions[entry.id] {
            selection = Set(visibleEntries[min(from, to)...max(from, to)].map(\.id))
            cursor = entry.id
        } else {
            select([entry.id])
        }
    }

    /// A marquee drag: `ids` under the rectangle, added to `base` when ⇧ or ⌘ was held.
    func marquee(_ ids: Set<ArchiveEntry.ID>, base: Set<ArchiveEntry.ID>, toggling: Bool) {
        selection = toggling ? base.symmetricDifference(ids) : ids
        if let first = ids.min(by: { (positions[$0] ?? .max) < (positions[$1] ?? .max) }) {
            cursor = first
            if anchor == nil || !toggling { anchor = first }
        }
    }

    func position(of id: ArchiveEntry.ID) -> Int? { positions[id] }

    /// The list's table changed the selection itself; keep the keyboard's place in step.
    func selectionDidChange() {
        if let cursor, selection.contains(cursor) { return }
        let first = selection.min { (positions[$0] ?? .max) < (positions[$1] ?? .max) }
        cursor = first
        anchor = first
    }

    func selectAll() {
        selection = Set(visibleEntries.map(\.id))
    }

    /// Arrow keys: in the grid by rows and columns, in the list by rows. ⇧ extends.
    func move(_ direction: Direction, extending: Bool = false) {
        guard !visibleEntries.isEmpty else { return }
        if viewMode == .columns {
            moveInColumns(direction)
            return
        }
        let step: Int
        switch (viewMode, direction) {
        case (.grid, .left): step = -1
        case (.grid, .right): step = 1
        case (_, .up): step = viewMode == .grid ? -gridColumns : -1
        case (_, .down): step = viewMode == .grid ? gridColumns : 1
        default: return
        }
        let current = cursor.flatMap { positions[$0] }
        let next = current.map { max(0, min(visibleEntries.count - 1, $0 + step)) } ?? (step > 0 ? 0 : visibleEntries.count - 1)
        let id = visibleEntries[next].id
        if extending, let anchor, let from = positions[anchor] {
            selection = Set(visibleEntries[min(from, next)...max(from, next)].map(\.id))
            cursor = id
        } else {
            selection = [id]
            anchor = id
            cursor = id
        }
        scrollTarget = id
    }

    /// Column view: Up/Down within the column, Right into a folder, Left back to its parent.
    private func moveInColumns(_ direction: Direction) {
        guard let current = cursor.flatMap(archive.entry(at:)) ?? visibleEntries.first else { return }
        let siblings = archive.children(of: current.parent, includingHelpers: showHelperItems)
        guard cursor != nil else {
            columnSelect(current)
            return
        }
        switch direction {
        case .up, .down:
            guard let index = siblings.firstIndex(where: { $0.id == current.id }) else { return }
            let next = max(0, min(siblings.count - 1, index + (direction == .down ? 1 : -1)))
            columnSelect(siblings[next])
        case .right:
            if current.isNavigable, let first = archive.children(of: current.path, includingHelpers: showHelperItems).first {
                columnSelect(first)
            }
        case .left:
            if !current.parent.isEmpty, let parent = archive.entry(at: current.parent) { columnSelect(parent) }
        }
    }

    /// In column view a selected folder opens as the next column; a file shows beside its column.
    func columnSelect(_ entry: ArchiveEntry, modifiers: NSEvent.ModifierFlags = []) {
        if !modifiers.intersection([.command, .shift]).isEmpty, entry.parent == cursor.flatMap(archive.entry(at:))?.parent {
            let siblings = archive.children(of: entry.parent, includingHelpers: showHelperItems)
            if modifiers.contains(.command) {
                if selection.contains(entry.id) { selection.remove(entry.id) } else { selection.insert(entry.id) }
            } else if let anchor, let from = siblings.firstIndex(where: { $0.id == anchor }),
                      let to = siblings.firstIndex(where: { $0.id == entry.id }) {
                selection = Set(siblings[min(from, to)...max(from, to)].map(\.id))
            }
            cursor = entry.id
            folder = entry.parent
            return
        }
        query = ""
        folder = entry.isNavigable ? entry.path : entry.parent
        selection = [entry.id]
        anchor = entry.id
        cursor = entry.id
        scrollTarget = entry.id
    }

    /// Typing a name's first letters selects it.
    func typeSelect(_ text: String) {
        let now = Date.now
        typeahead.text = now.timeIntervalSince(typeahead.at) > 1 ? text : typeahead.text + text
        typeahead.at = now
        let prefix = SearchIndex.fold(typeahead.text)
        let pool = viewMode == .columns
            ? archive.children(of: cursor.flatMap(archive.entry(at:))?.parent ?? folder, includingHelpers: showHelperItems)
            : visibleEntries
        guard let match = pool.first(where: { SearchIndex.fold($0.name).hasPrefix(prefix) }) else { return }
        if viewMode == .columns { columnSelect(match) } else { select([match.id], scroll: true) }
    }

    // MARK: - Opening

    func open(_ entry: ArchiveEntry) {
        if entry.isNavigable {
            navigate(to: entry.path)
        } else if archive.source == nil {
            entry.kind == .archive ? run(.openInside, on: [entry]) : run(.quickLook, on: [entry])
        } else if entry.kind == .archive {
            openInside(entry)
        } else if entry.isPackage {
            select([entry.id])
            toggleQuickLook()
        } else {
            openWithDefaultApp([entry])
        }
    }

    func showPackageContents(_ entry: ArchiveEntry) {
        if entry.isFolder {
            navigate(to: entry.path)
        } else {
            openInside(entry) // .docx, .epub, .jar …: ZIPs by another name
        }
    }

    /// Space / ⌘Y. Shows the selection in the Quick Look panel; arrow keys keep moving the selection.
    func toggleQuickLook() {
        if quickLook.isVisible {
            quickLook.close()
        } else if archive.source == nil {
            if !selection.isEmpty { run(.quickLook) }
        } else if !selection.isEmpty {
            quickLook.show()
        }
    }

    /// Extracts to Stow's preview folder and opens with the default app, read-only.
    func openWithDefaultApp(_ entries: [ArchiveEntry]) {
        let files = entries.filter { !$0.isFolder }
        guard !files.isEmpty, archive.source != nil else { return }
        let archive = archive
        let large = files.reduce(Int64(0)) { $0 + $1.size } > 24 << 20
        activityTask?.cancel()
        activityTask = Task { [weak self] in
            guard let self else { return }
            if large { activity = Activity(step: .quickLook, itemCount: files.count, phase: .running(0)) }
            do {
                var urls: [URL] = []
                for entry in files {
                    urls.append(try await previews.file(for: entry, in: archive) { fraction in
                        Task { @MainActor in self.advance(to: fraction) }
                    })
                }
                guard !Task.isCancelled else { return }
                for url in urls { NSWorkspace.shared.open(url) }
                if large { withAnimation(Motion.appear) { activity = nil } }
            } catch {
                report(error, step: .quickLook, count: files.count)
            }
        }
    }

    /// Opens an archive inside this one in place; the path bar shows the chain.
    func openInside(_ entry: ArchiveEntry) {
        guard archive.source != nil else { return run(.openInside, on: [entry]) }
        guard levels.count < Self.maxDepth else {
            activity = Activity(step: .openInside, itemCount: 1,
                                phase: .failed("Stow opens archives up to \(Self.maxDepth) levels deep."))
            return
        }
        let archive = archive, parentLevels = levels
        activityTask?.cancel()
        activityTask = Task { [weak self] in
            guard let self else { return }
            activity = Activity(step: .openInside, itemCount: 1, phase: .running(0))
            do {
                let url = try await previews.file(for: entry, in: archive) { fraction in
                    Task { @MainActor in self.advance(to: fraction * 0.9) }
                }
                previews.cache.pin(url)
                let (listing, password) = try await passwords.retrying(entry.name) { password in
                    try await ArchiveEngine.shared.list(url, password: password)
                }
                let inner = await Self.makeArchive(listing, url: url, name: entry.name)
                guard !Task.isCancelled else { return }
                let level = Level(archive: inner, password: password, entryPath: entry.path)
                activity = nil
                navigate(to: "", levels: parentLevels + [level])
                startIndexing(level)
            } catch {
                report(error, step: .openInside, count: 1)
            }
        }
    }

    @concurrent
    private static func makeArchive(_ listing: ArchiveListing, url: URL, name: String) async -> Archive {
        Archive(listing: listing, url: url, name: name)
    }

    private func report(_ error: any Error, step: NextStep, count: Int) {
        let error = EngineError(error)
        withAnimation(Motion.appear) {
            if error.failure == .cancelled {
                activity = nil
            } else {
                activity = Activity(step: step, itemCount: count, phase: .failed(error.message))
            }
        }
    }

    // MARK: - Names

    /// Names stored in an older encoding, if any — the browser offers to read them another way.
    var legacyNames: [Data] { archive.source?.legacyNames ?? [] }

    func readNames(as encoding: NameEncoding?) {
        guard let source = archive.source, let listing = source.listing else { return }
        var reread = Archive(listing: listing, url: source.url, name: archive.name, nameEncoding: encoding)
        reread.record(archive.checkup.filter { finding in !reread.checkup.contains { $0.title == finding.title } })
        let level = level
        level.archive = reread
        level.search = SearchIndex(total: reread.index.visible.count + reread.index.helpers.count)
        level.indexed = 0
        startIndexing(level)
        selection = []
        if !folder.isEmpty, reread.entry(at: folder) == nil { folder = "" } else { refresh() }
        runSearch()
    }

    // MARK: - Next steps

    /// Extracts the selection, or everything when nothing is selected.
    func run(_ step: NextStep, on entries: [ArchiveEntry]? = nil) {
        let items = entries ?? (selectedEntries.isEmpty ? archive.files : selectedEntries)
        if step == .extract, archive.source != nil {
            extract(selectedEntries.isEmpty && entries == nil ? nil : items)
        } else if step == .quickLook, archive.source != nil {
            if let entries { select(Set(entries.map(\.id))) }
            quickLook.show()
        } else if step == .openInside, archive.source != nil, let first = items.first {
            openInside(first)
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
            await extract(selection, itemCount: itemCount, to: destination)
        }
    }

    private func extract(_ selection: [ArchiveEntry]?, itemCount: Int, to destination: URL) async {
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

    /// A file promise from a drag to Finder: extract `entry` into `folder` as it's dropped.
    func extractForDrop(_ entries: [ArchiveEntry], into folder: URL) async throws(EngineError) -> [URL] {
        activity = Activity(step: .extract, itemCount: entries.count, phase: .running(0))
        do {
            let result = try await Extraction.run(archive, selection: entries, to: folder) { fraction in
                Task { @MainActor in self.advance(to: fraction) }
            }
            archive.record(Checkup.findings(for: result.report))
            activity?.placed = result.placed
            withAnimation(Motion.appear) { activity?.phase = .done }
            dismissLater()
            return result.placed
        } catch {
            report(error, step: .extract, count: entries.count)
            throw error
        }
    }

    private func dismissLater() {
        activityTask?.cancel()
        activityTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(Motion.appear) { self?.activity = nil }
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
