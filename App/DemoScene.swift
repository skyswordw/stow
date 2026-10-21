import AppKit
import SwiftUI

/// Launch-argument hooks for design review and screenshots:
///
///     Stow.app/Contents/MacOS/Stow -StowScene grid -StowSnapshot YES
///
/// Scenes: welcome, grid, list, fonts, search, activity, pack, tray, open (`-StowOpen <path>`),
/// packing / packed (the pack capsule), packrun (a real pack, see `runPack`).
/// `pack` with `-StowPack <path>` shows the sentence for real files; `-PackAudience mac` and the other
/// `PackPreferences` keys work as launch arguments too.
/// quicklook (the Finder preview; `-StowPreview encrypted|slow`, or `-StowOpen <path>` for a real file),
/// associations (Settings › File Types), integration (Settings › Integration; `-StowRepair YES`
/// runs Repair for real).
/// `-StowScene associations -StowAssociationsCheck <UTI>` makes Stow the real default for one
/// type, switches it back, prints both reports and quits — a live check of Launch Services.
/// settings (`-StowSettingsPane packing` selects a pane in the real Settings window),
/// password (the sheet after a rejected password), extract-options, install-options, batch, conflict, signature-warning, replace-app.
/// With `open`, `-StowRun extractAll|install|fonts|installer` runs that step once the archive is up
/// (`-StowInstallFolder <path>` installs into a scratch folder instead of /Applications).
/// `-StowWindowSize 900x560` resizes the main window first (compact marketing crops).
/// With -StowSnapshot, each visible window is rendered to a PNG in the sandbox's temporary
/// directory and its path printed to stdout, so no Screen Recording permission is needed.
enum DemoScene {
    static func apply(to app: AppState) {
        let defaults = UserDefaults.standard
        guard let scene = defaults.string(forKey: "StowScene") else { return }
        switch defaults.string(forKey: "StowAppearance") {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }

        switch scene {
        case "settings":
            SettingsRouter.shared.pane = defaults.string(forKey: "StowSettingsPane").flatMap(SettingsPane.init(rawValue:)) ?? .general
            SettingsRouter.shared.open()
        case "grid":
            app.openArchive(named: SampleArchive.make().name)
            app.browser?.folder = "Photos"
            app.browser?.selection = ["Photos/Lighthouse.jpg", "Photos/Pier at Dawn.jpg"]
        case "list":
            app.openArchive(named: SampleArchive.make().name)
            app.browser?.viewMode = .list
            app.browser?.folder = "Specs"
            app.browser?.selection = ["Specs/Brand Guidelines.pdf"]
        case "fonts":
            app.openArchive(named: SampleArchive.make().name)
            app.browser?.folder = "Fonts"
            app.browser?.selection = Set(app.browser?.visibleEntries.map(\.id) ?? [])
        case "search":
            app.openArchive(named: SampleArchive.make().name)
            app.browser?.query = "harbor"
        case "activity":
            app.openArchive(named: SampleArchive.make().name)
            app.browser?.folder = "Prototype"
            app.browser?.selection = ["Prototype/Harbor Prototype.app"]
            app.browser?.run(.moveToApplications)
        case "pack":
            if let path = defaults.string(forKey: "StowPack") {
                app.pack([URL(filePath: path)])
            } else {
                app.packRequest = PackRequest(files: SampleArchive.packCandidates)
            }
        case "packing":
            app.packing.preview(name: "Harbor Handoff.zip", phase: .running(0.42))
        case "packed":
            app.packing.preview(name: "Harbor Handoff.zip", phase: .done, verified: true)
        case "packrun":
            runPack(defaults)
            return
        case "password":
            // The question after a rejected password; nothing is checked against an archive.
            Task { _ = await app.passwords.ask(.init(archiveName: "Harbor Handoff.7z", purpose: .extract, isRetry: true)) }
        case "open":
            // A real archive through the engine: -StowScene open -StowOpen <path inside the sandbox>
            if let path = defaults.string(forKey: "StowOpen") { app.open(URL(filePath: path)) }
            if let step = defaults.string(forKey: "StowRun") {
                Task {
                    while app.browser == nil { try? await Task.sleep(for: .milliseconds(100)) }
                    try? await Task.sleep(for: .milliseconds(400))
                    run(step, in: app)
                }
            }
        case "extract-options":
            showOptions(ExtractionOptionsView(), title: String(localized: "Extraction"))
        case "install-options":
            showOptions(InstallOptionsView(), title: String(localized: "Installing"))
        case "batch":
            app.openArchive(named: SampleArchive.make().name)
            app.browser?.showInspector = false
            app.batch.preview([
                ("Field Recordings.7z", .done), ("server-logs.tar.xz", .running(0.62)),
                ("Brand Kit.zip", .waiting), ("Old Backup.rar", .failed(String(localized: "This archive needs a password."))),
                ("Fonts 2026.zip", .waiting),
            ])
        case "conflict", "conflict-folder":
            app.openArchive(named: SampleArchive.make().name)
            let base = FileManager.default.temporaryDirectory
            let isFolder = scene == "conflict-folder"
            let name = isFolder ? "Harbor Rebrand Handoff" : "Brand Guidelines.pdf"
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                _ = await Prompts.resolve(Placement.Conflict(name: name, existing: base.appending(path: name),
                                                             incoming: base.appending(path: name), canMerge: isFolder))
            }
        case "signature-warning", "replace-app":
            app.openArchive(named: SampleArchive.make().name)
            app.browser?.folder = "Prototype"
            app.browser?.selection = ["Prototype/Harbor Prototype.app"]
            let question: Installer.Question = scene == "replace-app"
                ? .replaceApp(app: "Harbor Prototype.app", installed: "1.2", incoming: "1.3")
                : .signature(app: "Harbor Prototype.app", verdict: .notNotarized(signer: "Harbor Studio"))
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                _ = await Prompts.ask(question)
            }
        case "quicklook":
            showQuickLook(defaults)
        case "associations":
            let model = Associations()
            if let uti = defaults.string(forKey: "StowAssociationsCheck") {
                checkAssociations(model, uti: uti)
                return
            }
            model.selection = ["public.zip-archive", "org.7-zip.7-zip-archive", "com.rarlab.rar-archive"]
            showSettingsPane(AssociationsView(model: model), title: String(localized: "File Types"), size: CGSize(width: 560, height: 640))
        case "integration":
            showSettingsPane(IntegrationView(), title: String(localized: "Integration"), size: CGSize(width: 560, height: 640))
            if defaults.bool(forKey: "StowRepair") { Task { await IntegrationSettings.shared.repairFinderExtension() } }
        case "tray":
            app.tray.items = [
                TrayItem(name: "Invoice October.pdf", size: 182_000),
                TrayItem(name: "Pier at Dawn.jpg", size: 4_210_000),
                TrayItem(name: "Kickoff.key", size: 18_900_000),
                TrayItem(name: "budget-2027.numbers", size: 412_000),
            ]
            app.tray.show()
        default:
            break
        }

        if scene == "open" { BrowseDemo.apply(to: app) }

        if defaults.object(forKey: "StowInspector") != nil {
            app.browser?.showInspector = defaults.bool(forKey: "StowInspector")
        }

        if let size = defaults.string(forKey: "StowWindowSize")?.split(separator: "x").compactMap({ Double($0) }),
           size.count == 2 {
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                let targetWindow = scene == "settings" ? NSApp.keyWindow
                    : NSApp.windows.first(where: { !($0 is NSPanel) && $0.isVisible })
                guard let window = targetWindow else { return }
                window.setContentSize(CGSize(width: size[0], height: size[1]))
            }
        }

        if defaults.bool(forKey: "StowSnapshot") {
            Task {
                let delay = defaults.double(forKey: "StowSnapshotDelay")
                try? await Task.sleep(for: .seconds(delay > 0 ? delay : 1.6))
                for (index, window) in NSApp.windows.filter(\.isVisible).enumerated() {
                    let kind = window.sheetParent != nil ? "sheet" : window is NSPanel ? "panel" : "window"
                    let name = index == 0 ? "\(scene)-\(kind)" : "\(scene)-\(kind)\(index)"
                    if let url = snapshot(window, name: name) { print(url.path) }
                }
                fflush(stdout)
                exit(0) // terminate(_:) waits on open sheets; this is a screenshot run.
            }
        }
    }

    /// Packs for real through the engine and prints where the archive went, then quits:
    ///
    ///     -StowScene packrun -StowPack <folder> -StowPackTo <folder> -PackAudience mac
    ///         [-StowFormat zip|sevenZip|tar|tarGz|tarBz2|tarXz] [-StowPassword pw] [-StowSplit bytes] [-PackVerify YES]
    ///
    /// Paths must be inside Stow's sandbox container.
    private static func runPack(_ defaults: UserDefaults) {
        guard let source = defaults.string(forKey: "StowPack"), let target = defaults.string(forKey: "StowPackTo") else {
            print("packrun needs -StowPack and -StowPackTo")
            exit(2)
        }
        Task {
            let request = await PackRequest.gather([URL(filePath: source)])
            var options = PackOptions()
            options.setAudience(PackPreferences.audience)
            if let format = defaults.string(forKey: "StowFormat").flatMap(PackFormat.init(rawValue:)) {
                options.setFormat(format)
            }
            let password = defaults.string(forKey: "StowPassword")
            options.usesPassword = password != nil && options.format.supportsPassword
            options.level = PackPreferences.level(for: options.audience)
            let split = Int64(defaults.integer(forKey: "StowSplit"))
            let report = Compatibility.report(for: request.files, options: options, password: password ?? "")
            let name = Compatibility.archiveName(request.suggestedName, for: options.audience)
            let keepsMetadata = options.audience.keepsMacMetadata && options.format == .zip
            let create = CreateRequest(operationID: UUID().uuidString, archiveName: name, format: options.format,
                                       level: options.level, password: options.usesPassword ? password : nil,
                                       volumeSize: split > 0 ? split : nil, keepsMacMetadata: keepsMetadata,
                                       verify: PackPreferences.verify, threads: PackPreferences.threads)
            do {
                let result = try await ArchiveCreation.run(report.items, totalBytes: report.totalBytes,
                                                           attributes: keepsMetadata, request: create, named: name,
                                                           in: URL(filePath: target)) { _ in }
                result.placed.forEach { print($0.path) }
                print("renamed \(report.renames.count), left out \(report.excluded.count + report.leftOutLinks.count), verified \(result.report.verified)")
                fflush(stdout)
                exit(0)
            } catch {
                print("failed: \(EngineError(error).message)")
                fflush(stdout)
                exit(1)
            }
        }
    }

    /// The Quick Look extension's view in a window the size Finder gives it.
    private static func showQuickLook(_ defaults: UserDefaults) {
        let sample = SampleArchive.make()
        let fallback = { (reason: ArchivePreviewFallback.Reason) in
            ArchivePreviewContent.fallback(ArchivePreviewFallback(name: "Quarterly Backup.7z", format: .sevenZip,
                                                                  size: 2_480_000_000, reason: reason))
        }
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 640, height: 480),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = String(localized: "Quick Look")
        window.isReleasedWhenClosed = false
        func show(_ content: ArchivePreviewContent) {
            window.contentView = NSHostingView(rootView: ArchivePreview(content: content, openInStow: {}))
            window.center()
            window.makeKeyAndOrderFront(nil)
        }
        switch defaults.string(forKey: "StowPreview") {
        case "encrypted": show(fallback(.encrypted))
        case "slow": show(fallback(.tooSlow))
        default:
            if let path = defaults.string(forKey: "StowOpen") {
                Task { show(await ArchivePreviewLoader.load(URL(filePath: path)) { try await ArchiveEngine.shared.list($0) }) }
            } else {
                show(.listed(ArchivePreviewModel(archive: sample)))
            }
        }
        quickLookWindow = window
    }

    private static var quickLookWindow: NSWindow?

    private static func showSettingsPane(_ view: some View, title: String, size: CGSize) {
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.makeKeyAndOrderFront(nil)
        quickLookWindow = window
    }

    private static func checkAssociations(_ model: Associations, uti: String) {
        Task {
            @MainActor func line(_ label: String) {
                let row = model.rows.first { $0.id == uti }
                print("\(label): \(model.name(of: row?.app)) (Stow: \(row?.opensWithStow ?? false), previous: \(row?.previous ?? "-"))")
            }
            line("before")
            model.selection = [uti]
            await model.makeStowDefault()
            print("make default → \(model.report?.summary ?? "?") \(model.report?.failed ?? [:])")
            line("after")
            await model.restorePrevious()
            print("switch back → \(model.report?.summary ?? "?") \(model.report?.failed ?? [:])")
            line("restored")
            fflush(stdout)
            exit(0)
        }
    }
    private static func run(_ step: String, in app: AppState) {
        guard let browser = app.browser else { return }
        switch step {
        case "extractAll": browser.extractAll()
        case "install": browser.run(.moveToApplications)
        case "fonts": browser.run(.installFonts(count: browser.selectedEntries.count), on: browser.archive.files.filter { $0.kind == .font })
        case "installer": browser.run(.openInstaller)
        default: break
        }
    }

    /// Option views get a plain window until the Settings window exists.
    private static func showOptions(_ view: some View, title: String) {
        let window = NSWindow(contentViewController: NSHostingController(rootView: view.frame(width: 520)))
        window.title = title
        window.styleMask = [.titled, .closable]
        window.setContentSize(window.contentView?.fittingSize ?? CGSize(width: 520, height: 420))
        window.center()
        window.makeKeyAndOrderFront(nil)
        retained = window
    }

    private static var retained: NSWindow?

    /// Captures the window as the window server composited it — glass, shadows and all.
    /// `CGWindowListCreateImage` is hidden from the SDK but still exported; an app may
    /// capture its own windows without Screen Recording permission.
    private static func snapshot(_ window: NSWindow, name: String) -> URL? {
        // A locked screen isn't composited; draw the view tree instead (`-StowSnapshotMode view`).
        if UserDefaults.standard.string(forKey: "StowSnapshotMode") == "view",
           let view = window.contentView?.superview ?? window.contentView,
           let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let data = rep.representation(using: .png, properties: [:]) else { return nil }
            let url = FileManager.default.temporaryDirectory.appending(path: "\(name).png")
            return (try? data.write(to: url)) != nil ? url : nil
        }
        typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY),
              let symbol = dlsym(handle, "CGWindowListCreateImage") else { return nil }
        let create = unsafeBitCast(symbol, to: CreateImage.self)
        let optionIncludingWindow: UInt32 = 1 << 3
        let imageBestResolution: UInt32 = 1 << 3
        guard let image = create(.null, optionIncludingWindow, UInt32(window.windowNumber), imageBestResolution)?
            .takeRetainedValue() else { return nil }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { return nil }
        let url = FileManager.default.temporaryDirectory.appending(path: "\(name).png")
        return (try? data.write(to: url)) != nil ? url : nil
    }
}
