import SwiftUI
import UniformTypeIdentifiers

@Observable
final class AppState {
    struct OpenFailure: Identifiable {
        let id = UUID()
        let name: String
        let message: String
        /// Disk images Stow can't read (encrypted, unusual formats) can still be opened by macOS.
        var canOpenInFinder = false
        var url: URL?
    }

    let tray = TrayController()
    var browser: BrowserModel?
    var packRequest: PackRequest?
    var isChoosingArchive = false
    var isChoosingBatch = false
    private(set) var isOpening = false
    var openFailure: OpenFailure?

    /// The open archive's security scope (Open panel URLs need it claimed; dropped URLs don't).
    private var scopedURL: URL?

    let batch = BatchQueue()

    init() {
        tray.app = self
        // Copies opened in a default app last time.
        TemporaryOpen.removeAll()
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
                try await DownloadCheck.waitUntilComplete(url)
                let listing: ArchiveListing
                do {
                    listing = try await ArchiveEngine.shared.list(url)
                } catch {
                    throw DiskImageCheck.explain(EngineError(error), for: url)
                }
                let archive = await Self.makeArchive(listing, url: url)
                releaseScope()
                scopedURL = scoped ? url : nil
                browser = makeBrowser(archive)
            } catch {
                if scoped { url.stopAccessingSecurityScopedResource() }
                openFailure = OpenFailure(name: url.lastPathComponent, message: EngineError(error).message,
                                          canOpenInFinder: DiskImageCheck.isDiskImage(url), url: url)
            }
        }
    }

    /// Sample data for design review and the "Try the Sample" button.
    func openArchive(named name: String) {
        releaseScope()
        browser = makeBrowser(SampleArchive.make(named: name))
    }

    private func makeBrowser(_ archive: Archive) -> BrowserModel {
        let model = BrowserModel(archive: archive)
        model.onArchiveGone = { [weak self] in self?.closeArchive() }
        model.onCloseWindow = { [weak self] in self?.closeWindow() }
        return model
    }

    /// "Close the window after Extract All or an install": the archive closes with it.
    func closeWindow() {
        closeArchive()
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
        // A second importer on the same view would be ignored, so this one sits on a background.
        .background {
            Color.clear.fileImporter(isPresented: $app.isChoosingBatch, allowedContentTypes: [.archive, .diskImage, .data],
                                     allowsMultipleSelection: true) { result in
                if case .success(let urls) = result, !urls.isEmpty { app.extractArchives(urls) }
            }
        }
        .fileImporter(isPresented: $app.isChoosingArchive, allowedContentTypes: [.archive, .diskImage, .data]) { result in
            if case .success(let url) = result { app.open(url) }
        }
        .alert("Couldn’t open “\(app.openFailure?.name ?? "")”", isPresented: Binding(
            get: { app.openFailure != nil }, set: { if !$0 { app.openFailure = nil } }
        ), presenting: app.openFailure) { failure in
            if failure.canOpenInFinder, let url = failure.url {
                Button("Open in Finder") { NSWorkspace.shared.open(url) }
            }
            Button("OK") {}
        } message: { failure in
            Text(failure.message)
        }
        .overlay(alignment: .bottomTrailing) { BatchStack(queue: app.batch) }
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
            Button("Extract Archives…") { app.isChoosingBatch = true }
                .keyboardShortcut("e", modifiers: [.command, .option])
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
