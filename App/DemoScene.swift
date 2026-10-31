import AppKit
import SwiftUI

/// Launch-argument hooks for design review and screenshots:
///
///     Stow.app/Contents/MacOS/Stow -StowScene grid -StowSnapshot YES
///
/// Scenes: onboarding, welcome (no history), recents (the welcome window with history),
/// grid, list, fonts, search, search-nested (results inside an inner archive; search-nested-many selects two), activity, pack, tray, open (`-StowOpen <path>`),
/// packing / packed (the pack capsule), packrun (a real pack, see `runPack`).
/// `pack` with `-StowPack <path>` shows the sentence for real files; `-PackAudience mac` and the other
/// `PackPreferences` keys work as launch arguments too; `-StowPackPassword YES` starts with “with a password”;
/// `-StowPackPasswordReview mismatch|shown` fills in a sample password (`pack-password` shows the mismatch);
/// `-StowPackFormat sevenZip` starts with that format, `-StowPackMore YES` opens More Options alone,
/// `-StowPackChanged YES` changes two choices from the purpose, `-StowPackSplitEditor sentence|options`
/// opens the part-size editor.
/// quicklook (the Finder preview; `-StowPreview encrypted|slow`, or `-StowOpen <path>` for a real file),
/// associations (Settings › File Types), integration (Settings › Integration; `-StowRepair YES`
/// runs Repair for real).
/// `-StowScene associations -StowAssociationsCheck <UTI>` makes Stow the real default for one
/// type, switches it back, prints both reports and quits — a live check of Launch Services.
/// settings (`-StowSettingsPane packing` selects a pane in the real Settings window),
/// password (the sheet after a rejected password; `-StowPasswordPurpose unlock|open|extract`, `-StowPasswordRetry NO`),
/// encrypted (the sample marked encrypted; `-StowLock checking|available`, or `-StowEncrypted YES` on any scene), extract-options, install-options, batch, conflict, signature-warning, replace-app,
/// install-running (an app part-way into Applications), install-app-open (refused: the installed copy is open, INS-181),
/// tray-files (real files on disk, for their icons), tray-arrived (rows pointed out after a drop),
/// tray-collect (Collect into a Folder, items from one folder), tray-collect-mixed (from three: people choose where),
/// tray-collect-taken (a name that's taken), tray-collected (after a real collect: where it went).
/// Source access (#213): source-access (the recovery picker, folder mode), source-access-file ("Allow only this
/// archive" checked; `-StowSourcePath <file>` or `-StowSourceName <name>` for either), source-access-unsaved (the grant couldn't be saved).
/// Empty and error states: open-failed, open-damaged, open-unreadable, finder-failed, extract-damaged, extract-full, extract-denied, extract-retry,
/// pack-failed, pack-failed-dmg, empty-archive, empty-folder, search-empty, tray-empty.
/// Editing states: editing, editing-saving (Save part-way), editing-refused (an edit Stow can't make), external, readonly,
/// rename-archive (File › Rename Archive…), save-changes (closing with unsaved edits).
/// Tray states: tray-collect (naming the folder for Collect into a Folder), tray-failed (a failure told inside the Tray).
/// With `open`, `-StowRun extractAll|install|fonts|installer` runs that step once the archive is up
/// (`-StowInstallFolder <path>` installs into a scratch folder instead of /Applications).
/// glance (the compact window over the sample archive; `-StowGlanceEdge top|bottom|left|right|topLeft|…`
/// puts the pointer on that edge of the screen first, `-glance.pinned '<true/>'` pins it,
/// `-StowReduceTransparency YES` shows the solid fallback). With -StowSnapshot it also writes
/// glance-<edge>-screen.png: where on the screen it opened, the pointer marked.
/// Next Steps: next-steps (the capsule over two photos), next-steps-more (its More menu open, captured
/// as next-steps-more-menu.png with `-StowActivate YES`), next-steps-settings (Settings › Next Steps).
/// archive-app and glance-app: an archive that's one app with nothing selected, where Actions offers
/// Install App (fictional, so it only simulates).
/// `-nextSteps.hidden quickLook,extract` and `-nextSteps.shown NO` try other choices without saving them.
/// `-StowWindowSize 900x560` resizes the main window first (compact marketing crops).
/// `-StowViewMode grid|list|columns` switches the view; `-StowScrollToEnd YES` scrolls to the last item.
/// With -StowSnapshot, each visible window is rendered to a PNG in the sandbox's temporary
/// directory and its path printed to stdout, so no Screen Recording permission is needed.
/// `-StowLogLayout YES` also prints who has the keyboard and which toolbar items are showing.
enum DemoScene {
    static func apply(to app: AppState) {
        let defaults = UserDefaults.standard
        guard let scene = defaults.string(forKey: "StowScene") else { return }
        if scene == "a11y-contrast" { defaults.register(defaults: ["StowIncreaseContrast": true]) }
        if scene == "a11y-solid" { defaults.register(defaults: ["StowReduceTransparency": true]) }
        switch defaults.string(forKey: "StowAppearance") {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
        // The sample's "Harbor Prototype.app" gets a real-looking icon (Design/DemoAppIcon.svg), not the generic one.
        if let icon = NSImage(named: "DemoAppIcon")?.cgImage(forProposedRect: nil, context: nil, hints: nil) { NativeIcon.bitmaps["com.apple.application-bundle"] = icon }

        switch scene {
        case "onboarding":
            OnboardingRouter.shared.open()
        case "settings":
            SettingsRouter.shared.show(rawValue: defaults.string(forKey: "StowSettingsPane"))
        case "editing", "editing-saving", "editing-refused":
            BrowseDemo.editing(in: app)
            if scene == "editing-saving" { app.browser?.editSession.showSavingForDemo(progress: 0.42) }
            if scene == "editing-refused" { app.browser?.editSession.message = String(localized: "That name is already taken.") }
        case "rename-archive", "save-changes":
            // The prompts File › Rename Archive… and closing with unsaved edits show, on the editing scene.
            BrowseDemo.editing(in: app)
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                guard let model = app.browser else { return }
                let prompt: Prompt = scene == "rename-archive" ? .renameArchive(model.archive.name) : .saveChanges(model.archive.name)
                _ = await Prompts.present(prompt, on: model.editingWindow)
            }
        case "external":
            BrowseDemo.externalChange(in: app)
        case "checkup-format":
            // A 7Z named .zip with data after it, as Checkup words it; the popover opens by itself.
            let sample = SampleArchive.make()
            let scan = Checkup.FormatScan(name: sample.name, real: .sevenZip, realType: "7z", tailSize: 2_048)
            app.browser = BrowserModel(archive: Archive(name: sample.name, format: .sevenZip, files: sample.files,
                                                        checkup: scan.findings + sample.checkup.filter { $0.severity == .info }))
            CheckupToolbarButton.opensForDemo = true
        case "readonly":
            BrowseDemo.readOnly(in: app)
        case "archive-app":
            app.browser = oneAppArchive()
        case "next-steps", "next-steps-more":
            app.openArchive(named: SampleArchive.make().name)
            app.browser?.folder = defaults.string(forKey: "StowFolder") ?? "Photos"
            app.browser?.selection = Set(defaults.string(forKey: "StowSelect").map { [$0] }
                                         ?? ["Photos/Lighthouse.jpg", "Photos/Pier at Dawn.jpg"])
            if scene == "next-steps-more" {
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    NextStepsDemo.openMoreMenu()
                }
            }
        case "next-steps-settings":
            SettingsRouter.shared.show(.nextSteps)
        case "grid":
            app.openArchive(named: SampleArchive.make().name)
            app.browser?.folder = "Photos"
            app.browser?.selection = ["Photos/Lighthouse.jpg", "Photos/Pier at Dawn.jpg"]
        case "encrypted":
            var archive = SampleArchive.make()
            archive.isEncrypted = true
            archive.checkup = []
            app.browser = BrowserModel(archive: archive)
            app.browser?.folder = "Photos"
        case "list", "a11y-contrast", "a11y-solid":
            app.openArchive(named: SampleArchive.make().name)
            app.browser?.viewMode = .list
            app.browser?.folder = "Specs"
            app.browser?.selection = ["Specs/Brand Guidelines.pdf"]
        case "fonts":
            app.openArchive(named: SampleArchive.make().name)
            app.browser?.folder = "Fonts"
            app.browser?.selection = Set(app.browser?.visibleEntries.map(\.id) ?? [])
        case "search-nested", "search-nested-many":
            // Search reaching into Earlier Rounds/Old Explorations.7z; the sample can't extract,
            // so the inner listing is made up here. One result inside it is selected
            // (both with `search-nested-many`).
            app.openArchive(named: SampleArchive.make().name)
            app.browser?.viewMode = .list
            app.browser?.nestedLoader = { entry, _ in
                guard entry.name == "Old Explorations.7z" else { throw EngineError(.failed) }
                let date = Date(timeIntervalSince1970: 1_700_000_000)
                return [("Round 1/Wordmark Ideas.pdf", 2_400_000), ("Round 2/Wordmark Draft.svg", 31_000),
                        ("Round 2/Mark Sketches.png", 880_000), ("Notes.txt", 2_000)]
                    .map { ArchiveEntry(path: $0.0, isFolder: false, size: $0.1, packedSize: $0.1 / 2, modified: date) }
            }
            app.browser?.query = "wordmark"
            app.browser?.selection = ["Earlier Rounds/Old Explorations.7z/Round 2/Wordmark Draft.svg"]
            if scene == "search-nested-many" {
                app.browser?.selection.insert("Earlier Rounds/Old Explorations.7z/Round 1/Wordmark Ideas.pdf")
            }
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
                // -StowPackFormat sevenZip|dmg|tarGz|… starts with that format (and its purpose).
                var request = PackRequest(files: SampleArchive.packCandidates)
                request.initialFormat = defaults.string(forKey: "StowPackFormat").flatMap(PackFormat.init(rawValue:))
                app.packRequest = request
            }
        case "pack-zst":
            // TAR.ZST for Linux, both disclosures open (registered, so nothing is saved).
            UserDefaults.standard.register(defaults: ["StowPackDetails": true])
            var request = PackRequest(files: SampleArchive.packCandidates)
            request.initialFormat = .tarZst
            app.packRequest = request
        case "pack-password":
            // "With a password", the second entry typed wrong (#153). Registered, so nothing is saved.
            UserDefaults.standard.register(defaults: ["StowPackPassword": true, "StowPackPasswordReview": "mismatch"])
            app.packRequest = PackRequest(files: SampleArchive.packCandidates)
        case "pack-dmg":
            // A DMG for Macs: the split word is off (a disk image is one file).
            var request = PackRequest(files: SampleArchive.packCandidates)
            request.initialFormat = .dmg
            app.packRequest = request
        case "packing":
            app.packing.preview(name: "Harbor Handoff.zip", phase: .running(0.42))
        case "packed":
            app.packing.preview(name: "Harbor Handoff.zip", phase: .done, verified: true)
        case "packrun":
            runPack(defaults)
            return
        case "cloud-download":
            // An iCloud placeholder on its way down; nothing is downloaded.
            app.cloudDownload = CloudDownload(name: "Field Recordings.zip", isICloud: true, fraction: 0.42)
        case "password":
            // The question after a rejected password; nothing is checked against an archive.
            let purpose: PasswordPrompt.Question.Purpose = switch defaults.string(forKey: "StowPasswordPurpose") {
            case "unlock": .unlock
            case "open": .open
            default: .extract
            }
            let isRetry = defaults.object(forKey: "StowPasswordRetry") == nil || defaults.bool(forKey: "StowPasswordRetry")
            Task { _ = await app.passwords.ask(.init(archiveName: "Harbor Handoff.7z", purpose: purpose, isRetry: isRetry)) }
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
            app.batch.preview([
                ("Field Recordings.7z", .done), ("server-logs.tar.xz", .running(0.62)),
                ("Brand Kit.zip", .waiting), ("Old Backup.rar", .failed(Failure(EngineError(.passwordRequired), .extract, name: "Old Backup.rar"))),
                ("Fonts 2026.zip", .waiting),
            ])
        case "conflict", "conflict-folder":
            app.openArchive(named: SampleArchive.make().name)
            let isFolder = scene == "conflict-folder"
            let name = isFolder ? "Harbor Rebrand Handoff" : "Brand Guidelines.pdf"
            // Two real files, so the prompt can compare them.
            let base = FileManager.default.temporaryDirectory.appending(path: "Demo Conflict")
            let existing = base.appending(path: "Downloads/\(name)"), incoming = base.appending(path: "Extracting/\(name)")
            for (url, size, age) in [(existing, 7_900_000, -86_400.0 * 12), (incoming, 8_400_000, -3_600.0)] {
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                if isFolder {
                    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                } else {
                    FileManager.default.createFile(atPath: url.path, contents: Data(count: size))
                }
                try? FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: age)], ofItemAtPath: url.path)
            }
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                _ = await Prompts.resolve(Placement.Conflict(name: name, existing: existing, incoming: incoming, canMerge: isFolder))
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
        case "open-failed", "open-damaged":
            // The sheet after an open that failed: not an archive, or one that's damaged.
            let failure = scene == "open-damaged"
                ? Failure(EngineError(.failed, "7-Zip couldn’t finish: Unexpected end of archive"), .open, name: "Field Recordings.7z")
                : Failure(EngineError(.notAnArchive), .open, name: "Invoice October.pdf")
            app.openFailure = AppState.OpenFailure(failure: failure)
        case "open-unreadable":
            // A file in WeChat's private storage that macOS won't let Stow read.
            let url = URL(filePath: "/Users/Shared/Library/Containers/com.tencent.xinWeChat/Data/Library/Application Support/com.tencent.xinWeChat/2.0b4.0.9/Message/File/Harbor Handoff.zip")
            app.openFailure = AppState.OpenFailure(failure: OtherAppFiles.unreadable(url), url: url)
        case "source-access", "source-access-file":
            // The recovery picker after macOS denied a read, over the welcome window. Nothing is read
            // or granted. `-StowSourcePath <file>` points it at a real folder (the picker can't browse
            // the sandbox's own temporary folder, so the default fixture there only shows the copy);
            // `-StowSourceName <name>` renames the default fixture to try a long name.
            let file: URL
            if let path = defaults.string(forKey: "StowSourcePath") {
                file = URL(filePath: path)
            } else {
                let folder = FileManager.default.temporaryDirectory.appending(path: "Demo Source", directoryHint: .isDirectory)
                try? FileManager.default.removeItem(at: folder)
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                file = folder.appending(path: defaults.string(forKey: "StowSourceName") ?? "Harbor Handoff.zip")
                FileManager.default.createFile(atPath: file.path, contents: Data())
            }
            // `-StowSourceOverBrowser YES`: opening another archive from the Browser instead of the welcome.
            if defaults.bool(forKey: "StowSourceOverBrowser") { app.openArchive(named: SampleArchive.make().name) }
            Task {
                try? await Task.sleep(for: .milliseconds(800))
                // As after a real open: Stow in front, its window key, so the picker comes down as a sheet.
                NSApp.activate()
                NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true && $0.isVisible }?.makeKeyAndOrderFront(nil)
                try? await Task.sleep(for: .milliseconds(200))
                await SourceReadAccess.showPanelForDemo(file, fileOnly: scene == "source-access-file")
            }
        case "source-access-unsaved":
            // Opened after the picker, but the folder's grant couldn't be saved.
            app.openArchive(named: SampleArchive.make().name)
            app.openFailure = AppState.OpenFailure(failure: AppState.unsavedSourceAccess(CocoaError(.fileWriteUnknown)))
        case "finder-failed":
            // Extract Here from Finder that failed: the same sheet, on whatever window Stow has.
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                _ = await Prompts.explain(demoFailure("extract-damaged", name: "Quarterly Backup.zip"))
            }
        case "extract-damaged", "extract-full", "extract-denied", "extract-retry":
            app.openArchive(named: SampleArchive.make().name)
            app.browser?.folder = "Photos"
            app.browser?.selection = ["Photos/Lighthouse.jpg", "Photos/Pier at Dawn.jpg"]
            app.browser?.previewActivity(.init(step: .extract, itemCount: 2, phase: .failed(demoFailure(scene, name: SampleArchive.make().name))))
        case "install-running", "install-app-open":
            // An app part-way into Applications, or refused because the installed copy is open (INS-181).
            app.openArchive(named: SampleArchive.make().name)
            app.browser?.folder = "Prototype"
            app.browser?.selection = ["Prototype/Harbor Prototype.app"]
            let phase: ActivityPhase = scene == "install-running" ? .running(0.42)
                : .failed(Failure(Installer.RunningApp(name: "Harbor Prototype"), .install, name: "Harbor Prototype"))
            app.browser?.previewActivity(.init(step: .moveToApplications, itemCount: 1, phase: phase, name: "Harbor Prototype"))
        case "checkup": app.openArchive(named: SampleArchive.make().name); app.browser?.navigate(to: "Prototype") // just opened, nothing selected
        case "pack-failed":
            app.packing.preview(name: "Harbor Handoff.zip", phase: .failed(demoFailure("pack-failed", name: "Harbor Handoff.zip")))
        case "pack-failed-dmg":
            // A disk image hdiutil refused, worded the way DiskImageCreation reports it.
            let error = EngineError(.failed, String(localized: "Couldn’t make the disk image") + " (hdiutil create: create failed - Resource busy)")
            app.packing.preview(name: "Harbor Handoff.dmg", phase: .failed(Failure(error, .pack, name: "Harbor Handoff.dmg")))
        case "empty-archive":
            app.browser = BrowserModel(archive: Archive(name: "Scans 2026.zip", format: .zip, files: []))
        case "empty-folder":
            let sample = SampleArchive.make()
            let drafts = ArchiveEntry(path: "Drafts", isFolder: true, size: 0, packedSize: 0, modified: .now)
            app.browser = BrowserModel(archive: Archive(name: sample.name, format: sample.format,
                                                        files: sample.files + [drafts], checkup: sample.checkup))
            app.browser?.viewMode = .grid
            app.browser?.folder = "Drafts"
        case "search-empty":
            app.openArchive(named: SampleArchive.make().name)
            app.browser?.query = "invoice"
        case "tray-empty":
            app.tray.items = []
            app.tray.show()
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
        case "glance", "glance-empty", "glance-search-empty", "glance-app":
            if scene == "glance-app" {
                app.browser = oneAppArchive()
            } else if scene == "glance-search-empty" {
                // The same search as the full window's "search-empty" scene.
                app.openArchive(named: SampleArchive.make().name)
                app.browser?.query = "invoice"
            } else if scene == "glance-empty" {
                // The same empty folder as the full window's "empty-folder" scene.
                let sample = SampleArchive.make()
                let drafts = ArchiveEntry(path: "Drafts", isFolder: true, size: 0, packedSize: 0, modified: .now)
                app.browser = BrowserModel(archive: Archive(name: sample.name, format: sample.format,
                                                            files: sample.files + [drafts], checkup: sample.checkup))
                app.browser?.navigate(to: "Drafts")
            } else {
                app.openArchive(named: SampleArchive.make().name)
                app.browser?.navigate(to: "Photos")
                app.browser?.select(["Photos/Lighthouse.jpg", "Photos/Pier at Dawn.jpg"])
            }
            let pointer = glanceEdge(defaults).pointer(in: (NSScreen.main ?? NSScreen.screens[0]).visibleFrame)
            app.glance.collapse(near: pointer, animated: false)
            if let size = defaults.string(forKey: "StowWindowSize")?.split(separator: "x").compactMap({ Double($0) }), size.count == 2 {
                app.glance.show(near: pointer, size: CGSize(width: size[0], height: size[1]), animated: false)
            }
        case "recents":
            // The welcome window with history; the files don't exist and nothing is saved.
            let home = FolderAccess.home.path
            let hour: TimeInterval = 3600
            app.recents.preview([
                ("\(home)/Downloads/Harbor Rebrand Handoff.zip", .now.addingTimeInterval(-0.4 * hour)),
                ("\(home)/Documents/Field Recordings/Field Recordings.7z", .now.addingTimeInterval(-3 * hour)),
                ("\(home)/Projects/harbor-api/server-logs.tar.xz", .now.addingTimeInterval(-26 * hour)),
                ("\(home)/Downloads/Fonts 2026.zip", .now.addingTimeInterval(-3 * 24 * hour)),
                ("/Volumes/Archive/Backups/Old Backup.rar", .now.addingTimeInterval(-9 * 24 * hour)),
                ("\(home)/Desktop/Kickoff Deck.zip", .now.addingTimeInterval(-24 * 24 * hour)),
            ])
        case "tray":
            app.tray.items = [
                TrayItem(name: "Invoice October.pdf", size: 182_000),
                TrayItem(name: "Pier at Dawn.jpg", size: 4_210_000),
                TrayItem(name: "Kickoff.key", size: 18_900_000),
                TrayItem(name: "budget-2027.numbers", size: 412_000),
                TrayItem(name: "Site Photos", size: 0, isFolder: true),
                TrayItem(name: "Brand Assets.zip", size: 26_400_000),
            ]
            app.tray.selection = [app.tray.items[1].id, app.tray.items[2].id]
            app.tray.show()
        case "tray-files":
            // Real files on disk, so the rows show what Finder would: text, an image, a PDF, a ZIP, a folder.
            let folder = FileManager.default.temporaryDirectory.appending(path: "Demo Tray Files", directoryHint: .isDirectory)
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.createDirectory(at: folder.appending(path: "Site Photos"), withIntermediateDirectories: true)
            let note = folder.appending(path: "Notes.txt"), short = folder.appending(path: "File 01.txt")
            try? Data("Kickoff notes\n\n- Agree the scope\n- Book the photographer\n- Send the brand kit\n".utf8).write(to: note)
            try? Data("01\n".utf8).write(to: short)
            let picture = folder.appending(path: "Pier at Dawn.png")
            let image = NSImage(size: CGSize(width: 240, height: 160), flipped: false) { rect in
                NSGradient(starting: .systemOrange, ending: .systemIndigo)?.draw(in: rect, angle: 90)
                return true
            }
            if let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: picture)
            }
            let pdf = folder.appending(path: "Invoice October.pdf")
            let page = NSTextView(frame: CGRect(x: 0, y: 0, width: 300, height: 400))
            page.string = "Invoice October\n\nHarbor Studio\n\n3 × Brand workshop\nTotal 4,200"
            try? page.dataWithPDF(inside: page.bounds).write(to: pdf)
            let zip = folder.appending(path: "Brand Assets.zip")
            try? Data([0x50, 0x4B, 0x05, 0x06] + [UInt8](repeating: 0, count: 18)).write(to: zip)
            app.tray.add([note, short, picture, pdf, zip, folder.appending(path: "Site Photos")])
            app.tray.showArrivalForDemo([])
            app.tray.show()
        case "tray-arrived":
            // Three rows just dropped; the last is already on the Tray and was dropped again.
            app.tray.items = [
                TrayItem(name: "Invoice October.pdf", size: 182_000),
                TrayItem(name: "Pier at Dawn.jpg", size: 4_210_000),
                TrayItem(name: "Kickoff.key", size: 18_900_000),
                TrayItem(name: "budget-2027.numbers", size: 412_000),
                TrayItem(name: "Brand Assets.zip", size: 26_400_000),
            ]
            app.tray.showArrivalForDemo(Set(app.tray.items.suffix(3).map(\.id)))
            app.tray.show()
        case "tray-failed":
            app.tray.items = [
                TrayItem(name: "Invoice October.pdf", size: 182_000),
                TrayItem(name: "Pier at Dawn.jpg", size: 4_210_000),
                TrayItem(name: "Kickoff.key", size: 18_900_000),
            ]
            app.tray.show()
            // A copy that failed part-way: the footer's failure card.
            app.tray.failure = Failure(NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC)), .copy, name: "Kickoff.key")
        case "tray-collect", "tray-collect-taken", "tray-collect-mixed", "tray-collected":
            // Real files, so the Where rule runs: one folder (it's the default), or three (people choose).
            let layout: [(String, [String])] = scene == "tray-collect-mixed"
                ? [("Invoices", ["Invoice October.pdf"]), ("Photos", ["Pier at Dawn.jpg", "Lighthouse.jpg"]), ("Kickoff", ["Kickoff.key"])]
                : [("Kickoff", ["Invoice October.pdf", "Pier at Dawn.jpg", "Kickoff.key"])]
            let urls = demoTrayFiles(layout, taken: scene == "tray-collect-taken" ? String(localized: "New Folder") : nil)
            app.tray.items = []
            app.tray.add(urls)
            app.tray.showArrivalForDemo([])
            app.tray.show()
            // The scenes ignore any folder remembered on this Mac, so they look the same everywhere.
            app.tray.beginCollecting(remembered: nil)
            switch scene {
            case "tray-collect-taken": app.tray.showCollectProblemForDemo(String(localized: "New Folder"))
            case "tray-collected": Task { await app.tray.collectIntoFolder() }
            default: break
            }
        default:
            break
        }

        if scene == "open" { BrowseDemo.apply(to: app) }

        // `-StowEncrypted YES` marks the sample archive encrypted in any scene (Glance, List…);
        // `-StowLock checking|available` shows the lock checking a password, or after one worked.
        if defaults.bool(forKey: "StowEncrypted"), let level = app.browser?.level {
            level.archive.isEncrypted = true
            level.savedArchive.isEncrypted = true
        }
        switch defaults.string(forKey: "StowLock") {
        case "checking": app.browser?.showUnlockingForDemo()
        case "available": app.browser?.level.password = "demo"
        default: break
        }

        // `-StowViewMode grid|list|columns` and `-StowScrollToEnd YES`: check what floats over the last row.
        if let mode = defaults.string(forKey: "StowViewMode").flatMap(BrowserModel.ViewMode.init(rawValue:)) {
            app.browser?.viewMode = mode
        }
        if defaults.bool(forKey: "StowScrollToEnd") {
            Task {
                try? await Task.sleep(for: .milliseconds(700))
                app.browser?.scrollTarget = app.browser?.visibleEntries.last?.id
            }
        }

        if !scene.hasPrefix("glance"), let size = defaults.string(forKey: "StowWindowSize")?.split(separator: "x").compactMap({ Double($0) }),
           size.count == 2 {
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                // The Browser opens a moment after the welcome window; wait for it rather than
                // resizing whichever window happens to be up first.
                for _ in 0..<20 where scene != "settings" && !NSApp.windows.contains(where: { $0.identifier?.rawValue.hasPrefix("main") == true && $0.isVisible }) {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                let targetWindow = scene == "settings" ? NSApp.keyWindow
                    : NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true && $0.isVisible })
                    ?? NSApp.windows.first(where: { !($0 is NSPanel) && $0.isVisible })
                guard let window = targetWindow else { return }
                // A scene's size is for its picture only: never save it as the window's everyday frame.
                window.setFrameAutosaveName("")
                window.setContentSize(CGSize(width: size[0], height: size[1]))
            }
        }

        if defaults.bool(forKey: "StowSnapshot") {
            Task {
                let delay = defaults.double(forKey: "StowSnapshotDelay")
                // `-StowActivate YES`: capture as the front app, so default buttons show their colour.
                if defaults.bool(forKey: "StowActivate") { NSApp.activate() }
                try? await Task.sleep(for: .seconds(delay > 0 ? delay : 1.6))
                // Glance snapshots are named by the edge they opened at, so each edge keeps its own file.
                let label = scene == "glance" ? "glance-\(glanceEdge(defaults).rawValue)" : scene
                // The Tray's menu-bar icon lives in a status-bar window of its own; it isn't a scene.
                let windows = NSApp.windows.filter { $0.isVisible && !$0.className.contains("StatusBar") }
                for (index, window) in windows.enumerated() {
                    let kind = window.sheetParent != nil ? "sheet" : window is NSPanel ? "panel" : "window"
                    let name = index == 0 ? "\(label)-\(kind)" : "\(label)-\(kind)\(index)"
                    if let url = snapshot(window, name: name) { print(url.path) }
                }
                if defaults.bool(forKey: "StowLogLayout") {
                    // Who has the keyboard, and which toolbar items made it out of the overflow menu.
                    print("focus:", NSApp.keyWindow?.firstResponder.map { String(describing: type(of: $0)) } ?? "none")
                    if let toolbar = NSApp.windows.compactMap(\.toolbar).first {
                        print("toolbar:", toolbar.visibleItems?.map(\.label).filter { !$0.isEmpty } ?? [])
                    }
                }
                if scene == "glance", let url = glancePlacement(app, name: "\(label)-screen") { print(url.path) }
                if scene == "next-steps-more", let url = NextStepsDemo.captureWithMenu(name: "\(label)-menu") { print(url.path) }
                fflush(stdout)
                exit(0) // terminate(_:) waits on open sheets; this is a screenshot run.
            }
        }
    }

    /// Real files for the Tray's Collect scenes, in folders inside the sandbox's temporary
    /// directory (made fresh each run). `taken` puts an item of that name in the first folder.
    private static func demoTrayFiles(_ layout: [(String, [String])], taken: String?) -> [URL] {
        let base = FileManager.default.temporaryDirectory.appending(path: "Demo Tray", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: base)
        var urls: [URL] = []
        for (folder, names) in layout {
            let dir = base.appending(path: folder, directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for name in names {
                let url = dir.appending(path: name)
                FileManager.default.createFile(atPath: url.path, contents: Data(name.utf8))
                urls.append(url)
            }
        }
        if let taken, let first = layout.first {
            try? FileManager.default.createDirectory(at: base.appending(path: "\(first.0)/\(taken)", directoryHint: .isDirectory),
                                                     withIntermediateDirectories: true)
        }
        return urls
    }

    /// The error scenes' failures, made from the errors the engine and the file system really throw.
    private static func demoFailure(_ scene: String, name: String) -> Failure {
        let downloads = FileManager.default.temporaryDirectory
        return switch scene {
        case "extract-damaged": Failure(EngineError(.failed, "Data Error : Photos/Lighthouse.jpg"), .extract, name: name)
        case "extract-full": Failure(NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC)), .extract, name: name,
                                     destination: downloads, needs: 189_000_000)
        case "pack-failed": Failure(NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC)), .pack, name: name,
                                    destination: downloads, needs: 0)
        case "extract-denied": Failure(NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError), .extract,
                                       name: name, destination: URL(filePath: "/Users/Shared", directoryHint: .isDirectory))
        default: Failure(EngineError(.connectionLost), .extract, name: name)
        }
    }

    /// Packs for real through the engine and prints where the archive went, then quits:
    ///
    ///     -StowScene packrun -StowPack <folder> -StowPackTo <folder> -PackAudience mac
    ///         [-StowFormat zip|sevenZip|tar|tarGz|tarBz2|tarXz|tarZst] [-StowPassword pw] [-StowSplit bytes] [-PackVerify YES]
    ///         [-StowPackIncludeHelpers YES|NO] [-StowPackMetadata YES|NO] [-StowPackEncryptNames NO] [-StowPackThreads n]
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
            // More Options (#152, #153): -StowPackIncludeHelpers YES|NO and -StowPackMetadata YES|NO go
            // through the same setters as the sheet's checkboxes; -StowPackEncryptNames NO, -StowPackThreads n.
            if defaults.object(forKey: "StowPackIncludeHelpers") != nil {
                options.setIncludesMacHelperFiles(defaults.bool(forKey: "StowPackIncludeHelpers"))
            }
            if defaults.object(forKey: "StowPackMetadata") != nil {
                options.setKeepsMacMetadata(defaults.bool(forKey: "StowPackMetadata"))
            }
            if defaults.object(forKey: "StowPackEncryptNames") != nil {
                options.encryptFilenames = defaults.bool(forKey: "StowPackEncryptNames")
            }
            if defaults.integer(forKey: "StowPackThreads") > 0 { options.threads = defaults.integer(forKey: "StowPackThreads") }
            let split = Int64(defaults.integer(forKey: "StowSplit"))
            let name = Compatibility.archiveName(request.suggestedName, for: options.audience)
            let keepsMetadata = options.effectiveKeepsMacMetadata
            if defaults.bool(forKey: "StowPackApplications"), options.format == .dmg {
                options.diskImageApplicationsLink = true
            }
            if let fs = defaults.string(forKey: "StowPackFilesystem"), options.format == .dmg {
                options.diskImageFilesystem = DiskImageFilesystem(rawValue: fs) ?? .hfsPlus
            }
            options.diskImageFinderChrome = options.format == .dmg && defaults.bool(forKey: "StowPackFinderChrome")
            let report = Compatibility.report(for: request.files, options: options, password: password ?? "")
            var create = CreateRequest(operationID: UUID().uuidString, archiveName: name, format: options.format,
                                       level: options.level, password: options.usesPassword ? password : nil,
                                       volumeSize: split > 0 ? split : nil, keepsMacMetadata: keepsMetadata,
                                       verify: PackPreferences.verify, threads: options.effectiveThreads(global: PackPreferences.threads),
                                       diskImageFilesystem: options.format == .dmg ? options.diskImageFilesystem : .hfsPlus,
                                       diskImageApplicationsLink: options.format == .dmg && options.diskImageApplicationsLink,
                                       diskImageFinderChrome: options.format == .dmg && options.diskImageFinderChrome)
            create.encryptFilenames = options.format == .sevenZip && options.encryptFilenames
            do {
                let result = try await ArchiveCreation.run(report.items, totalBytes: report.totalBytes,
                                                           attributes: keepsMetadata, request: create, named: name,
                                                           in: URL(filePath: target)) { _ in }
                result.placed.forEach { print($0.path) }
                print("renamed \(report.renames.count), left out \(report.excluded.count + report.leftOutLinks.count), verified \(result.report.verified)")
                print("threads \(create.threads.map(String.init) ?? "all"), metadata \(keepsMetadata), encrypt names \(create.encryptFilenames)")
                report.notes.forEach { print("note: \($0.title) — \($0.detail)") }
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

    /// A fictional archive that's one app and a Read Me, with nothing selected: Actions offers to
    /// install the app. Nothing is on disk, so Install only simulates.
    private static func oneAppArchive() -> BrowserModel {
        let modified = Date(timeIntervalSince1970: 1_791_000_000)
        let model = BrowserModel(archive: Archive(name: "Harbor Prototype.zip", format: .zip, files: [
            ArchiveEntry(path: "Harbor Prototype.app", isFolder: false, size: 48_600_000, packedSize: 21_400_000, modified: modified),
            ArchiveEntry(path: "Read Me.txt", isFolder: false, size: 2_400, packedSize: 1_100, modified: modified),
        ]))
        model.select([])
        return model
    }

    private static func glanceEdge(_ defaults: UserDefaults) -> GlancePlacement.Edge {
        defaults.string(forKey: "StowGlanceEdge").flatMap(GlancePlacement.Edge.init(rawValue:)) ?? .center
    }

    /// The whole screen at half size: the visible area, the menu bar and Dock strips Glance stays
    /// out of, the Glance window where it opened, and the pointer that opened it.
    private static func glancePlacement(_ app: AppState, name: String) -> URL? {
        guard let window = app.glance.window, let screen = window.screen ?? NSScreen.main else { return nil }
        let scale: CGFloat = 0.5
        let bounds = screen.frame
        let pointer = glanceEdge(.standard).pointer(in: screen.visibleFrame)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * scale), pixelsHigh: Int(bounds.height * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        func place(_ rect: CGRect) -> CGRect {
            CGRect(x: (rect.minX - bounds.minX) * scale, y: (rect.minY - bounds.minY) * scale,
                   width: rect.width * scale, height: rect.height * scale)
        }
        let dark = window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor(white: dark ? 0.08 : 0.62, alpha: 1).setFill()
        CGRect(x: 0, y: 0, width: bounds.width * scale, height: bounds.height * scale).fill()
        NSColor(white: dark ? 0.2 : 0.86, alpha: 1).setFill()
        place(screen.visibleFrame).fill()
        typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        if let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY),
           let symbol = dlsym(handle, "CGWindowListCreateImage"),
           // Including the window, its frame only (no shadow), best resolution.
           let image = unsafeBitCast(symbol, to: CreateImage.self)(.null, 1 << 3, UInt32(window.windowNumber), 1 << 0 | 1 << 3)?
            .takeRetainedValue() {
            context.cgContext.draw(image, in: place(window.frame))
        } else {
            NSColor.controlAccentColor.setFill()
            place(window.frame).fill()
        }
        let dot = CGRect(x: (pointer.x - bounds.minX) * scale - 5, y: (pointer.y - bounds.minY) * scale - 5, width: 10, height: 10)
        NSColor.systemRed.setFill()
        NSBezierPath(ovalIn: dot).fill()
        NSColor.white.setStroke()
        let ring = NSBezierPath(ovalIn: dot)
        ring.lineWidth = 1.5
        ring.stroke()
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.representation(using: .png, properties: [:]) else { return nil }
        let url = FileManager.default.temporaryDirectory.appending(path: "\(name).png")
        return (try? data.write(to: url)) != nil ? url : nil
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
