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

    var archive: Archive
    var folder = ""
    var selection: Set<ArchiveEntry.ID> = []
    var viewMode: ViewMode = .grid
    var query = ""
    var showInspector = true
    private(set) var activity: Activity?
    /// Code signature verdicts for app entries, by path (from an install or the inspector's check).
    private(set) var signatures: [String: CodeSignature.Verdict] = [:]
    private(set) var checkingSignature: String?
    /// Set by `AppState`: the archive went to the Trash / the window should close after a step.
    var onArchiveGone: (() -> Void)?
    var onCloseWindow: (() -> Void)?

    private var activityTask: Task<Void, Never>?

    init(archive: Archive) {
        self.archive = archive
        // A disk image opens at its volume, with the one thing to install already selected.
        folder = archive.volumeRoot
        if let suggested = Self.suggestedSelection(in: archive) { selection = [suggested] }
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
        case .openInside, .quickLook: simulate(step, itemCount: items.count)
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
        }) { progress throws(EngineError) in
            guard let destination else { throw EngineError(.cancelled) }
            let options = Extraction.Options.current(resolve: ConflictPolicy().resolver)
            let result = try await Extraction.run(archive, selection: selection, to: destination, options: options,
                                                  onProgress: progress)
            var finished = Finished(placed: result.placed, findings: Checkup.findings(for: result.report))
            if result.placed.isEmpty { finished.title = "Nothing new — everything was already there" }
            if selection == nil {
                finished.aftercare = (Preferences.current.afterExtractAll, Preferences.Key.afterExtractAll, "Everything was extracted.")
            }
            return finished
        }
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
        perform(.openInstaller, itemCount: 1) { progress throws(EngineError) in
            _ = try await Installer.openInstaller(entry, from: archive, onProgress: progress)
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
            return Finished(placed: result.placed, findings: Checkup.findings(for: result.report))
        }
    }

    /// Extracts into a private temporary folder and opens each item with its default app.
    func openWithDefaultApp(_ entries: [ArchiveEntry]) {
        let archive = archive
        perform(.extract, itemCount: entries.count) { progress throws(EngineError) in
            let folder = TemporaryOpen.makeFolder()
            let result = try await Extraction.run(archive, selection: entries, to: folder, onProgress: progress)
            for url in result.placed { NSWorkspace.shared.open(url) }
            return Finished(title: entries.count == 1 ? "Opened “\(entries[0].name)”" : "Opened \(entries.count) items")
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
                              title: "“\(Installer.displayName(app))”: \(base.title.prefix(1).lowercased() + base.title.dropFirst())",
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
