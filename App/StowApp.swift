import SwiftUI
import UniformTypeIdentifiers

@Observable
final class AppState {
    struct OpenFailure: Identifiable {
        let id = UUID()
        let name: String
        let message: String
    }

    let tray = TrayController()
    let packing = PackController()
    let system = SystemActions()
    var browser: BrowserModel?
    var packRequest: PackRequest?
    var isChoosingArchive = false
    private(set) var isOpening = false
    var openFailure: OpenFailure?

    /// The open archive's security scope (Open panel URLs need it claimed; dropped URLs don't).
    private var scopedURL: URL?

    /// Brings back the main window (it may have been closed while Stow kept running).
    var showMainWindow: () -> Void = {}

    init() {
        tray.app = self
        system.app = self
    }

    /// Lists a real archive through the engine and shows it in the browser.
    func open(_ url: URL) {
        guard !isOpening else { return }
        isOpening = true
        let scoped = url.startAccessingSecurityScopedResource()
        Task {
            defer { isOpening = false }
            do {
                let listing = try await ArchiveEngine.shared.list(url)
                let archive = await Self.makeArchive(listing, url: url)
                releaseScope()
                scopedURL = scoped ? url : nil
                browser = BrowserModel(archive: archive)
            } catch {
                if scoped { url.stopAccessingSecurityScopedResource() }
                openFailure = OpenFailure(name: url.lastPathComponent, message: EngineError(error).message)
            }
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
            showMainWindow()
            open(archive)
        }
    }

    /// Sample data for design review and the "Try the Sample" button.
    func openArchive(named name: String) {
        releaseScope()
        browser = BrowserModel(archive: SampleArchive.make(named: name))
    }

    func closeArchive() {
        releaseScope()
        browser = nil
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

    var body: some Scene {
        Window("Stow", id: "main") {
            RootView()
                .environment(app)
                .onAppear { delegate.app = app }
        }
        .defaultSize(width: 1120, height: 700)
        .windowToolbarStyle(.unified)
        .commands { StowCommands(app: app) }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openWindow) private var openWindow

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
        .fileImporter(isPresented: $app.isChoosingArchive, allowedContentTypes: [.archive, .diskImage, .data]) { result in
            if case .success(let url) = result { app.open(url) }
        }
        .alert("Couldn’t open “\(app.openFailure?.name ?? "")”", isPresented: Binding(
            get: { app.openFailure != nil }, set: { if !$0 { app.openFailure = nil } }
        ), presenting: app.openFailure) { _ in
            Button("OK") {}
        } message: { failure in
            Text(failure.message)
        }
        .task { DemoScene.apply(to: app) }
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
            Button("Open Sample Archive") { app.openArchive(named: SampleArchive.make().name) }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Divider()
            Button("Close Archive") { app.closeArchive() }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(app.browser == nil)
        }
        CommandGroup(before: .toolbar) {
            Button("as Icons") { app.browser?.viewMode = .grid }
                .keyboardShortcut("1")
            Button("as List") { app.browser?.viewMode = .list }
                .keyboardShortcut("2")
            Divider()
        }
        CommandGroup(after: .windowArrangement) {
            Button(app.tray.isShown ? "Hide Tray" : "Show Tray") { app.tray.toggle() }
                .keyboardShortcut("t", modifiers: [.command, .option])
        }
    }
}
