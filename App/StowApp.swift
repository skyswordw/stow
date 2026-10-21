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
    var openFailure: OpenFailure?

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

    /// Lists a real archive through the engine and shows it in the browser.
    func open(_ url: URL) {
        guard !isOpening else { return }
        isOpening = true
        let scoped = url.startAccessingSecurityScopedResource()
        Task {
            defer { isOpening = false }
            do {
                if let browser, !(await browser.confirmDiscardingEdits()) {
                    if scoped { url.stopAccessingSecurityScopedResource() }
                    return
                }
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
                    (listing, password) = try await passwords.retrying(url.lastPathComponent, for: .open) { password in
                        try await ArchiveEngine.shared.list(url, password: password)
                    }
                } catch {
                    throw DiskImageCheck.explain(EngineError(error), for: url)
                }
                var archive = await Self.makeArchive(listing, url: url)
                archive.source?.password = password
                releaseScope()
                scopedURL = scoped ? url : nil
                // Files received from a drag (Mail, chat apps) live in a folder Stow empties at launch.
                if !OtherAppFiles.isReceived(url) { recents.add(url) }
                browser = makeBrowser(archive)
                browser?.verifyDiskImage()
            } catch {
                let error = EngineError(error)
                if scoped { url.stopAccessingSecurityScopedResource() }
                if error.failure != .cancelled {
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
        guard model.archive.source != nil else { return }
        Task {
            do {
                let archive = model.archive
                let (staged, password) = try await model.passwords.retrying(archive.name, for: .extract, known: model.level.password) { password in
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
        releaseScope()
        browser = makeBrowser(SampleArchive.make(named: name))
    }

    private func makeBrowser(_ archive: Archive) -> BrowserModel {
        let model = BrowserModel(archive: archive)
        model.passwords = PasswordHook(prompt: passwords)
        model.onArchiveGone = { [weak self] in self?.closeArchive() }
        model.onCloseWindow = { [weak self] in self?.closeWindow() }
        return model
    }

    /// "Close the window after Extract All or an install": the archive closes with it.
    func closeWindow() {
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
        Window("Stow", id: "main") {
            RootView()
                .environment(app)
                .onAppear { delegate.app = app; SettingsAppearance.apply() }
                .onChange(of: appearance) { SettingsAppearance.apply() }
        }
        .defaultSize(width: 1120, height: 700)
        .windowToolbarStyle(.unified)
        .commands {
            StowCommands(app: app)
            BrowseCommands(app: app)
            GlanceCommands(app: app)
        }
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

struct RootView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var app = app
        Group {
            if let browser = app.browser {
                BrowserView(model: browser)
                    .overlay(alignment: .bottom) { packActivity }
            } else {
                // Below the welcome content rather than over the Recent row.
                WelcomeView()
                    .navigationTitle("Stow")
                    .safeAreaInset(edge: .bottom, spacing: 0) { packActivity }
            }
        }
        .sheet(item: $app.packRequest) { PackSheet(request: $0).environment(app) }
        // A second importer on the same view would be ignored, so this one sits on a background.
        .background {
            Color.clear.fileImporter(isPresented: $app.isChoosingBatch, allowedContentTypes: [.archive, .diskImage, .data],
                                     allowsMultipleSelection: true) { result in
                if case .success(let urls) = result, !urls.isEmpty { app.extractArchives(urls) }
            }
        }
        .passwordSheet(app.passwords)
        .fileImporter(isPresented: $app.isChoosingArchive, allowedContentTypes: [.archive, .diskImage, .data]) { result in
            if case .success(let url) = result { app.open(url) }
        }
        .sheet(item: $app.openFailure) { open in
            FailureCard(failure: open.failure) { action in
                app.openFailure = nil
                if let action, let url = open.url { app.follow(action, opening: url) }
            }
        }
        .overlay(alignment: .bottomTrailing) { BatchStack(queue: app.batch) }
        .task {
            SettingsRouter.shared.open = { openSettings() }
            OnboardingRouter.shared.open = { openWindow(id: "onboarding") }
            DemoScene.apply(to: app)
            guard !OnboardingRouter.shared.didCheckAutomaticPresentation else { return }
            OnboardingRouter.shared.didCheckAutomaticPresentation = true
            // Let the main window appear before presenting the first-run checklist.
            await Task.yield()
            if Onboarding.shouldShowAutomatically() {
                openWindow(id: "onboarding")
            }
        }
        .onAppear { app.showMainWindow = { [openWindow] in openWindow(id: "main") } }
    }

    /// Sits above the browser's Next Steps when both are showing.
    private var packActivity: some View {
        let nextSteps = app.browser.map { !$0.selection.isEmpty || $0.activity != nil } ?? false
        return ZStack {
            if app.packing.activity != nil {
                PackActivityBar(packing: app.packing)
                    .transition(.rise(reduceMotion: reduceMotion))
            }
        }
        .padding(.bottom, app.packing.activity == nil ? 0 : nextSteps ? 76 : Space.l)
        .animation(Motion.resolved(Motion.appear, reduceMotion: reduceMotion), value: app.packing.activity == nil)
    }
}

struct StowCommands: Commands {
    let app: AppState

    var body: some Commands {
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
