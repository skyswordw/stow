import SwiftUI

@Observable
final class AppState {
    let tray = TrayController()
    var browser: BrowserModel?
    var packRequest: PackRequest?

    init() {
        tray.app = self
    }

    func openArchive(named name: String) {
        browser = BrowserModel(archive: SampleArchive.make(named: name))
    }

    func closeArchive() {
        browser = nil
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
                WelcomeView { app.openArchive(named: $0) }
                    .navigationTitle("Stow")
            }
        }
        .sheet(item: $app.packRequest) { PackSheet(request: $0) }
        .task { DemoScene.apply(to: app) }
    }
}

struct StowCommands: Commands {
    let app: AppState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Archive…") { app.packRequest = PackRequest(files: SampleArchive.packCandidates) }
                .keyboardShortcut("n")
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
