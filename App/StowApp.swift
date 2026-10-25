import SwiftUI
import UniformTypeIdentifiers

@Observable
final class AppState {
    struct OpenFailure: Identifiable {
        let id = UUID()
        let failure: Failure
        var url: URL?
    }

    let tray = TrayController()
    let packing = PackController()
    let system = SystemActions()
    let passwords = PasswordPrompt()
    let glance = GlanceController()
    /// Demo scenes keep their own list so screenshots never show (or change) real history.
    let recents = RecentArchives(defaults: UserDefaults.standard.string(forKey: "StowScene") == nil ? .standard : nil)
    var browser: BrowserModel?
    var packRequest: PackRequest?
    var isChoosingArchive = false
    var isChoosingBatch = false
    private(set) var isOpening = false
    private var openingTask: Task<Void, Never>?
    private var openingID = UUID()
    var openFailure: OpenFailure?
    /// A cloud placeholder being downloaded before it opens.
    var cloudDownload: CloudDownload?

    /// The open archive's security scope (Open panel URLs need it claimed; dropped URLs don't).
    private var scopedURL: URL?

    /// Brings back the main window (it may have been closed while Stow kept running).
    var showMainWindow: () -> Void = {}
    let batch = BatchQueue()

    init() {
        tray.app = self
        system.app = self
        glance.app = self
        batch.onOpen = { [weak self] url in
            self?.showMainWindow()
            self?.open(url)
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
        if packing.isRunning || batch.isActive || isOpening || browser?.isUnlocking == true || passwords.question != nil { return true }
        if case .running = browser?.activity?.phase { return true }
        return false
    }

    /// Lists a real archive through the engine and shows it in the browser.
    func open(_ url: URL) {
        cancelOpening()
        let id = UUID()
        openingID = id
        isOpening = true
        let scoped = url.startAccessingSecurityScopedResource()
        openingTask = Task {
            defer { if openingID == id { isOpening = false; openingTask = nil } }
            do {
                if let browser, !(await browser.confirmDiscardingEdits()) {
                    if scoped { url.stopAccessingSecurityScopedResource() }
                    return
                }
                try await waitForCloudDownload(url)
                // Files in another app's private storage (WeChat, Mail…) that macOS won't let Stow
                // read get plain words and a way to a readable copy, not "permission denied".
                guard OtherAppFiles.canRead(url) else {
                    if scoped { url.stopAccessingSecurityScopedResource() }
                    openFailure = OpenFailure(failure: OtherAppFiles.unreadable(url), url: url)
                    return
                }
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
                if Task.isCancelled { throw EngineError(.cancelled) }
                archive.source?.password = password
                releaseScope()
                scopedURL = scoped ? url : nil
                // Files received from a drag (Mail, chat apps) live in a folder Stow empties at launch.
                if !OtherAppFiles.isReceived(url) { recents.add(url) }
                if browser?.isListing == true { browser?.applyListing(archive, complete: true) }
                else {
                    browser?.quickLook.close()
                    browser = makeBrowser(archive)
                }
                browser?.verifyDiskImage()
            } catch {
                let error = error is CancellationError ? EngineError(.cancelled) : EngineError(error)
                if openingID == id, browser?.isListing == true { browser = nil }
                if scoped { url.stopAccessingSecurityScopedResource() }
                if openingID == id, error.failure != .cancelled {
                    var failure = Failure(error, .open, name: url.lastPathComponent)
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
    func pack(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        Task {
            let request = await PackRequest.gather(urls)
            guard !request.files.isEmpty else { return }
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

    /// New Archive (⌘N): pick what to pack.
    func chooseFilesToPack() {
        Task { pack(await PackDestination.chooseSources()) }
    }

    /// URLs macOS opened Stow with. Archives open in the browser (the first one; Stow has one window).
    func receive(_ urls: [URL]) {
        for url in urls where Handoff.isHandoff(url) {
            system.receive(url)
        }
        if let archive = urls.first(where: \.isFileURL) {
            NSApp.activate()
            if SettingsKeys.flag(SettingsKeys.openInGlance) {
                glance.open(archive)
                return
            }
            showMainWindow()
            open(archive)
        }
    }

    /// File › Open Recent and the welcome window's Recent list.
    func openRecent(_ entry: RecentArchives.Entry) {
        guard let url = recents.url(for: entry) else { return }
        showMainWindow()
        open(url)
    }

    /// Sample data for design review and the "Try the Sample" button.
    func openArchive(named name: String) {
        cancelOpening()
        releaseScope()
        browser = makeBrowser(SampleArchive.make(named: name))
    }

    private func makeBrowser(_ archive: Archive, isListing: Bool = false) -> BrowserModel {
        let model = BrowserModel(archive: archive, isListing: isListing)
        model.passwords = PasswordHook(prompt: passwords)
        model.onArchiveGone = { [weak self] in self?.closeArchive() }
        model.onCloseWindow = { [weak self] in self?.closeWindow() }
        // The Pack sentence is a sheet on the full window, so Glance hands over to it first.
        model.onPack = { [weak self] request in
            self?.glance.expand(byKeyboard: false)
            self?.packRequest = request
        }
        return model
    }

    /// "Close the window after Extract All or an install": the archive closes with it.
    func closeWindow() {
        cancelOpening()
        glance.close()
        NSApp.windows.first { !($0 is NSPanel) && $0.isVisible && $0.sheetParent == nil }?.performClose(nil)
    }

    /// Extracts several archives, one after another, into a folder chosen once.
    func extractArchives(_ urls: [URL]) {
        Task {
            guard let destination = await ExtractDestination.choose(count: urls.count, near: urls.first) else { return }
            batch.enqueue(urls, into: destination)
        }
    }

    func closeArchive() {
        Task {
            guard await browser?.confirmDiscardingEdits() ?? true else { return }
            cancelOpening()
            releaseScope()
            browser = nil
        }
    }

    private func releaseScope() {
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
    @State private var app = AppState()
    @AppStorage(SettingsKeys.appearance) private var appearance = "system"

    var body: some Scene {
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
        .defaultLaunchBehavior(.presented)
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
        Settings {
            SettingsView().environment(app)
        }
        .windowResizability(.contentSize)
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
                // For the moment it takes the welcome to come back.
                Color.clear
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
            app.cancelOpening()
        }
        .modifier(AppRoot(host: .browser))
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
    @MainActor private static var launched = false

    private var isHost: Bool { (host == .welcome) == (app.browser == nil) }

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
            .passwordSheet(app.passwords, isActive: isHost)
            .fileImporter(isPresented: isHost ? $app.isChoosingArchive : .constant(false),
                          allowedContentTypes: [.archive, .diskImage, .data]) { result in
                if case .success(let url) = result { app.open(url) }
            }
            .sheet(item: isHost ? $app.openFailure : .constant(nil)) { open in
                FailureCard(failure: open.failure) { action in
                    app.openFailure = nil
                    if let action, let url = open.url { app.follow(action, opening: url) }
                }
            }
            .cloudDownloadSheet(app, isActive: isHost && !app.glance.isShown)
            .overlay(alignment: .bottomTrailing) { if isHost { BatchStack(queue: app.batch) } }
            .onChange(of: app.browser == nil, initial: true) { _, noArchive in handOver(noArchive: noArchive) }
            .task {
                SettingsRouter.shared.open = { openSettings() }
                OnboardingRouter.shared.open = { openWindow(id: "onboarding") }
                guard !Self.launched else { return }
                Self.launched = true
                DemoScene.apply(to: app)
                guard !OnboardingRouter.shared.didCheckAutomaticPresentation else { return }
                OnboardingRouter.shared.didCheckAutomaticPresentation = true
                // Let the window appear before presenting the first-run checklist.
                await Task.yield()
                if Onboarding.shouldShowAutomatically() {
                    openWindow(id: "onboarding")
                }
            }
            // "Show the main window": the Browser with an archive open, the welcome without one.
            .onAppear(perform: routeShowMainWindow)
    }

    private func routeShowMainWindow() {
        let open = openWindow
        app.showMainWindow = { [weak app] in open(id: app?.browser == nil ? "welcome" : "main") }
    }

    /// An archive opened in the welcome, or the Browser's archive closed: the other window takes
    /// over. Glance showing the archive keeps the Browser away. A key press switches them without
    /// window animation (DESIGN.md › Motion).
    private func handOver(noArchive: Bool) {
        let leaving: String, arriving: String?
        switch host {
        case .welcome where !noArchive: (leaving, arriving) = ("welcome", app.glance.isShown ? nil : "main")
        case .browser where noArchive: (leaving, arriving) = ("main", "welcome")
        default: return
        }
        WindowSwitch.animation = Motion.byKeyboard ? .none : .default
        for window in GlanceController.mainWindows { window.animationBehavior = WindowSwitch.animation }
        if let arriving { openWindow(id: arriving) }
        dismissWindow(id: leaving)
    }
}

/// How the welcome comes up after a switch; the Browser's own opening is Glance's (`prepareMainWindow`).
@MainActor enum WindowSwitch {
    static var animation = NSWindow.AnimationBehavior.default
}

/// The pack capsule while packing: under the welcome, or over the Browser above its Next Steps.
struct PackActivityAccessory: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            Button("New Archive…") { app.chooseFilesToPack() }
                .keyboardShortcut("n")
            Button("Open Archive…") { app.isChoosingArchive = true }
                .keyboardShortcut("o")
            // Read here, in the Commands body: a nested view's reads don't refresh the menu.
            OpenRecentMenu(entries: app.recents.visible, open: { app.openRecent($0) }, clear: { app.recents.clear() })
            Button("Extract Archives…") { app.isChoosingBatch = true }
                .keyboardShortcut("e", modifiers: [.command, .option])
            Button("Open Sample Archive") { app.openArchive(named: SampleArchive.make().name) }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Divider()
            Button("Close Archive") { app.closeArchive() }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(app.browser == nil)
        }
        CommandGroup(after: .help) {
            Button("Welcome to Stow") { OnboardingRouter.shared.open() }
        }
        CommandGroup(after: .windowArrangement) {
            Button(app.tray.isShown ? String(localized: "Hide Tray") : String(localized: "Show Tray")) { app.tray.toggle() }
                .keyboardShortcut("t", modifiers: [.command, .option])
        }
    }
}
