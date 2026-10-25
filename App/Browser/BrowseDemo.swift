import AppKit
import Quartz

/// Launch arguments that drive a real archive opened with `-StowScene open -StowOpen <path>`, for
/// design review and verification runs:
///
///     -StowNested "Showcase/Nested/Earlier Rounds.7z"   open archives inside, `|`-separated chain
///     -StowFolder Showcase/Photos   -StowView grid|list|columns   -StowHelpers YES
///     -StowSelect "Mac-Blue.jpg|Sonoma.jpg"   (names in the folder)   -StowQuery "tide"   -StowFind YES (⌘F)
///     -browse.showsFolders YES   -browse.showsInspector NO   (which optional panes are open)
///     -StowQuickLook YES   -StowHover "README.md"   -StowMove down   -StowEncodingSheet YES
///
/// Pair with `-StowSnapshotDelay 5` so thumbnails and previews arrive before the picture.
enum BrowseDemo {
    static func editing(in app: AppState) {
        app.openArchive(named: SampleArchive.make().name)
        guard let model = app.browser else { return }
        model.folder = "Photos"
        model.editSession.add(sampleFilesToAdd(), into: "Photos")
        model.editSession.rename("Photos/Lighthouse.jpg", to: "Harbor Lighthouse.jpg")
        model.editSession.delete(["Photos/Pier at Dawn.jpg"])
        model.selection = ["Photos/Field Notes.txt"]
    }

    /// Two real files to add, so the staged items have a size, a date and a kind like a real drop.
    private static func sampleFilesToAdd() -> [URL] {
        let folder = FileManager.default.temporaryDirectory.appending(path: "Stow-Sample", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let notes = folder.appending(path: "Field Notes.txt")
        let sheet = folder.appending(path: "Contact Sheet.pdf")
        let text = String(repeating: "Harbor, 6:40 am. Low tide, pier lights still on. Shot the lighthouse from the north jetty.\n", count: 40)
        try? Data(text.utf8).write(to: notes)
        let pdf = NSMutableData()
        var page = CGRect(x: 0, y: 0, width: 612, height: 792)
        if let consumer = CGDataConsumer(data: pdf), let context = CGContext(consumer: consumer, mediaBox: &page, nil) {
            for index in 0..<4 {
                context.beginPDFPage(nil)
                context.setFillColor(gray: 0.2 + 0.15 * CGFloat(index), alpha: 1)
                context.fill(page.insetBy(dx: 72, dy: 96))
                context.endPDFPage()
            }
            context.closePDF()
        }
        try? (pdf as Data).write(to: sheet)
        let date = Date.now.addingTimeInterval(-2 * 3600)
        for url in [notes, sheet] { try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path) }
        return [notes, sheet]
    }

    static func readOnly(in app: AppState) {
        var archive = SampleArchive.make(named: "Harbor Handoff.rar")
        archive.format = .rar
        app.browser = BrowserModel(archive: archive)
        app.browser?.editSession.showsReadOnly = true
    }

    static func externalChange(in app: AppState) {
        app.openArchive(named: SampleArchive.make().name)
        guard let model = app.browser else { return }
        model.folder = "Photos"
        model.editSession.rename("Photos/Lighthouse.jpg", to: "Harbor Lighthouse.jpg")
        model.editSession.delete(["Photos/Pier at Dawn.jpg"])
        model.editSession.revealExternalChangeForDemo()
        model.selection = ["Photos/Harbor Lighthouse.jpg"]
    }

    static func apply(to app: AppState) {
        let defaults = UserDefaults.standard
        Task {
            let started = ContinuousClock.now
            let deadline = started + .seconds(60)
            while app.browser == nil, ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(20)) }
            guard let model = app.browser else { return }
            if defaults.bool(forKey: "StowScrollBenchmark") {
                print("Opened \(model.archive.entries.count) entries in \(ContinuousClock.now - started)")
            }
            for path in defaults.string(forKey: "StowNested")?.split(separator: "|").map(String.init) ?? [] {
                let depth = model.levels.count
                guard let entry = model.archive.entry(at: path) else { break }
                model.openInside(entry)
                while model.levels.count == depth, ContinuousClock.now < deadline {
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
            if let view = defaults.string(forKey: "StowView").flatMap(BrowserModel.ViewMode.init) { model.viewMode = view }
            model.showHelperItems = defaults.bool(forKey: "StowHelpers")
            if let folder = defaults.string(forKey: "StowFolder") { model.navigate(to: folder) }
            if let names = defaults.string(forKey: "StowSelect") {
                let ids = names.split(separator: "|").map { model.folder.isEmpty ? String($0) : model.folder + "/" + $0 }
                if model.viewMode == .columns, ids.count == 1, let entry = model.archive.entry(at: ids[0]) {
                    model.columnSelect(entry)
                } else {
                    model.select(Set(ids), scroll: true)
                }
            }
            if let query = defaults.string(forKey: "StowQuery") { model.query = query }
            if defaults.bool(forKey: "StowFind") { model.focusSearch() }
            try? await Task.sleep(for: .milliseconds(400))
            if let move = defaults.string(forKey: "StowMove") {
                let direction: BrowserModel.Direction = switch move {
                case "up": .up
                case "left": .left
                case "right": .right
                default: .down
                }
                model.move(direction)
            }
            if defaults.bool(forKey: "StowQuickLook") {
                model.toggleQuickLook()
                try? await Task.sleep(for: .seconds(1.5))
                report(model, "opened")
                // An arrow pressed while the panel has the keyboard, as the panel delivers it.
                if let key = defaults.string(forKey: "StowQuickLookArrow"), let panel = QLPreviewPanel.shared(),
                   let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                windowNumber: panel.windowNumber, context: nil, characters: "",
                                                charactersIgnoringModifiers: "", isARepeat: false,
                                                keyCode: key == "left" ? 123 : key == "up" ? 126 : key == "down" ? 125 : 124) {
                    _ = model.quickLook.previewPanel(panel, handle: event)
                    try? await Task.sleep(for: .seconds(1.5))
                    report(model, "after \(key)")
                }
            }
            if let hover = defaults.string(forKey: "StowHover") {
                model.demoHover = model.folder.isEmpty ? hover : model.folder + "/" + hover
                if defaults.bool(forKey: "StowLogPreview"), let entry = model.archive.entry(at: model.demoHover!) {
                    print("Preview:", await model.previews.richPreview(for: entry, in: model.archive))
                    fflush(stdout)
                }
            }
            if defaults.bool(forKey: "StowEncodingSheet") { model.isChoosingEncoding = true }
            if defaults.bool(forKey: "StowDragTest"), let window = NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) }),
               let first = model.selectedEntries.first {
                // A press on the first selected entry that turns into a drag, through the app's own
                // event dispatch (where the drag-out monitor listens).
                model.dragOut.onBegin = { paths in
                    print("Drag began with \(paths.count) file promises: \(paths)")
                    fflush(stdout)
                }
                model.dragOut.hovered = first.id
                let point = NSPoint(x: window.frame.width / 2, y: window.frame.height / 2)
                for (type, offset) in [(NSEvent.EventType.leftMouseDown, 0.0), (.leftMouseDragged, 3.0), (.leftMouseDragged, 12.0)] {
                    if let event = NSEvent.mouseEvent(with: type, location: NSPoint(x: point.x + offset, y: point.y),
                                                      modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                      windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                                      clickCount: 1, pressure: 1) {
                        NSApp.sendEvent(event)
                    }
                }
            }
            if defaults.bool(forKey: "StowScrollBenchmark"), let window = NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) }) {
                while model.level.indexed < model.level.search.total { try? await Task.sleep(for: .milliseconds(50)) }
                try? await Task.sleep(for: .seconds(1.5))
                print("Scroll (\(model.viewMode.rawValue), \(model.visibleEntries.count) items):", await ScrollBenchmark.run(in: window))
                fflush(stdout)
            }
        }
    }

    /// What the Quick Look panel is showing — its content is drawn out of process, so window
    /// snapshots can't show it.
    private static func report(_ model: BrowserModel, _ moment: String) {
        let panel = QLPreviewPanel.shared()
        let item = panel?.currentPreviewItem as? QuickLookController.Item
        let size = (item?.url).flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize } ?? -1
        print("QuickLook \(moment): visible=\(panel?.isVisible == true) items=\(model.quickLook.entries.count) "
              + "current=\(item?.entry.path ?? "-") bytes=\(size) selection=\(model.selection.sorted())")
        fflush(stdout)
    }
}
