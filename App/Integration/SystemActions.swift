import AppKit
import OSLog

/// Runs what Finder, the Services menu and other apps ask of Stow: extract here or somewhere,
/// open, compress. Results are revealed in Finder; problems are explained in an alert.
@Observable
final class SystemActions {
    weak var app: AppState?
    var packer: any ArchivePacking = Packers.current
    /// Jobs in flight; the Dock icon shows their combined progress.
    private(set) var running = 0
    private var progress: [UUID: Double] = [:]

    private static let log = Logger(subsystem: "app.stow.Stow", category: "system")

    // MARK: - Entry points

    /// A `stow://handoff/…` URL from the Finder extension.
    func receive(_ url: URL) {
        do {
            let request = try Handoff().receive(url)
            Self.log.info("Hand-off: \(request.action.rawValue, privacy: .public), \(request.paths.count) items")
            perform(request.action, on: request.urls, fromFinder: true)
        } catch {
            // Unknown, used or stale tokens are dropped without a word: they're replays, or pages
            // poking at the URL scheme. Nothing behind them was ever trusted.
            Self.log.notice("Ignored hand-off \(url.absoluteString, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    /// `fromFinder`: the paths came through the hand-off, so Stow may not be able to read them
    /// yet (Services and opened documents arrive with access already granted).
    func perform(_ action: HandoffAction, on urls: [URL], fromFinder: Bool = false) {
        guard !urls.isEmpty else { return }
        switch action {
        case .open:
            Task { await open(urls[0], fromFinder: fromFinder) }
        case .extractHere:
            Task { await extract(urls, to: nil) }
        case .extractTo:
            Task {
                guard let destination = await chooseDestination(for: urls) else { return }
                await extract(urls, to: destination)
            }
        case .compress:
            showPackSheet(urls)
        case .quickCompress:
            Task { await quickCompress(urls) }
        }
    }

    /// Services › Send to Stow: archives open in the browser, everything else goes to the Tray.
    func send(_ urls: [URL]) {
        let archives = urls.filter { ArchiveTypes.type(forFileName: $0.lastPathComponent) != nil }
        let others = urls.filter { ArchiveTypes.type(forFileName: $0.lastPathComponent) == nil }
        if let archive = archives.first { app?.showMainWindow(); app?.open(archive) }
        if !others.isEmpty, let tray = app?.tray {
            tray.items += others.map { TrayItem(name: $0.lastPathComponent, size: $0.fileSize, url: $0) }
            tray.show()
        }
    }

    // MARK: - Actions

    private func open(_ url: URL, fromFinder: Bool) async {
        if fromFinder, !(await FolderAccess.shared.readable(url, for: .open(url.lastPathComponent))) { return }
        app?.showMainWindow()
        app?.open(url)
    }

    /// `destination` nil: next to each archive.
    private func extract(_ archives: [URL], to destination: URL?) async {
        var placed: [URL] = []
        for url in archives {
            var folder = destination ?? url.deletingLastPathComponent()
            if destination == nil {
                guard let writable = await FolderAccess.shared.writableFolder(folder, for: .extract(url.lastPathComponent)) else { return }
                folder = writable
            }
            guard await FolderAccess.shared.readable(url, for: .extract(url.lastPathComponent)) else { return }
            do {
                placed += try await track { report in
                    let listing = try await ArchiveEngine.shared.list(url)
                    let archive = await Self.makeArchive(listing, url: url)
                    return try await Extraction.run(archive, selection: nil, to: folder, onProgress: report).placed
                }
            } catch {
                await explain(EngineError(error), archive: url, destination: folder)
            }
        }
        Self.log.info("Extracted \(archives.count) archives into \(placed.count) items")
        if !placed.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(placed) }
    }

    private func quickCompress(_ items: [URL]) async {
        let folder = items[0].deletingLastPathComponent()
        guard let writable = await FolderAccess.shared.writableFolder(folder, for: .compress) else { return }
        let target = QuickCompress.destination(for: items.map { writable.appending(path: $0.lastPathComponent) }) {
            FileManager.default.fileExists(atPath: $0.path)
        }
        do {
            let packer = packer
            try await track { report in
                try await packer.pack(items, options: QuickCompress.options, to: target, onProgress: report)
            }
            NSWorkspace.shared.activateFileViewerSelecting([target])
        } catch {
            await explain(EngineError(error), archive: nil, destination: target.deletingLastPathComponent())
        }
    }

    private func showPackSheet(_ urls: [URL]) {
        app?.showMainWindow()
        app?.packRequest = PackRequest(files: urls.map { PackFile(path: $0.lastPathComponent, size: $0.fileSize) })
    }

    private func chooseDestination(for archives: [URL]) async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Extract")
        panel.message = archives.count == 1
            ? String(localized: "Choose where to extract “\(archives[0].lastPathComponent)”.")
            : String(localized: "Choose where to extract \(archives.count) archives.")
        panel.directoryURL = archives[0].deletingLastPathComponent()
        NSApp.activate()
        return panel.runModal() == .OK ? panel.url : nil
    }

    // MARK: - Feedback

    private func explain(_ error: EngineError, archive: URL?, destination: URL? = nil) async {
        guard error.failure != .cancelled else { return }
        let failure = if let archive {
            Failure(error, .extract, name: archive.lastPathComponent, destination: destination ?? archive.deletingLastPathComponent())
        } else {
            Failure(error, .pack, name: String(localized: "the selection"), destination: destination)
        }
        guard let action = await Prompts.explain(failure), let archive else { return }
        switch action {
        case .openInStow:
            app?.showMainWindow()
            app?.open(archive)
        case .showInFinder:
            NSWorkspace.shared.activateFileViewerSelecting([archive])
        case .openInFinder:
            NSWorkspace.shared.open(archive)
        case .chooseFolder:
            perform(.extractTo, on: [archive])
        case .tryAgain:
            await extract([archive], to: destination)
        }
    }

    /// Runs a job while the Dock icon shows overall progress.
    private func track<T>(_ job: (@escaping @Sendable (Double) -> Void) async throws -> T) async throws -> T {
        let id = UUID()
        running += 1
        progress[id] = 0
        updateDock()
        defer {
            running -= 1
            progress[id] = nil
            updateDock()
        }
        return try await job { fraction in
            Task { @MainActor in
                guard self.progress[id] != nil else { return }
                self.progress[id] = fraction
                self.updateDock()
            }
        }
    }

    private func updateDock() {
        guard running > 0 else {
            NSApp.dockTile.badgeLabel = nil
            return
        }
        let overall = progress.values.reduce(0, +) / Double(max(progress.count, 1))
        NSApp.dockTile.badgeLabel = "\(Int(overall * 100))%"
    }

    @concurrent
    private static func makeArchive(_ listing: ArchiveListing, url: URL) async -> Archive {
        Archive(listing: listing, url: url)
    }
}
