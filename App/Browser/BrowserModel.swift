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
        /// Overrides the step's own done wording ("Updated in Applications", "2 fonts installed · 1 already there").
        var title: String?

        var doneTitle: String {
            if let title { return title }
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
    /// Code signature verdicts for app entries, by path (from an install or the inspector's check).
    private(set) var signatures: [String: CodeSignature.Verdict] = [:]
    private(set) var checkingSignature: String?
    /// Set by `AppState`: the archive went to the Trash / the window should close after a step.
    var onArchiveGone: (() -> Void)?
    var onCloseWindow: (() -> Void)?

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
        let root = Level(archive: archive, password: archive.source?.password)
        levels = [root]
        self.previews = previews
        // A disk image opens at its volume, with the one thing to install already selected.
        folder = archive.volumeRoot
        history = [Location(levels: levels, folder: folder)]
        previews.password = { [weak self] archive in
            self?.levels.first { $0.archive.id == archive.id }?.password
        }
        quickLook.model = self
        dragOut.model = self
        refresh()
        if let suggested = Self.suggestedSelection(in: archive) { select([suggested]) }
        startIndexing(root)
    }

    var level: Level { levels[levels.count - 1] }

    var archive: Archive {
        get { level.archive }
        set { level.archive = newValue }
    }

    /// Disk images are checked against their checksums in the background; browsing doesn't wait.
    func verifyDiskImage() {
        guard archive.format == .dmg, let url = archive.source?.url else { return }
        Task { [weak self] in
            var damage: String?
            do {
                try await ArchiveEngine.shared.verify(url)
            } catch {
                let error = EngineError(error)
                if error.failure == .cancelled || error.failure == .passwordRequired { return }
                damage = error.message
            }
            self?.archive.record([Checkup.diskImageFinding(damaged: damage)])
        }
    }

    /// The single app or installer package at the top of a disk image (or archive), if that's
    /// clearly what it's for.
    static func suggestedSelection(in archive: Archive) -> ArchiveEntry.ID? {
        let top = archive.children(of: archive.volumeRoot)
        let installable = top.filter { $0.kind == .app || $0.kind == .installer }
        guard installable.count == 1, archive.isDiskImage || top.count <= 3 else { return nil }
        return installable[0].id
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
            var lastSearch = ContinuousClock.now
            await search.build(entries) { count in
                await MainActor.run {
                    level?.indexed = count
                    // Results grow as the index does. Search the newly indexed part now and then,
                    // not every chunk: replacing 100,000 results costs the list a moment each time.
                    let complete = count >= search.total
                    guard let self, self.isSearching, self.level === level,
                          complete || ContinuousClock.now - lastSearch > .milliseconds(750) else { return }
                    lastSearch = .now
                    self.runSearch()
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

    /// Runs a Next Step on the selection (or on `entries`); Extract with nothing selected extracts all.
    func run(_ step: NextStep, on entries: [ArchiveEntry]? = nil) {
        let items = entries ?? (selectedEntries.isEmpty ? archive.files : selectedEntries)
        guard archive.source != nil else {
            simulate(step, itemCount: items.count)
            return
        }
        switch step {
        case .extract: extract(selectedEntries.isEmpty && entries == nil ? nil : items)
        case .moveToApplications: if let app = items.first { installApp(app) }
        case .installFonts: installFonts(items)
        case .openInstaller: if let package = items.first { openInstaller(package) }
        case .copyTo(let folder): copy(items, to: URL(filePath: folder, directoryHint: .isDirectory), step: step)
        case .quickLook:
            if let entries { select(Set(entries.map(\.id))) }
            quickLook.show()
        case .openInside: if let first = items.first { openInside(first) }
        }
    }

    func extractAll() {
        if archive.source != nil {
            extract(nil)
        } else {
            simulate(.extract, itemCount: archive.files.count)
        }
    }

    /// What a finished step leaves behind, for the done capsule.
    private struct Finished {
        var placed: [URL] = []
        var title: String?
        var findings: [CheckupFinding] = []
        /// Extract All and installs: keep/trash the archive and maybe close the window afterwards.
        var aftercare: (setting: Preferences.AfterwardsArchive, key: String, action: String)?
    }

    /// Progress → done (or failed) → gone, shared by every real step. Cancelling leaves nothing behind.
    private func perform(_ step: NextStep, itemCount: Int, prepare: (() async throws(EngineError) -> Void)? = nil,
                         _ work: @escaping (@escaping @Sendable (Double) -> Void) async throws(EngineError) -> Finished) {
        activityTask?.cancel()
        activityTask = Task { [weak self] in
            guard let self else { return }
            let finished: Finished
            do {
                try await prepare?()
                activity = Activity(step: step, itemCount: itemCount, phase: .running(0))
                finished = try await work { fraction in
                    Task { @MainActor in self.advance(to: fraction) }
                }
            } catch {
                let error = EngineError(error)
                withAnimation(Motion.appear) {
                    if error.failure == .cancelled {
                        activity = nil
                    } else {
                        activity?.phase = .failed(error.message)
                        if activity == nil {
                            activity = Activity(step: step, itemCount: itemCount, phase: .failed(error.message))
                        }
                    }
                }
                return
            }
            archive.record(finished.findings)
            activity?.placed = finished.placed
            activity?.title = finished.title
            withAnimation(Motion.appear) { activity?.phase = .done }

            if let aftercare = finished.aftercare, let source = archive.source?.url {
                let trashed = await ArchiveAftercare.apply(aftercare.setting, key: aftercare.key, to: [source],
                                                           action: aftercare.action)
                if !trashed.isEmpty {
                    try? await Task.sleep(for: .seconds(1.2))
                    onArchiveGone?()
                    return
                }
                if Preferences.current.closeWindowAfter {
                    try? await Task.sleep(for: .seconds(1.2))
                    onCloseWindow?()
                    return
                }
            }
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(Motion.appear) { activity = nil }
        }
    }

    /// Asks where, then extracts through the engine; nil extracts everything.
    private func extract(_ selection: [ArchiveEntry]?) {
        var destination: URL?
        let archive = archive
        perform(.extract, itemCount: selection?.count ?? archive.files.count, prepare: { () async throws(EngineError) in
            destination = await ExtractDestination.choose(for: archive)
            if destination == nil { throw EngineError(.cancelled) }
        }) { [weak self, passwords] progress throws(EngineError) in
            guard let destination else { throw EngineError(.cancelled) }
            let options = Extraction.Options.current(resolve: ConflictPolicy().resolver)
            // Encrypted contents only need the password now; one that worked before is tried first.
            let (result, password) = try await passwords.retrying(archive.name, for: .extract,
                                                                  known: archive.source?.password) { password in
                var attempt = archive
                attempt.source?.password = password
                return try await Extraction.run(attempt, selection: selection, to: destination, options: options,
                                                onProgress: progress)
            }
            if let password { self?.rememberPassword(password) }
            var finished = Finished(placed: result.placed, findings: result.findings)
            if result.placed.isEmpty { finished.title = "Nothing new — everything was already there" }
            if selection == nil {
                finished.aftercare = (Preferences.current.afterExtractAll, Preferences.Key.afterExtractAll, "Everything was extracted.")
            }
            return finished
        }
    }

    /// A file promise from a drag to Finder: extract `entries` into `folder` as they're dropped.
    func extractForDrop(_ entries: [ArchiveEntry], into folder: URL) async throws(EngineError) -> [URL] {
        activityTask?.cancel()
        activity = Activity(step: .extract, itemCount: entries.count, phase: .running(0))
        do {
            let options = Extraction.Options.current(resolve: ConflictPolicy().resolver)
            let result = try await Extraction.run(archive, selection: entries, to: folder, options: options) { fraction in
                Task { @MainActor in self.advance(to: fraction) }
            }
            archive.record(result.findings)
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

    /// A password that worked stays with the open archive (memory only) for later steps and previews.
    private func rememberPassword(_ password: String) {
        archive.source?.password = password
        if levels.count == 1 { level.password = password }
    }

    /// Where an app goes: the disk image's own "drag to Applications" shortcut, or /Applications.
    private func installFolder(for entry: ArchiveEntry) -> URL {
        if let override = FolderAccess.override { return override }
        let sibling = archive.dropTargets.first { $0.folder.hasSuffix("Applications") && ($0.path as NSString).deletingLastPathComponent == entry.parent }
        return sibling?.url ?? FolderAccess.applications
    }

    private func installApp(_ entry: ArchiveEntry) {
        let archive = archive
        let target = installFolder(for: entry)
        var grant: FolderAccess.Grant?
        perform(.moveToApplications, itemCount: 1, prepare: { () async throws(EngineError) in
            grant = try await FolderAccess.request(
                target, purpose: "To install “\(Installer.displayName(entry.name))”, Stow needs permission to add apps to this folder.")
        }) { [weak self] progress throws(EngineError) in
            guard let grant else { throw EngineError(.cancelled) }
            defer { grant.release() }
            let outcome = try await Installer.installApp(entry, from: archive, into: grant.url,
                                                         removeQuarantine: Preferences.current.removeQuarantine,
                                                         ask: Prompts.ask, onProgress: progress)
            self?.signatures[entry.path] = outcome.verdict
            var findings = [Self.finding(outcome.verdict, app: entry.name)]
            if outcome.quarantineRemoved == false {
                findings.append(CheckupFinding(severity: .info, title: "Quarantine flag kept",
                                               detail: "macOS doesn’t let a sandboxed app remove it, so Gatekeeper checks “\(Installer.displayName(entry.name))” the first time it opens."))
            }
            let folder = FileManager.default.displayName(atPath: grant.url.path)
            return Finished(placed: [outcome.app],
                            title: outcome.replaced ? "Updated in \(folder)" : "Installed in \(folder)",
                            findings: findings,
                            aftercare: (Preferences.current.afterInstall, Preferences.Key.afterInstall, "“\(Installer.displayName(entry.name))” is installed."))
        }
    }

    private func installFonts(_ entries: [ArchiveEntry]) {
        let archive = archive
        let target = FolderAccess.override ?? FolderAccess.userFonts
        var grant: FolderAccess.Grant?
        perform(.installFonts(count: entries.count), itemCount: entries.count, prepare: { () async throws(EngineError) in
            grant = try await FolderAccess.request(target, purpose: "To install fonts, Stow needs permission to add them to your font library.")
        }) { progress throws(EngineError) in
            guard let grant else { throw EngineError(.cancelled) }
            defer { grant.release() }
            let outcome = try await Installer.installFonts(entries, from: archive, into: grant.url, ask: Prompts.ask,
                                                           onProgress: progress)
            var title = outcome.installed.count == 1 ? "Font installed" : "\(outcome.installed.count) fonts installed"
            if !outcome.skipped.isEmpty { title += " · \(outcome.skipped.count) already there" }
            if !outcome.unusable.isEmpty { title += " · \(outcome.unusable.count) not installable" }
            return Finished(placed: outcome.installed, title: title,
                            aftercare: (Preferences.current.afterInstall, Preferences.Key.afterInstall, "The fonts are installed."))
        }
    }

    private func openInstaller(_ entry: ArchiveEntry) {
        let archive = archive
        let beside = FolderAccess.override ?? archive.source?.url.deletingLastPathComponent() ?? FolderAccess.home
        var grant: FolderAccess.Grant?
        perform(.openInstaller, itemCount: 1, prepare: { () async throws(EngineError) in
            grant = try await FolderAccess.request(
                beside, purpose: "To open “\(entry.name)” in Installer, Stow unpacks it next to the archive for a moment.")
        }) { progress throws(EngineError) in
            guard let grant else { throw EngineError(.cancelled) }
            defer { grant.release() }
            _ = try await Installer.openInstaller(entry, from: archive, near: grant.url, onProgress: progress)
            return Finished()
        }
    }

    /// A disk image's "drag here" folder (plug-ins, screen savers…), asked for once like Applications.
    private func copy(_ entries: [ArchiveEntry], to folder: URL, step: NextStep) {
        let archive = archive
        var grant: FolderAccess.Grant?
        perform(step, itemCount: entries.count, prepare: { () async throws(EngineError) in
            grant = try await FolderAccess.request(FolderAccess.override ?? folder,
                                                   purpose: "The disk image asks for this to be copied here.")
        }) { progress throws(EngineError) in
            guard let grant else { throw EngineError(.cancelled) }
            defer { grant.release() }
            let options = Extraction.Options.current(resolve: ConflictPolicy().resolver)
            let result = try await Extraction.run(archive, selection: entries, to: grant.url, options: options,
                                                  onProgress: progress)
            return Finished(placed: result.placed, findings: result.findings)
        }
    }

    /// Checks an app's signature without installing it (inspector), and notes it in Checkup.
    func checkSignature(_ entry: ArchiveEntry) {
        guard archive.source != nil, signatures[entry.path] == nil else { return }
        let archive = archive
        checkingSignature = entry.path
        Task { [weak self] in
            defer { self?.checkingSignature = nil }
            do {
                let folder = TemporaryOpen.makeFolder()
                defer { try? FileManager.default.removeItem(at: folder) }
                let staged = try await Extraction.stage(archive, selection: [entry], near: folder) { _ in }
                defer { staged.discard() }
                let verdict = await Self.assess(staged.url(for: entry))
                self?.signatures[entry.path] = verdict
                self?.archive.record([Self.finding(verdict, app: entry.name)])
            } catch {
                self?.signatures[entry.path] = nil
            }
        }
    }

    @concurrent
    private static func assess(_ bundle: URL) async -> CodeSignature.Verdict { CodeSignature.assess(bundle) }

    /// The verdict as a Checkup line naming the app.
    static func finding(_ verdict: CodeSignature.Verdict, app: String) -> CheckupFinding {
        let base = verdict.finding
        return CheckupFinding(severity: base.severity == .fine ? .info : base.severity,
                              title: verdict.headline(app: Installer.displayName(app)),
                              detail: base.detail)
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
