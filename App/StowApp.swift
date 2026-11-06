import SwiftUI
import UniformTypeIdentifiers

@Observable
final class AppState {
    struct OpenFailure: Identifiable {
        let id = UUID()
        let failure: Failure
        var url: URL?
    }

    let tray: TrayController
    let packing = PackController()
    let system = SystemActions()
    let passwords = PasswordPrompt()
    let glance = GlanceController()
    /// Tests and demo scenes keep their own history, leaving the user's stored list untouched.
    let recents = RecentArchives.forApplication()
    var browser: BrowserModel?
    /// A native window close leaves Stow running without presenting a replacement window.
    private(set) var mainWindowDismissed = false
    var archiveDraft: ArchiveDraft?
    var showCreationWindow: () -> Void = {}
    var closeCreationWindow: () -> Void = {}
    var packRequest: PackRequest?
    private(set) var pendingCommands = 0
    private struct FinishingArchive {
        var model: BrowserModel
        var scopedURL: URL?
        var grant: SourceReadAccess.Grant?
    }
    private var finishingBrowsers: [FinishingArchive] = []
    var hasLifetimeWork: Bool {
        isBusy || packRequest != nil || isChoosingArchive || isChoosingBatch
            || tray.hasRelatedInteraction || archiveDraft?.packRequest != nil
            || archiveDraft?.isChoosingSources == true
            || finishingBrowsers.contains { if case .failed = $0.model.activity?.phase { true } else { false } }
    }
    var isChoosingArchive = false
    var isChoosingBatch = false
    private(set) var isOpening = false
    private(set) var openingName: String?
    /// Loading and open failures belong to Browser too, without a Welcome interlude.
    var usesBrowserWindow: Bool { browser != nil || isOpening || (openingName != nil && openFailure != nil) }
    var presentationDefaults = UserDefaults.standard

    func rememberArchiveWindow(_ window: SettingsKeys.ArchiveWindow) {
        // Snapshot fixtures and unit tests must not overwrite the user's last-used window.
        guard UserDefaults.standard.string(forKey: "StowScene") == nil,
              NSClassFromString("XCTestCase") == nil || presentationDefaults !== UserDefaults.standard else { return }
        presentationDefaults.set(window.rawValue, forKey: SettingsKeys.lastArchiveWindow)
    }
    private var openingTask: Task<Void, Never>?
    private var openingID = UUID()
    var openFailure: OpenFailure?
    /// A cloud placeholder being downloaded before it opens.
    var cloudDownload: CloudDownload?

    /// The open archive's security scope (Open panel URLs need it claimed; dropped URLs don't).
    private var scopedURL: URL?
    private var sourceGrant: SourceReadAccess.Grant?
    /// Successful opens warn once per source folder for this app session.
    private var warnedSourceFolders: Set<String> = []
    var sourceReadAccess = SourceReadAccess()

    /// Brings back the main window (it may have been closed while Stow kept running).
    var showMainWindow: () -> Void = {}
    let batch = BatchQueue()

    init(traySettings: UserDefaults = .standard) {
        tray = TrayController(settings: traySettings)
        tray.app = self
        system.app = self
        glance.app = self
        packing.onDirectoryCleaned = { [weak self] url in
            self?.tray.removeCleanedTemporaryGroup(at: url)
        }
        TrayTemporaryGroups.purgeAbandoned(keeping: [])
        batch.onOpen = { [weak self] url in
            self?.openPreferred(url)
        }
        // Copies opened in a default app last time.
        TemporaryOpen.removeAll()
        OtherAppFiles.removeReceived()
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil,
                                               queue: .main) { _ in MainActor.assumeIsolated { PackageHandoff.removeAll() } }
    }

    /// Extracting, packing, opening or a browser action is running. Updates wait for it (#35), and
    /// Settings holds off cleaning temporary files.
    var isBusy: Bool {
        if archiveDraft?.isImporting == true || archiveDraft?.isSaving == true { return true }
        if pendingCommands > 0 || system.pendingRequests > 0 || system.running > 0
            || finishingBrowsers.contains(where: { if case .running = $0.model.activity?.phase { true } else { false } }) { return true }
        if packing.isRunning || batch.isActive || isOpening || browser?.isUnlocking == true || passwords.question != nil { return true }
        if case .running = browser?.activity?.phase { return true }
        return false
    }

    /// Lists a real archive through the engine and shows it in the browser.
    func open(_ url: URL) {
        mainWindowDismissed = false
        cancelOpening()
        openFailure = nil
        let id = UUID()
        openingID = id
        isOpening = true
        openingName = url.lastPathComponent
        let scoped = url.startAccessingSecurityScopedResource()
        openingTask = Task {
            var recovered: SourceReadAccess.Grant?
            var transferred = false
            defer {
                if !transferred {
                    if scoped { url.stopAccessingSecurityScopedResource() }
                    recovered?.release()
                }
                if openingID == id { isOpening = false; openingTask = nil }
            }
            do {
                if let browser, !(await browser.confirmDiscardingEdits()) {
                    return
                }
                try Task.checkCancellation()
                try await waitForCloudDownload(url)
                recovered = try await sourceReadAccess.acquire(url)
                try Task.checkCancellation()
                guard openingID == id else { throw CancellationError() }
                try await DownloadCheck.waitUntilComplete(url)
                let listing: ArchiveListing
                let password: String?
                do {
                    // 7z archives with an encrypted file list need the password just to be listed.
                    (listing, password) = try await passwords.retrying(url.lastPathComponent, for: .open, vaultURL: url) { password in
                        try await self.listForBrowser(url, password: password, id: id)
                    }
                } catch {
                    throw DiskImageCheck.explain(EngineError(error), for: url)
                }
                var archive = await Self.makeArchive(listing, url: url)
                if Task.isCancelled || openingID != id { throw EngineError(.cancelled) }
                archive.source?.password = password
                releaseScope()
                scopedURL = scoped ? url : nil
                sourceGrant = recovered
                transferred = true
                // Files received from a drag (Mail, chat apps) live in a folder Stow empties at launch.
                if !OtherAppFiles.isReceived(url) { recents.add(url) }
                if browser?.isListing == true { browser?.applyListing(archive, complete: true) }
                else {
                    browser?.quickLook.close()
                    browser = makeBrowser(archive)
                }
                browser?.verifyDiskImage()
                if let recovered, let error = recovered.persistenceError, let browser,
                   warnedSourceFolders.insert(recovered.url.standardizedFileURL.path).inserted {
                    browser.sourceAccessNotice = Self.unsavedSourceAccess(error)
                }
            } catch {
                let denied = error as? SourceReadAccess.Denied
                let underlying = error
                let error = error is CancellationError ? EngineError(.cancelled) : EngineError(error)
                if openingID == id, browser?.isListing == true { browser = nil }
                if openingID == id, error.failure != .cancelled {
                    var failure = denied.map { OtherAppFiles.unreadable(url, code: $0.code) }
                        ?? Failure(underlying, .open, name: url.lastPathComponent)
                    // Disk images Stow can't read (encrypted, unusual formats) can still be opened by macOS.
                    if DiskImageCheck.isDiskImage(url), failure.kind == .notAnArchive || failure.kind == .other {
                        let original = failure
                        failure = Failure(kind: .notAnArchive, title: String(localized: "Stow can’t look inside “\(url.lastPathComponent)”"),
                                          advice: error.message, action: .openInFinder, code: original.code)
                        failure.diagnostic = original.diagnostic
                    }
                    openFailure = OpenFailure(failure: failure, url: url)
                }
            }
        }
    }

    /// The archive opened, but its folder's grant couldn't be saved for next time.
    static func unsavedSourceAccess(_ error: Error) -> Failure {
        var notice = Failure(String(localized: "Folder access wasn’t saved"),
                             advice: String(localized: "The archive is open for now, but Stow couldn’t save access to this folder, so it may ask again next time."))
        notice.diagnostic = String(describing: error)
        return notice
    }

    /// Design-review scenes: the opening state with nothing being read.
    func showOpeningForDemo(name: String? = nil) {
        cancelOpening()
        isOpening = true
        openingName = name
    }

    func cancelOpening() {
        openingTask?.cancel()
        openingTask = nil
        openingID = UUID()
        isOpening = false
        if browser?.isListing == true { browser = nil }
    }

    /// One ordered consumer keeps chunks and model construction out of independent callback tasks.
    private func listForBrowser(_ url: URL, password: String?, id: UUID) async throws -> ArchiveListing {
        let (chunks, continuation) = AsyncStream<[ListedEntry]>.makeStream()
        let listing = Task {
            defer { continuation.finish() }
            return try await ArchiveEngine.shared.list(url, password: password) {
                continuation.yield($0)
            }
        }
        defer { listing.cancel() }
        return try await withTaskCancellationHandler {
            var entries: [ListedEntry] = []
            var nextCount = 2_048
            for await chunk in chunks {
                if Task.isCancelled { throw EngineError(.cancelled) }
                entries.append(contentsOf: chunk)
                guard entries.count >= nextCount else { continue }
                // Geometric snapshots bound total entries rebuilt to O(n), rather than O(n²).
                nextCount = entries.count * 2
                let partial = ArchiveListing(type: url.pathExtension, entries: entries)
                var archive = await Self.makeArchive(partial, url: url)
                if Task.isCancelled { throw EngineError(.cancelled) }
                guard openingID == id else { throw EngineError(.cancelled) }
                archive.source?.password = password
                if browser?.isListing == true { browser?.applyListing(archive, complete: false) }
                else {
                    browser = makeBrowser(archive, isListing: true)
                }
            }
            return try await listing.value
        } onCancel: { listing.cancel() }
    }

    /// An iCloud (or other cloud) placeholder comes down first, with its progress on screen and
    /// a Cancel button. Files already on this Mac go straight through, with nothing shown.
    private func waitForCloudDownload(_ url: URL) async throws(EngineError) {
        let download = CloudDownload(url: url)
        defer {
            if cloudDownload === download { cloudDownload = nil }
            DownloadPercent.shared.stop()
        }
        try await CloudPlaceholder.waitForDownload(url, isCancelled: { download.isCancelled }) { fraction in
            if cloudDownload !== download { cloudDownload = download }
            download.fraction = fraction
        }
    }

    /// Stops waiting for the download on screen (Cancel, Escape).
    func cancelCloudDownload() {
        cloudDownload?.cancel()
        cloudDownload = nil
    }

    /// A failed open's one next step.
    func follow(_ action: Failure.Action, opening url: URL) {
        switch action {
        case .showInFinder: NSWorkspace.shared.activateFileViewerSelecting([url])
        case .openInFinder: NSWorkspace.shared.open(url)
        case .tryAgain, .openInStow: open(url)
        case .chooseFolder: break
        }
    }

    /// Shows the Pack sentence for files and folders from anywhere (drops, the Tray, New Archive).
    /// `cleanupTemporaryGroups` are app-owned Tray folders removed only after a successful pack (#179).
    func pack(_ urls: [URL], cleanupTemporaryGroups: [URL] = []) {
        guard !urls.isEmpty else { return }
        pendingCommands += 1
        Task {
            defer { pendingCommands -= 1 }
            var request = await PackRequest.gather(urls)
            guard !request.files.isEmpty else { return }
            // Ownership is explicit: only attach directories that are known temporary groups.
            let owned = cleanupTemporaryGroups.filter { TrayTemporaryGroups.isOwned($0) }
            if owned.count == 1, let folder = owned.first,
               urls.map({ $0.resolvingSymlinksInPath().standardizedFileURL }) == [folder.resolvingSymlinksInPath().standardizedFileURL] {
                request.cleanupDirectory = folder
                request.cleanupOnlyOnSuccess = true
                // Don't offer the caches TrayGroups folder as the archive destination.
                if let directory = request.directory, TrayTemporaryGroups.isOwned(directory) {
                    request.directory = GatherDestination.remembered()
                        ?? FolderAccess.home.appending(path: "Desktop", directoryHint: .isDirectory)
                }
            }
            showMainWindow()
            packRequest = request
        }
    }

    func extractAndRepack(_ model: BrowserModel) {
        // Snapshot/sample scenes must never start extraction or packing work.
        guard !model.isListing, model.archive.source != nil else { return }
        Task {
            do {
                let archive = model.archive
                let (staged, password) = try await model.passwords.retrying(archive.name, for: .extract, known: model.level.password,
                                                                            vaultURL: archive.source?.url) { password in
                    var input = archive
                    input.source?.password = password
                    return try await Extraction.stage(input, selection: nil, near: FileManager.default.temporaryDirectory,
                                                       skipSystemFiles: false, onProgress: { _ in })
                }
                model.level.password = password
                do {
                    let urls = try FileManager.default.contentsOfDirectory(at: staged.root, includingPropertiesForKeys: nil)
                    var request = await PackRequest.gather(urls)
                    request.directory = model.levels.first?.archive.source?.url.deletingLastPathComponent()
                    var stem = (archive.name as NSString).deletingPathExtension
                    if stem.lowercased().hasSuffix(".tar") { stem = (stem as NSString).deletingPathExtension }
                    request.suggestedNameOverride = stem
                    request.initialFormat = .zip
                    request.cleanupDirectory = staged.folder
                    packRequest = request
                } catch { staged.discard(); throw error }
            } catch { model.editSession.message = EngineError(error).message }
        }
    }

    func beginNewArchive() {
        guard passwords.question == nil else { return }
        if archiveDraft == nil { archiveDraft = ArchiveDraft() }
        showCreationWindow()
    }

    func discardArchiveDraft() {
        guard let draft = archiveDraft, !draft.isSaving else { return }
        draft.close()
        closeCreationWindow()
        if archiveDraft === draft { archiveDraft = nil }
    }

    /// Quick Pack: pick what to pack.
    func chooseFilesToPack() {
        pendingCommands += 1
        Task {
            defer { pendingCommands -= 1 }
            pack(await PackDestination.chooseSources())
        }
    }

    /// URLs macOS opened Stow with. Archives open in the browser (the first one; Stow has one window).
    func receive(_ urls: [URL]) {
        for url in urls where Handoff.isHandoff(url) {
            system.receive(url)
        }
        if let archive = urls.first(where: \.isFileURL) {
            NSApp.activate()
            openPreferred(archive)
        }
    }

    /// Establish the destination and loading state before showing a window.
    func openPreferred(_ url: URL) {
        if SettingsKeys.archiveWindow(in: presentationDefaults) == .glance {
            glance.open(url)
        } else {
            glance.close()
            open(url)
            showMainWindow()
        }
    }

    /// File › Open Recent and the welcome window's Recent list.
    func openRecent(_ entry: RecentArchives.Entry) {
        guard let url = recents.url(for: entry) else { return }
        openPreferred(url)
    }

    /// Explicit browser download keeps the main app offline and never fabricates an archive.
    func downloadSample() { NSWorkspace.shared.open(SampleDownload.url) }

    /// In-memory sample for explicitly requested design-review scenes only.
    func openArchive(named name: String) {
        openDemo(SampleArchive.make(named: name))
    }

    /// Any in-memory listing, for design-review scenes (the install walkthrough's prototype build).
    func openDemo(_ archive: Archive) {
        mainWindowDismissed = false
        cancelOpening()
        releaseScope()
        browser = makeBrowser(archive)
    }

    private func makeBrowser(_ archive: Archive, isListing: Bool = false) -> BrowserModel {
        let model = BrowserModel(archive: archive, isListing: isListing)
        model.passwords = PasswordHook(prompt: passwords)
        // A retained background job may finish after a different archive has taken over.
        model.onArchiveGone = { [weak self, weak model] in
            guard let self, let model, self.browser === model, !self.isOpening else { return }
            self.closeArchive()
        }
        model.onCloseWindow = { [weak self, weak model] in
            guard let self, let model, self.browser === model, !self.isOpening else { return }
            self.closeWindow()
        }
        // The Pack sentence is a sheet on the full window, so Glance hands over to it first.
        model.onPack = { [weak self] request in
            self?.glance.expand(byKeyboard: false)
            self?.packRequest = request
        }
        return model
    }

    /// "Close the window after Extract All or an install": the archive closes with it.
    func closeWindow() {
        let archiveWindow = browser?.editingWindow
        cancelOpening()
        glance.close()
        // Never pick an arbitrary visible window: Settings or a new draft may be in front.
        if let archiveWindow, archiveWindow !== glance.window { archiveWindow.performClose(nil) }
    }

    /// Extracts several archives, one after another, into a folder chosen once.
    func extractArchives(_ urls: [URL]) {
        pendingCommands += 1
        Task {
            defer { pendingCommands -= 1 }
            guard let destination = await ExtractDestination.choose(count: urls.count, near: urls.first) else { return }
            batch.enqueue(urls, into: destination)
        }
    }

    func closeArchive() {
        let model = browser
        let opening = openingID
        Task {
            guard browser === model, openingID == opening else { return }
            guard await model?.confirmDiscardingEdits() ?? true else { return }
            guard browser === model, openingID == opening else { return }
            mainWindowDismissed = false
            clearArchive()
        }
    }

    /// Called only after AppKit has accepted the close (including the unsaved-edits decision).
    /// Automatic Welcome/Browser handovers and transfers to Glance do not end the session.
    func mainWindowDidClose(_ host: AppRoot.Host) {
        guard WindowSwitch.ownsOpening(host, hasArchive: usesBrowserWindow,
                                       glanceIsShown: glance.isShown) else { return }
        mainWindowDismissed = true
        clearArchive()
    }

    func prepareToShowMainWindow() {
        mainWindowDismissed = false
        // Closing a window must not make an accepted operation unreachable on reopen.
        if browser == nil, !isOpening, let work = finishingBrowsers.popLast() {
            browser = work.model
            scopedURL = work.scopedURL
            sourceGrant = work.grant
        }
    }

    func releaseFinishedWork() {
        finishingBrowsers.removeAll {
            if case .running = $0.model.activity?.phase { return false }
            // A failed accepted operation remains reachable on reopening, including its retry state.
            if case .failed = $0.model.activity?.phase { return false }
            $0.scopedURL?.stopAccessingSecurityScopedResource()
            $0.grant?.release()
            return true
        }
    }

    private func clearArchive() {
        releaseFinishedWork()
        if let browser, case .running = browser.activity?.phase {
            finishingBrowsers.append(FinishingArchive(model: browser, scopedURL: scopedURL, grant: sourceGrant))
            scopedURL = nil
            sourceGrant = nil
        }
        browser?.quickLook.close()
        browser?.cancelUnlocking()
        cancelCloudDownload()
        cancelOpening()
        releaseScope()
        browser = nil
        openingName = nil
        openFailure = nil
    }

    private func releaseScope() {
        sourceGrant?.release()
        sourceGrant = nil
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
    }

    /// Mapping a listing with tens of thousands of entries shouldn't hold up the main thread.
    @concurrent
    private static func makeArchive(_ listing: ArchiveListing, url: URL) async -> Archive {
        Archive(listing: listing, url: url)
    }
}

@main
struct StowApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var app: AppState

    init() {
        let store = UserDefaults.standard
        let domain = store.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "app.stow.Stow") ?? [:]
        if NSClassFromString("XCTestCase") == nil, store.string(forKey: "StowScene") == nil {
            SettingsKeys.migrateTray(in: store, persistent: domain)
        }
        _app = State(initialValue: AppState())
    }
    @AppStorage(SettingsKeys.appearance) private var appearance = "system"
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some Scene {
        let _ = configureRouting()
        // The welcome is a window of its own, fixed and compact as welcome windows usually are. It's
        // up while no archive is open; the Browser takes over when one opens and hands back on close.
        Window("Stow", id: "welcome") {
            WelcomeWindow()
                .environment(app)
                .onAppear { delegate.app = app; SettingsAppearance.apply() }
                .onChange(of: appearance) { SettingsAppearance.apply() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .commands {
            StowCommands(app: app)
            EditingUndoCommands()
            BrowseCommands(app: app)
            GlanceCommands(app: app)
        }
        // Not at launch and not in the Window menu: the welcome opens it, with an archive to show.
        Window("Stow", id: "main") {
            RootView()
                .environment(app)
                .onAppear { delegate.app = app; SettingsAppearance.apply() }
                .onChange(of: appearance) { SettingsAppearance.apply() }
        }
        .defaultSize(width: 1120, height: 700)
        .windowToolbarStyle(.unified)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .commandsRemoved()
        Window("Welcome to Stow", id: "onboarding") {
            OnboardingView().environment(app)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        Window("Create Archive", id: "creation") {
            if let draft = app.archiveDraft { ArchiveDraftView(draft: draft).environment(app) }
        }
        // The Browser's window and title bar (#302): room for the files and Details side by side.
        .defaultSize(width: 980, height: 620)
        .windowToolbarStyle(.unified)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .commandsRemoved()
        Settings {
            SettingsView().environment(app)
        }
        .windowResizability(.contentSize)
    }

    private func configureRouting() {
        let open = openWindow
        app.showMainWindow = { [weak app] in
            guard let app else { return }
            app.prepareToShowMainWindow()
            let id = app.usesBrowserWindow ? "main" : "welcome"
            ApplicationLifecycle.shared.presentWindow(id) { open(id: id) }
        }
        let dismiss = dismissWindow
        app.closeCreationWindow = { dismiss(id: "creation") }
        app.showCreationWindow = { [weak app] in
            ApplicationLifecycle.shared.presentWindow("creation") { open(id: "creation") }
            if app?.usesBrowserWindow == false { dismiss(id: "welcome") }
        }
        SettingsRouter.shared.open = {
            ApplicationLifecycle.shared.presentWindow("com_apple_SwiftUI_Settings_window") { openSettings() }
        }
        OnboardingRouter.shared.open = { open(id: "onboarding") }
        delegate.app = app
    }
}

/// The Browser window. It only ever shows an open archive: with none, the welcome takes over (`AppRoot`).
struct RootView: View {
    @Environment(AppState.self) private var app
    @State private var rootWindow: NSWindow?

    var body: some View {
        Group {
            if let browser = app.browser {
                BrowserView(model: browser)
                    .overlay(alignment: .bottom) { PackActivityAccessory() }
            } else {
                BrowserOpeningView(name: app.openingName ?? "", isOpening: app.isOpening) {
                    app.cancelCloudDownload(); app.cancelOpening()
                }
            }
        }
        .background {
            WindowReader { window in
                rootWindow = window
                // State restoration is off, so the Browser keeps its size and place this way.
                window.setFrameAutosaveName("Browser")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
            guard let window = notification.object as? NSWindow, window === rootWindow else { return }
            app.mainWindowDidClose(.browser)
        }
        .modifier(AppRoot(host: .browser))
    }
}

/// The Browser before its archive arrives (opened from Finder, Recent or a drop on the welcome),
/// or behind the failure card when it can't be opened. It already has the Browser's title bar:
/// the same toolbar height and hidden bar, so the window's controls don't move, and the archive's
/// name where its title menu will be. The files, path and Details arrive together with the listing.
private struct BrowserOpeningView: View {
    let name: String
    let isOpening: Bool
    let cancel: () -> Void

    private var kind: String {
        ArchiveFormat.infer(fromName: name).map { String(localized: "\($0.displayName) archive") } ?? ""
    }

    var body: some View {
        ZStack {
            if isOpening { ArchiveOpeningStatus(name: name, cancel: cancel) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(name.isEmpty ? "Stow" : name)
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                if !name.isEmpty {
                    ArchiveTitleLabel(title: name, subtitle: kind, showsChevron: false)
                        .accessibilityElement(children: .combine)
                }
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }
}

/// What both of Stow's windows carry: the sheets and file panels Stow presents app-wide, the launch
/// setup, and the hand-over between the welcome and the Browser. Only the window in charge, the
/// welcome with no archive open and the Browser with one, presents anything, so nothing shows twice
/// while one window replaces the other.
struct AppRoot: ViewModifier {
    enum Host { case welcome, browser }
    let host: Host

    @Environment(AppState.self) private var app
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openSettings) private var openSettings

    private var isHost: Bool { (host == .browser) == app.usesBrowserWindow }

    func body(content: Content) -> some View {
        @Bindable var app = app
        content
            .sheet(item: isHost ? $app.packRequest : .constant(nil)) { PackSheet(request: $0).environment(app) }
            // A second importer on the same view would be ignored, so this one sits on a background.
            .background {
                Color.clear.fileImporter(isPresented: isHost ? $app.isChoosingBatch : .constant(false),
                                         allowedContentTypes: [.archive, .diskImage, .data],
                                         allowsMultipleSelection: true) { result in
                    if case .success(let urls) = result, !urls.isEmpty { app.extractArchives(urls) }
                }
            }
            .passwordSheet(app.passwords, isActive: isHost && !app.glance.isShown)
            .fileImporter(isPresented: isHost ? $app.isChoosingArchive : .constant(false),
                          allowedContentTypes: [.archive, .diskImage, .data]) { result in
                if case .success(let url) = result { app.openPreferred(url) }
            }
            .sheet(item: isHost ? $app.openFailure : .constant(nil)) { open in
                FailureCard(failure: open.failure) { action in
                    app.openFailure = nil
                    if let action, let url = open.url { app.follow(action, opening: url) }
                }
            }
            .cloudDownloadSheet(app, isActive: isHost && !app.glance.isShown)
            .overlay(alignment: .bottomTrailing) { if isHost { BatchStack(queue: app.batch) } }
            .onChange(of: app.usesBrowserWindow, initial: true) { _, browser in handOver(noArchive: !browser) }
    }

    /// An archive opened in the welcome, or the Browser's archive closed: the other window takes
    /// over. Glance showing the archive keeps the Browser away. A key press switches them without
    /// window animation (DESIGN.md › Motion).
    private func handOver(noArchive: Bool) {
        guard !app.mainWindowDismissed else { return }
        if app.glance.isShown {
            dismissWindow(id: host == .welcome ? "welcome" : "main")
            return
        }
        let leaving: String, arriving: String?
        switch host {
        case .welcome where !noArchive: (leaving, arriving) = ("welcome", app.glance.isShown ? nil : "main")
        case .browser where noArchive: (leaving, arriving) = ("main", "welcome")
        default: return
        }
        WindowSwitch.animation = Motion.byKeyboard ? .none : .default
        for window in GlanceController.mainWindows { window.animationBehavior = WindowSwitch.animation }
        if let arriving {
            ApplicationLifecycle.shared.presenting(arriving)
            openWindow(id: arriving)
        }
        dismissWindow(id: leaving)
    }
}

/// How the welcome comes up after a switch; the Browser's own opening is Glance's (`prepareMainWindow`).
@MainActor enum WindowSwitch {
    static var animation = NSWindow.AnimationBehavior.default

    /// Automatic handover closes the former host after a replacement load has already begun.
    /// Only the currently responsible presentation may interpret a close as cancellation.
    static func ownsOpening(_ host: AppRoot.Host, hasArchive: Bool, glanceIsShown: Bool) -> Bool {
        guard !glanceIsShown else { return false }
        switch host {
        case .welcome: return !hasArchive
        case .browser: return hasArchive
        }
    }
}

/// The pack capsule while packing: under the welcome, or over the Browser above its Next Steps.
struct PackActivityAccessory: View {
    @Environment(AppState.self) private var app
    @Environment(\.reducesMotion) private var reduceMotion

    var body: some View {
        let nextSteps = app.browser.map { !$0.selection.isEmpty || $0.activity != nil } ?? false
        ZStack {
            if app.packing.activity != nil {
                PackActivityBar(packing: app.packing)
                    .transition(.rise(reduceMotion: reduceMotion))
            }
        }
        .padding(.bottom, app.packing.activity == nil ? 0 : nextSteps ? 76 : Space.l)
        .animation(Motion.presence(app.packing.activity != nil, reduceMotion: reduceMotion), value: app.packing.activity == nil)
    }
}

struct StowCommands: Commands {
    let app: AppState

    var body: some Commands {
        // Sparkle (#35). Read here, in the Commands body, so the item enables once the updater starts.
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { AppUpdater.shared.checkForUpdates() }
                .disabled(!AppUpdater.shared.isAvailable)
        }
        CommandGroup(replacing: .newItem) {
            Button("New Archive…") { app.passwords.performCommand { app.beginNewArchive() } }
                .disabled(app.passwords.question != nil)
                .keyboardShortcut("n")
            Button("Open Archive…") { app.passwords.performCommand { app.isChoosingArchive = true } }
                .disabled(app.passwords.question != nil)
                .keyboardShortcut("o")
            // Read here, in the Commands body: a nested view's reads don't refresh the menu.
            OpenRecentMenu(entries: app.recents.visible, open: { entry in app.passwords.performCommand { app.openRecent(entry) } },
                           clear: { app.passwords.performCommand { app.recents.clear() } })
                .disabled(app.passwords.question != nil)
            Button("Extract Archives…") { app.passwords.performCommand { app.isChoosingBatch = true } }
                .disabled(app.passwords.question != nil)
                .keyboardShortcut("e", modifiers: [.command, .option])
            Divider()
            Button("Close Archive") { app.passwords.performCommand { app.closeArchive() } }
                .disabled(app.passwords.question != nil)
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(app.browser == nil)
        }
        CommandGroup(after: .help) {
            Button("Welcome to Stow") { OnboardingRouter.shared.open() }
            // The sample is a web download now, so it lives with the app's other web pages in Help,
            // not in File beside commands that open archives here. No ellipsis: nothing is asked
            // before the browser takes over.
            Divider()
            Button("Download Sample Archive") { app.downloadSample() }
                .disabled(app.passwords.question != nil)
            Button("Sample Credits and Licenses") { NSWorkspace.shared.open(SampleDownload.creditsURL) }
        }
        CommandGroup(after: .windowArrangement) {
            Button(app.tray.isEnabled ? (app.tray.isShown ? String(localized: "Hide Tray") : String(localized: "Show Tray")) : String(localized: "Tray Settings…")) {
                if app.tray.isEnabled { app.tray.toggle() } else { SettingsRouter.shared.show(.tray) }
            }
                .keyboardShortcut("t", modifiers: [.command, .option])
        }
    }
}
