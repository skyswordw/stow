import AppKit
import SwiftUI

@Observable
final class BrowserModel {
    nonisolated enum ViewMode: String, CaseIterable, Identifiable, Sendable {
        case grid, list, columns
        var id: Self { self }
    }

    enum Direction { case up, down, left, right }

    struct Activity: Equatable {
        typealias Phase = ActivityPhase
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
            return String(localized: "Extracted to \(FileManager.default.displayName(atPath: folder.path))")
        }
    }

    /// One archive in the chain being browsed: the one opened, then any opened inside it.
    @Observable
    final class Level: Identifiable {
        let id = UUID()
        var archive: Archive
        var savedArchive: Archive
        var password: String?
        let edits: EditSession
        /// Where this archive sits in the level above; nil for the archive that was opened.
        let entryPath: String?
        fileprivate(set) var search: SearchIndex
        fileprivate(set) var indexed = 0
        /// The archives inside this one, read the first time someone searches (#21).
        fileprivate(set) var nested: NestedSearch?

        init(archive: Archive, password: String? = nil, entryPath: String? = nil) {
            self.archive = archive
            savedArchive = archive
            let base = archive.source?.listing ?? ArchiveListing(type: archive.format == .sevenZip ? "7z" : archive.format.rawValue, entries: (archive.entries + archive.index.helpers).map { ListedEntry(path: $0.path, isFolder: $0.isFolder, size: $0.size, packedSize: $0.packedSize, modified: $0.modified) })
            edits = EditSession(base: base, url: archive.source?.url, name: archive.name, nested: entryPath != nil)
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
    var viewMode: ViewMode = SettingsKeys.browserView()
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
    /// Set by `AppState`: Pack… staged the selection; show the Pack sentence for it.
    var onPack: ((PackRequest) -> Void)?

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
    private(set) var isUnlocking = false
    private(set) var previewRevision = 0
    private var unlockTask: Task<Void, Never>?

    isolated deinit { unlockTask?.cancel() }

    private var positions: [ArchiveEntry.ID: Int] = [:]
    private var searchResults: [ArchiveEntry] = []
    /// Results that sit inside an inner archive, by the id they show under.
    private(set) var nestedHits: [ArchiveEntry.ID: NestedHit] = [:]
    /// Reads an inner archive for search. Real archives extract it to the preview cache; nil
    /// (the sample archive) leaves search at the open level. Demo scenes and tests swap it.
    var nestedLoader: NestedSearch.Loader?
    private var searchTask: Task<Void, Never>?
    private var activityTask: Task<Void, Never>?
    /// The last step run, for a failure's Try Again / Choose Another Folder.
    private var lastRun: (() -> Void)?
    private var typeahead = (text: "", at: Date.distantPast)

    private(set) var isListing = false
    private(set) var listedCount = 0

    init(archive: Archive, previews: PreviewService = PreviewService(), isListing: Bool = false) {
        self.isListing = isListing
        listedCount = archive.source?.listing?.entries.count ?? archive.entries.count
        let root = Level(archive: archive, password: archive.source?.password)
        root.edits.isListing = isListing
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
        connectEdits(root)
        if archive.source != nil {
            nestedLoader = { [weak self] entry, archive in
                guard let self else { throw EngineError(.cancelled) }
                let url = try await self.previews.file(for: entry, in: archive)
                self.previews.cache.pin(url)
                let listing = try await ArchiveEngine.shared.list(url, password: nil)
                let inner = await Self.makeArchive(listing, url: url, name: entry.name)
                return inner.index.visible + inner.index.helpers
            }
        }
        refresh()
        if let suggested = Self.suggestedSelection(in: archive) { select([suggested]) }
        if !isListing { startIndexing(root) }
    }

    /// Keep navigation and selection while replacing provisional metadata with the final listing.
    func applyListing(_ archive: Archive, complete: Bool) {
        let oldFolder = folder
        let oldSelection = selection
        let root = Level(archive: archive, password: archive.source?.password)
        root.edits.isListing = !complete
        levels = [root]
        isListing = !complete
        listedCount = archive.source?.listing?.entries.count ?? archive.entries.count
        connectEdits(root)
        folder = oldFolder.isEmpty || archive.entry(at: oldFolder) != nil ? oldFolder : archive.volumeRoot
        history = [Location(levels: levels, folder: folder)]
        historyIndex = 0
        selection = oldSelection.filter { archive.entry(at: $0) != nil }
        refresh()
        if complete { startIndexing(root) }
    }

    var editSession: EditSession { level.edits }
    var renamingPath: String?
    var renameText = ""
    weak var editingWindow: NSWindow?

    var level: Level { levels[levels.count - 1] }

    var archive: Archive {
        get { level.archive }
        set { level.archive = newValue }
    }

    private func connectEdits(_ target: Level) {
        var previousOperations = target.edits.operations
        for (shown, stored) in target.archive.source?.storedPaths ?? [:] {
            for path in stored { target.edits.displayedPaths[path] = shown }
        }
        target.edits.onURLChange = { [weak self, weak target] url in
            guard let self, let target else { return }
            self.adoptArchiveURL(url, on: target)
        }
        target.edits.onChange = { [weak self, weak target] in
            guard let self, let target else { return }
            let old = target.archive
            let nextOperations = target.edits.operations
            let common = zip(previousOperations, nextOperations).prefix { pair in pair.0 == pair.1 }.count
            let reversedRenames = previousOperations.dropFirst(common).reversed().compactMap { operation -> EditOperation? in
                if case let .rename(from, to) = operation { return .rename(from: to, to: from) }
                return nil
            }
            let moves = target.edits.isSaving ? [] : reversedRenames + Array(nextOperations.dropFirst(common))
            previousOperations = nextOperations
            if self.level === target {
                self.folder = EditSession.map(path: self.folder, through: moves)
                self.selection = Set(self.selection.map { EditSession.map(path: $0, through: moves) })
            }
            self.history = self.history.map { location in
                Location(levels: location.levels, folder: location.levels.last === target ? EditSession.map(path: location.folder, through: moves) : location.folder)
            }
            if let url = old.source?.url {
                var updated = Archive(listing: target.edits.pending, url: url, name: old.name, nameEncoding: old.source?.nameEncoding)
                updated.source?.password = target.password
                target.archive = updated
                if target.edits.isSaving { target.savedArchive = updated }
            } else {
                target.archive = Archive(name: old.name, format: old.format, files: target.edits.pending.entries.map {
                    ArchiveEntry(path: $0.path, isFolder: $0.isFolder, size: $0.size, packedSize: $0.packedSize ?? 0, modified: $0.modified ?? .distantPast)
                })
            }
            target.search = SearchIndex(total: target.archive.index.visible.count + target.archive.index.helpers.count)
            target.indexed = 0
            if self.level === target {
                self.folder = EditSession.nearestExistingParent(self.folder, in: target.edits.pending)
                self.selection = self.selection.filter { target.archive.entry(at: $0) != nil }
                self.refresh()
                self.runSearch()
            }
            self.editingWindow?.isDocumentEdited = self.levels.contains { $0.edits.isEdited }
            self.startIndexing(target)
        }
        previews.originalFile = { [weak self] entry, archive in
            guard let target = self?.levels.first(where: { $0.archive.id == archive.id }), target.edits.isEdited else { return nil }
            let original = target.edits.originalPath(for: entry.path)
            guard let originalEntry = target.savedArchive.entry(at: original) else { return nil }
            return (originalEntry, target.savedArchive)
        }
        previews.stagedSource = { [weak self] entry, archive in
            self?.levels.first { $0.archive.id == archive.id }?.edits.source(for: entry.path)
        }
    }

    func chooseAddFiles() {
        guard !isListing else { return }
        guard editSession.requireEditable() else { return }
        Task { editSession.add(await PackDestination.chooseSources(forAdding: true), into: folder) }
    }

    func beginRename(_ entry: ArchiveEntry) {
        guard !isListing else { return }
        guard editSession.requireEditable() else { return }
        if let reason = editSession.refusal(for: [entry.path]) { editSession.message = reason; return }
        renamingPath = entry.path
        renameText = entry.name
    }

    func commitRename() {
        guard !isListing else { return }
        guard let path = renamingPath else { return }
        let parent = ArchiveEntry.parent(of: path)
        let newPath = parent.isEmpty ? renameText : parent + "/" + renameText
        editSession.rename(path, to: renameText)
        if editSession.message == nil { selection = [newPath]; renamingPath = nil }
    }

    func chooseReplacement(_ entry: ArchiveEntry) {
        guard !isListing else { return }
        guard editSession.requireEditable() else { return }
        Task {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            let response = if let window = editingWindow { await panel.beginSheetModal(for: window) } else { panel.runModal() }
            if response == .OK, let url = panel.url { editSession.replace(entry.path, with: url) }
        }
    }

    @discardableResult func saveEdits() async -> Bool {
        if renamingPath != nil {
            commitRename()
            guard renamingPath == nil else { return false }
        }
        let target = level
        if target.savedArchive.isEncrypted, target.password == nil {
            guard let password = await passwords.ask(archive.name, .extract, false) else { return false }
            target.password = password
        }
        let oldFolder = folder, oldSelection = selection, oldHistory = history
        guard await target.edits.save(password: target.password) else { return false }
        func mapped(_ path: String) -> String {
            EditSession.nearestExistingParent(path, in: target.edits.base)
        }
        // Live positions and history already use staged names; discard missing descendants.
        folder = EditSession.nearestExistingParent(oldFolder, in: target.edits.base)
        selection = Set(oldSelection.filter { target.archive.entry(at: $0) != nil })
        history = oldHistory.map { location in
            Location(levels: location.levels, folder: location.levels.last === target ? mapped(location.folder) : location.folder)
        }
        refresh()
        return true
    }

    func revertEdits() {
        renamingPath = nil
        editSession.revert()
    }

    /// Reloads the open archive from disk and discards staged edits (external-change banner).
    @discardableResult func reloadArchive() async -> Bool {
        renamingPath = nil
        let target = level
        let folderBefore = folder, selectionBefore = selection, historyBefore = history
        guard await target.edits.reload(password: target.password) else { return false }
        guard let url = target.edits.url ?? target.archive.source?.url else { return false }
        var archive = Archive(listing: target.edits.base, url: url,
                              name: target.edits.name, nameEncoding: target.archive.source?.nameEncoding)
        archive.source?.password = target.password
        target.archive = archive
        target.savedArchive = archive
        target.search = SearchIndex(total: archive.index.visible.count + archive.index.helpers.count)
        target.indexed = 0
        startIndexing(target)
        folder = EditSession.nearestExistingParent(folderBefore, in: target.edits.base)
        selection = Set(selectionBefore.filter { target.archive.entry(at: $0) != nil })
        history = historyBefore.map { location in
            Location(levels: location.levels,
                     folder: location.levels.last === target
                        ? EditSession.nearestExistingParent(location.folder, in: target.edits.base)
                        : location.folder)
        }
        refresh()
        runSearch()
        editingWindow?.isDocumentEdited = levels.contains { $0.edits.isEdited }
        return true
    }

    /// Saves pending edits to a new file chosen by the user; the original stays byte-identical.
    @discardableResult func saveCopyOfArchive() async -> Bool {
        guard editSession.isEdited, let source = archive.source?.url else { return false }
        if renamingPath != nil {
            commitRename()
            guard renamingPath == nil else { return false }
        }
        let target = level
        if target.savedArchive.isEncrypted, target.password == nil {
            guard let password = await passwords.ask(archive.name, .extract, false) else { return false }
            target.password = password
        }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        let ext = source.pathExtension
        let stem = source.deletingPathExtension().lastPathComponent
        panel.nameFieldStringValue = ext.isEmpty ? stem + " copy" : stem + " copy." + ext
        panel.directoryURL = source.deletingLastPathComponent()
        panel.title = String(localized: "Save a Copy")
        let response = if let window = editingWindow { await panel.beginSheetModal(for: window) } else { panel.runModal() }
        guard response == .OK, let destination = panel.url else { return false }
        let oldFolder = folder, oldSelection = selection, oldHistory = history
        guard await target.edits.saveCopy(to: destination, password: target.password) else { return false }
        adoptArchiveURL(destination, on: target)
        folder = EditSession.nearestExistingParent(oldFolder, in: target.edits.base)
        selection = Set(oldSelection.filter { target.archive.entry(at: $0) != nil })
        history = oldHistory.map { location in
            Location(levels: location.levels,
                     folder: location.levels.last === target
                        ? EditSession.nearestExistingParent(location.folder, in: target.edits.base)
                        : location.folder)
        }
        refresh()
        return true
    }

    /// Renames the archive file on disk (File › Rename Archive…), including SMB/NAS after a folder grant.
    @discardableResult func renameArchive() async -> Bool {
        guard !isListing else { return false }
        guard levels.count == 1, archive.source?.url != nil else { return false }
        let prompt = Prompt.renameArchive(archive.name)
        let answer = await Prompts.present(prompt, on: editingWindow)
        guard prompt.choices[answer.choice].role == .primary else { return false }
        let newName = answer.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != archive.name else { return false }
        let folderBefore = folder, selectionBefore = selection
        guard await editSession.renameArchive(to: newName) else { return false }
        guard let url = editSession.url else { return false }
        adoptArchiveURL(url, on: level)
        folder = folderBefore
        selection = selectionBefore
        refresh()
        return true
    }

    private func adoptArchiveURL(_ url: URL, on target: Level) {
        let encoding = target.archive.source?.nameEncoding
        let listing = target.edits.isEdited ? target.edits.pending : target.edits.base
        var archive = Archive(listing: listing, url: url, name: url.lastPathComponent, nameEncoding: encoding)
        archive.source?.password = target.password
        target.archive = archive
        if !target.edits.isEdited {
            target.savedArchive = archive
        } else {
            var saved = Archive(listing: target.edits.base, url: url, name: url.lastPathComponent, nameEncoding: encoding)
            saved.source?.password = target.password
            target.savedArchive = saved
        }
        editingWindow?.representedURL = url
        editingWindow?.title = url.lastPathComponent
    }

    func confirmDiscardingEdits() async -> Bool {
        guard let editedIndex = levels.firstIndex(where: { $0.edits.isEdited }) else { return true }
        guard !levels[editedIndex].edits.isSaving else { return false }
        let originalLevels = levels, originalFolder = folder, originalSelection = selection
        if editedIndex != levels.count - 1 {
            navigate(to: "", levels: Array(levels.prefix(editedIndex + 1)), record: false)
        }
        let answer = await Prompts.present(.saveChanges(archive.name), on: editingWindow)
        let decision: EditSession.CloseDecision = switch answer.choice {
        case Prompt.SaveChoice.save: .save
        case Prompt.SaveChoice.discard: .discard
        default: .cancel
        }
        let saved = decision == .save ? await saveEdits() : false
        let allowed = EditSession.canClose(decision, saved: saved)
        if decision == .discard { editSession.discardChanges() }
        if originalLevels.map(\.id) != levels.map(\.id) {
            navigate(to: originalFolder, levels: originalLevels, selecting: originalSelection, record: false)
        }
        return allowed
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
        if isSearching { return String(localized: "Search") }
        return folder.isEmpty ? archive.name : (folder as NSString).lastPathComponent
    }

    var subtitle: String {
        let count = visibleEntries.count
        let items = count == 1 ? String(localized: "1 item")
            : String(localized: "\(count.formatted()) items")
        return isSearching ? String(localized: "\(count.formatted()) results in \(archive.name)") : items
    }

    /// The selected search result, when it sits inside an inner archive.
    var selectedNestedHit: NestedHit? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return nestedHits[id]
    }

    /// "Indexing… 12,000 of 40,000" while a big archive's search index builds.
    var indexingProgress: String? {
        if isListing { return String(localized: "Listing… \(listedCount.formatted())") }
        let search = level.search
        if isSearching, let nested = level.nested, nested.isLoading {
            return nested.pending == 1 ? String(localized: "Looking inside 1 more archive…")
                : String(localized: "Looking inside \(nested.pending) more archives…")
        }
        guard level.indexed < search.total, search.total > 2_000 else { return nil }
        return String(localized: "Indexing… \(level.indexed.formatted()) of \(search.total.formatted())")
    }

    // MARK: - Contents

    private func refresh() {
        visibleEntries = isSearching ? searchResults
            : archive.children(of: folder, includingHelpers: showHelperItems)
        positions = Dictionary(visibleEntries.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func runSearch() {
        guard !isListing else { return }
        searchTask?.cancel()
        guard isSearching else {
            searchResults = []
            nestedHits = [:]
            refresh()
            return
        }
        let level = level, query = query, helpers = showHelperItems
        startNestedSearch(level)
        searchTask = Task {
            let results = await level.search.search(query, includingHelpers: helpers)
            let hits = await level.nested?.search(query, includingHelpers: helpers) ?? []
            guard !Task.isCancelled, level === self.level else { return }
            nestedHits = Dictionary(hits.map { ($0.entry.id, $0) }, uniquingKeysWith: { first, _ in first })
            searchResults = results + hits.map(\.entry)
            refresh()
        }
    }

    /// The first search in a level reads the archives inside it, once; results grow as each is read.
    private func startNestedSearch(_ level: Level) {
        guard level.nested == nil, let loader = nestedLoader else { return }
        let nested = NestedSearch(archive: level.archive)
        level.nested = nested
        guard !nested.isEmpty else { return }
        let archive = level.archive
        Task { [weak self, weak level] in
            await nested.load(in: archive, with: loader) {
                guard let self, let level, level.nested === nested, self.level === level, self.isSearching else { return }
                self.runSearch()
            }
        }
    }

    /// Opens the inner archive a search result sits in, with the result selected.
    func showNested(_ hit: NestedHit) {
        openInside(hit.container, revealing: hit.inner)
    }

    private func startIndexing(_ level: Level) {
        let entries = level.archive.index.visible + level.archive.index.helpers
        let search = level.search
        Task { [weak self, weak level] in
            var lastSearch = ContinuousClock.now
            await search.build(entries) { count in
                await MainActor.run {
                    guard level?.search === search else { return }
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
        editingWindow?.isDocumentEdited = levels.contains { $0.edits.isEdited }
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
        if let hit = nestedHits[entry.id] {
            showNested(hit)
        } else if entry.isNavigable {
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
        if quickLook.isActive {
            quickLook.close()
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
                    urls.append(try await previewFile(for: entry, in: archive) { fraction in
                        Task { @MainActor in self.advance(to: fraction) }
                    })
                }
                guard !Task.isCancelled else { return }
                for url in urls { NSWorkspace.shared.open(url) }
                if large { withAnimation(Motion.current(Motion.exit)) { activity = nil } }
            } catch {
                report(error, step: .quickLook, count: files.count)
            }
        }
    }

    /// Opens an archive inside this one in place; the path bar shows the chain.
    func openInside(_ entry: ArchiveEntry, revealing target: ArchiveEntry? = nil) {
        guard !isListing else { return }
        guard archive.source != nil else { return run(.openInside, on: [entry]) }
        guard levels.count < Self.maxDepth else {
            activity = Activity(step: .openInside, itemCount: 1,
                                phase: .failed(Failure(String(localized: "Stow opens archives up to \(Self.maxDepth) levels deep"),
                                                       advice: String(localized: "Extract this one first, then open it from Finder."),
                                                       code: ErrorCode(.open, .limit))))
            return
        }
        let archive = archive, parentLevels = levels
        activityTask?.cancel()
        activityTask = Task { [weak self] in
            guard let self else { return }
            activity = Activity(step: .openInside, itemCount: 1, phase: .running(0))
            do {
                let url = try await previewFile(for: entry, in: archive) { fraction in
                    Task { @MainActor in self.advance(to: fraction * 0.9) }
                }
                previews.cache.pin(url)
                let (listing, password) = try await passwords.retrying(entry.name) { password in
                    try await ArchiveEngine.shared.list(url, password: password)
                }
                let inner = await Self.makeArchive(listing, url: url, name: entry.name)
                guard !Task.isCancelled else { return }
                let level = Level(archive: inner, password: password, entryPath: entry.path)
                connectEdits(level)
                activity = nil
                if let target, target.isFolder {
                    navigate(to: target.path, levels: parentLevels + [level])
                } else {
                    navigate(to: target?.parent ?? "", levels: parentLevels + [level], selecting: target.map { [$0.id] } ?? [])
                }
                startIndexing(level)
            } catch {
                report(error, step: .openInside, count: 1, name: entry.name)
            }
        }
    }

    @concurrent
    private static func makeArchive(_ listing: ArchiveListing, url: URL, name: String) async -> Archive {
        Archive(listing: listing, url: url, name: name)
    }

    private func report(_ error: any Error, step: NextStep, count: Int, name: String? = nil) {
        let error = EngineError(error)
        withAnimation(Motion.current(Motion.status)) {
            if error.failure == .cancelled {
                activity = nil
            } else {
                activity = Activity(step: step, itemCount: count,
                                    phase: .failed(Failure(error, step.failureOperation, name: name ?? archive.name)))
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
        reread.source?.password = level.password
        level.savedArchive = Archive(listing: level.edits.base, url: source.url, name: archive.name, nameEncoding: encoding)
        level.savedArchive.source?.password = level.password
        level.edits.displayedPaths = [:]
        for (shown, stored) in reread.source?.storedPaths ?? [:] {
            for path in stored { level.edits.displayedPaths[path] = shown }
        }
        level.archive = reread
        level.search = SearchIndex(total: reread.index.visible.count + reread.index.helpers.count)
        level.indexed = 0
        level.nested = nil
        startIndexing(level)
        selection = []
        if !folder.isEmpty, reread.entry(at: folder) == nil { folder = "" } else { refresh() }
        runSearch()
    }

    // MARK: - Next steps

    /// Runs a Next Step on the selection (or on `entries`); Extract with nothing selected extracts all.
    func run(_ step: NextStep, on entries: [ArchiveEntry]? = nil) {
        guard !isListing else { return }
        // Only results inside other archives are selected: nothing here to act on, and not "everything".
        if entries == nil, selectedEntries.isEmpty, !selection.isEmpty { return }
        let items = entries ?? (selectedEntries.isEmpty ? archive.files : selectedEntries)
        let again = entries ?? (selectedEntries.isEmpty ? nil : selectedEntries)
        lastRun = { [weak self] in self?.run(step, on: again) }
        guard archive.source != nil else {
            if step == .pack { return packSample(items) }
            // The sample's files are in the app: Quick Look shows them for real.
            if step == .quickLook {
                if let entries { select(Set(entries.map(\.id))) }
                return quickLook.show()
            }
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
        case .pack: pack(items)
        }
    }

    func extractAll() {
        guard !isListing else { return }
        lastRun = { [weak self] in self?.extractAll() }
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
    /// `name` is what the step works on; `destination` and `needs` let a failure tell a full or
    /// read-only folder apart from a damaged archive.
    private func perform(_ step: NextStep, itemCount: Int, name: String? = nil, destination: @escaping () -> URL? = { nil },
                         needs bytes: Int64 = 0, prepare: (() async throws(EngineError) -> Void)? = nil,
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
                let failure = Failure(error, step.failureOperation, name: name ?? archive.name,
                                      destination: destination(), needs: bytes)
                withAnimation(Motion.current(Motion.status)) {
                    if EngineError(error).failure == .cancelled {
                        activity = nil
                    } else {
                        activity?.phase = .failed(failure)
                        if activity == nil {
                            activity = Activity(step: step, itemCount: itemCount, phase: .failed(failure))
                        }
                    }
                }
                return
            }
            archive.record(finished.findings)
            activity?.placed = finished.placed
            activity?.title = finished.title
            withAnimation(Motion.current(Motion.status)) { activity?.phase = .done }

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
            withAnimation(Motion.current(Motion.exit)) { activity = nil }
        }
    }

    /// Asks where, then extracts through the engine; nil extracts everything.
    private func extract(_ selection: [ArchiveEntry]?) {
        var destination: URL?
        let archive = archive
        let bytes = (selection ?? archive.files).reduce(Int64(0)) { $0 + $1.size }
        perform(.extract, itemCount: selection?.count ?? archive.files.count, destination: { destination }, needs: bytes,
                prepare: { () async throws(EngineError) in
            destination = await ExtractDestination.choose(for: archive)
            if destination == nil { throw EngineError(.cancelled) }
        }) { [weak self, passwords] progress throws(EngineError) in
            guard let destination else { throw EngineError(.cancelled) }
            let options = Extraction.Options.current(resolve: ConflictPolicy().resolver)
            // Encrypted contents only need the password now; one that worked before is tried first.
            let (result, password) = try await passwords.retrying(archive.name, for: .extract,
                                                                  known: archive.source?.password,
                                                                  vaultURL: archive.source?.url) { password in
                var attempt = archive
                attempt.source?.password = password
                return try await Extraction.run(attempt, selection: selection, to: destination, options: options,
                                                onProgress: progress)
            }
            if let password { self?.rememberPassword(password) }
            var finished = Finished(placed: result.placed, findings: result.findings)
            if result.placed.isEmpty { finished.title = String(localized: "Nothing new — everything was already there") }
            if selection == nil {
                finished.aftercare = (Preferences.current.afterExtractAll, Preferences.Key.afterExtractAll, String(localized: "Everything was extracted."))
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
            withAnimation(Motion.current(Motion.status)) { activity?.phase = .done }
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
            withAnimation(Motion.current(Motion.exit)) { self?.activity = nil }
        }
    }

    /// A password that worked stays with the open archive (memory only) for later steps and previews.
    private func rememberPassword(_ password: String) {
        rememberPassword(password, in: level)
    }

    private func rememberPassword(_ password: String, in target: Level) {
        let changed = target.password != password
        target.password = password
        target.archive.source?.password = password
        target.savedArchive.source?.password = password
        if changed {
            previews.passwordDidChange()
            previewRevision += 1
        }
    }

    /// User-requested previews may ask; background thumbnails and hover previews never do.
    func previewFile(for entry: ArchiveEntry, in archive: Archive,
                     onProgress: (@Sendable (Double) -> Void)? = nil) async throws(EngineError) -> URL {
        let target = levels.first { $0.archive.id == archive.id }
        let (url, password) = try await passwords.retrying(archive.name, for: .unlock,
                                                          known: target?.password ?? archive.source?.password,
                                                          vaultURL: archive.source?.url) { password in
            try await self.previews.file(for: entry, in: archive, using: password, onProgress: onProgress)
        }
        if !Task.isCancelled, let password, let target { rememberPassword(password, in: target) }
        return url
    }

    /// Verify actual encrypted data: listing an ordinary ZIP doesn't test its password.
    /// Read one encrypted file inside the engine and discard its output, without writing to a
    /// user destination. A requested file takes precedence for ZIPs with different passwords.
    func unlockArchive(for entry: ArchiveEntry? = nil) {
        let target = level
        guard !isUnlocking, !isListing, let source = target.savedArchive.source,
              target.savedArchive.isEncrypted else { return }
        let encrypted = source.listing?.entries.filter { $0.isEncrypted && !$0.isFolder && !$0.isSymlink } ?? []
        let path = entry.flatMap { source.storedPaths[$0.path]?.first }
            ?? encrypted.min(by: { $0.size < $1.size })?.path
        guard let path else { return }
        isUnlocking = true
        unlockTask = Task { [weak self, passwords] in
            defer { self?.isUnlocking = false; self?.unlockTask = nil }
            do {
                let (_, password) = try await passwords.retrying(target.archive.name, for: .unlock,
                                                                  known: target.password, vaultURL: source.url) { password in
                    guard password != nil else { throw EngineError(.passwordRequired) }
                    let output = try await ArchiveEngine.shared.extract(source.url, paths: [path], password: password,
                                                                         excludeMacHelperFiles: false) { _ in }
                    ArchiveEngine.shared.discard(output)
                }
                guard !Task.isCancelled, let password, let self else { return }
                rememberPassword(password, in: target)
                quickLook.selectionChanged()
            } catch {
                if !Task.isCancelled { self?.report(error, step: .quickLook, count: 1, name: target.archive.name) }
            }
        }
    }

    func cancelUnlocking() {
        unlockTask?.cancel()
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
        perform(.moveToApplications, itemCount: 1, name: Installer.displayName(entry.name), destination: { grant?.url ?? target },
                needs: entry.size, prepare: { () async throws(EngineError) in
            grant = try await FolderAccess.request(
                target, purpose: String(localized: "To install “\(Installer.displayName(entry.name))”, Stow needs permission to add apps to this folder."))
        }) { [weak self] progress throws(EngineError) in
            guard let grant else { throw EngineError(.cancelled) }
            defer { grant.release() }
            let outcome = try await Installer.installApp(entry, from: archive, into: grant.url,
                                                         removeQuarantine: Preferences.current.removeQuarantine,
                                                         ask: Prompts.ask, onProgress: progress)
            self?.signatures[entry.path] = outcome.verdict
            var findings = [Self.finding(outcome.verdict, app: entry.name)]
            if outcome.quarantineRemoved == false {
                findings.append(CheckupFinding(severity: .info, title: String(localized: "Quarantine flag kept"),
                                               detail: String(localized: "macOS doesn’t let a sandboxed app remove it, so Gatekeeper checks “\(Installer.displayName(entry.name))” the first time it opens.")))
            }
            let folder = FileManager.default.displayName(atPath: grant.url.path)
            return Finished(placed: [outcome.app],
                            title: outcome.replaced ? String(localized: "Updated in \(folder)") : String(localized: "Installed in \(folder)"),
                            findings: findings,
                            aftercare: (Preferences.current.afterInstall, Preferences.Key.afterInstall, String(localized: "“\(Installer.displayName(entry.name))” is installed.")))
        }
    }

    private func installFonts(_ entries: [ArchiveEntry]) {
        let archive = archive
        let target = FolderAccess.override ?? FolderAccess.userFonts
        var grant: FolderAccess.Grant?
        perform(.installFonts(count: entries.count), itemCount: entries.count,
                name: entries.count == 1 ? entries[0].name : nil, destination: { grant?.url ?? target },
                prepare: { () async throws(EngineError) in
            grant = try await FolderAccess.request(target, purpose: String(localized: "To install fonts, Stow needs permission to add them to your font library."))
        }) { progress throws(EngineError) in
            guard let grant else { throw EngineError(.cancelled) }
            defer { grant.release() }
            let outcome = try await Installer.installFonts(entries, from: archive, into: grant.url, ask: Prompts.ask,
                                                           onProgress: progress)
            var title = outcome.installed.count == 1 ? String(localized: "Font installed") : String(localized: "\(outcome.installed.count) fonts installed")
            if !outcome.skipped.isEmpty { title += String(localized: " · \(outcome.skipped.count) already there") }
            if !outcome.unusable.isEmpty { title += String(localized: " · \(outcome.unusable.count) not installable") }
            return Finished(placed: outcome.installed, title: title,
                            aftercare: (Preferences.current.afterInstall, Preferences.Key.afterInstall, String(localized: "The fonts are installed.")))
        }
    }

    private func openInstaller(_ entry: ArchiveEntry) {
        let archive = archive
        let beside = FolderAccess.override ?? archive.source?.url.deletingLastPathComponent() ?? FolderAccess.home
        var grant: FolderAccess.Grant?
        perform(.openInstaller, itemCount: 1, name: entry.name, destination: { grant?.url ?? beside }, needs: entry.size,
                prepare: { () async throws(EngineError) in
            grant = try await FolderAccess.request(
                beside, purpose: String(localized: "To open “\(entry.name)” in Installer, Stow unpacks it next to the archive for a moment."))
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
        perform(step, itemCount: entries.count, destination: { grant?.url ?? folder },
                needs: entries.reduce(Int64(0)) { $0 + $1.size }, prepare: { () async throws(EngineError) in
            grant = try await FolderAccess.request(FolderAccess.override ?? folder,
                                                   purpose: String(localized: "The disk image asks for this to be copied here."))
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
        withAnimation(Motion.current(.linear(duration: 0.1))) { activity?.phase = .running(fraction) }
    }

    /// Pack…: the selection is staged in a temporary folder, then the Pack sentence takes over
    /// (it removes the folder when it's done). Stop works while staging, as for any step.
    private func pack(_ entries: [ArchiveEntry]) {
        let archive = archive
        let directory = levels.first?.archive.source?.url.deletingLastPathComponent()
        activityTask?.cancel()
        activity = Activity(step: .pack, itemCount: entries.count, phase: .running(0))
        activityTask = Task { [weak self, passwords] in
            do throws(EngineError) {
                let (staged, password) = try await passwords.retrying(archive.name, for: .extract,
                                                                      known: archive.source?.password,
                                                                      vaultURL: archive.source?.url) { password in
                    var attempt = archive
                    attempt.source?.password = password
                    return try await Extraction.stage(attempt, selection: entries, near: FileManager.default.temporaryDirectory,
                                                      skipSystemFiles: false) { fraction in
                        Task { @MainActor in self?.advance(to: fraction) }
                    }
                }
                guard let self, !Task.isCancelled else { return staged.discard() }
                if let password { rememberPassword(password) }
                var request = await PackRequest.gather(staged.items(allFolder: .automatic, folderName: archive.name).map(\.0))
                request.directory = directory
                request.cleanupDirectory = staged.folder
                activity = nil
                onPack?(request)
            } catch {
                guard let self, error.failure != .cancelled else { return }
                let failure = Failure(error, .pack, name: entries.count == 1 ? entries[0].name : archive.name)
                withAnimation(Motion.current(Motion.status)) { activity?.phase = .failed(failure) }
            }
        }
    }

    /// Sample archives have nothing on disk: Pack… shows the sentence for the selection's names and sizes.
    private func packSample(_ entries: [ArchiveEntry]) {
        let files = entries.flatMap { entry in
            let base = entry.parent.isEmpty ? "" : entry.parent + "/"
            let inside = archive.files.filter { $0.path.hasPrefix(entry.path + "/") }
            return ([entry] + inside).map { PackFile(path: String($0.path.dropFirst(base.count)), size: $0.size, isFolder: $0.isFolder) }
        }
        onPack?(PackRequest(files: files))
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
                withAnimation(Motion.current(.linear(duration: 0.055))) {
                    self?.activity?.phase = .running(Double(tick) / 20)
                }
            }
            withAnimation(Motion.current(Motion.status)) { self?.activity?.phase = .done }
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            withAnimation(Motion.current(Motion.exit)) { self?.activity = nil }
        }
    }

    /// Stops a running step; a cancelled extraction leaves nothing behind.
    func cancelActivity() {
        activityTask?.cancel()
        withAnimation(Motion.current(Motion.exit)) { activity = nil }
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

    /// A failed step's one next step.
    func follow(_ action: Failure.Action) {
        let again = lastRun
        dismissActivity()
        switch action {
        case .tryAgain, .chooseFolder: again?()
        case .showInFinder:
            if let url = archive.source?.url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        case .openInStow, .openInFinder: break
        }
    }

    /// Design review only: shows a capsule state without running anything.
    func previewActivity(_ activity: Activity) {
        activityTask?.cancel()
        self.activity = activity
    }
}
