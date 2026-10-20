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
    var browser: BrowserModel?
    var packRequest: PackRequest?
    var isChoosingArchive = false
    private(set) var isOpening = false
    var openFailure: OpenFailure?

    /// The open archive's security scope (Open panel URLs need it claimed; dropped URLs don't).
    private var scopedURL: URL?

    init() {
        tray.app = self
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
    @State private var app = AppState()

    var body: some Scene {
        Window("Stow", id: "main") {
            RootView()
                .environment(app)
        }
        .defaultSize(width: 1120, height: 700)
        .windowToolbarStyle(.unified)
        .commands { StowCommands(app: app) }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        Group {
            if let browser = app.browser {
                BrowserView(model: browser)
            } else {
                WelcomeView()
                    .navigationTitle("Stow")
            }
        }
        .sheet(item: $app.packRequest) { PackSheet(request: $0) }
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
    }
}

struct StowCommands: Commands {
    let app: AppState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Archive…") { app.packRequest = PackRequest(files: SampleArchive.packCandidates) }
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
