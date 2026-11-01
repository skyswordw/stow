import AppKit
import ImageIO
import Quartz

/// Launch arguments that drive a real archive opened with `-StowScene open -StowOpen <path>`, for
/// design review and verification runs:
///
///     -StowNested "Showcase/Nested/Earlier Rounds.7z"   open archives inside, `|`-separated chain
///     -StowFolder Showcase/Photos   -StowView grid|list|columns   -StowHelpers YES
///     -StowSelect "Mac-Blue.jpg|Sonoma.jpg"   (names in the folder)   -StowQuery "tide"   -StowFind YES (⌘F)
///     -StowQuickLook YES   -StowHover "README.md"   -StowMove down   -StowEncodingSheet YES
///     -StowActionsOpen YES   (the Actions stack fanned out)   -StowUnlock YES   (asks for the password)
///     -StowEdits YES   (the editing scene's unsaved changes in Photos; nothing is saved)
///
/// Pair with `-StowSnapshotDelay 5` so thumbnails and previews arrive before the picture.
enum BrowseDemo {
    static func editing(in app: AppState) {
        app.openArchive(named: SampleArchive.make().name)
        guard let model = app.browser else { return }
        stageEdits(in: model)
    }

    /// Three unsaved changes in Photos: two files added, one renamed, one deleted. `-StowEdits YES`
    /// stages them on a real archive too (Try the Sample's ZIP); nothing is written until Save.
    static func stageEdits(in model: BrowserModel) {
        model.folder = "Photos"
        model.editSession.add(sampleFilesToAdd(), into: "Photos")
        model.editSession.rename("Photos/Lighthouse.jpg", to: "Harbor Lighthouse.jpg")
        model.editSession.delete(["Photos/Pier at Dawn.jpg"])
        model.selection = ["Photos/Field Notes.txt"]
    }

    /// Two real files to add, so the staged items have a size, a date, a kind and a preview like a
    /// real drop: the photographer's notes, and a contact sheet of the sample's own photos.
    private static func sampleFilesToAdd() -> [URL] {
        let folder = FileManager.default.temporaryDirectory.appending(path: "Stow-Sample", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let notes = folder.appending(path: "Field Notes.txt")
        let sheet = folder.appending(path: "Contact Sheet.pdf")
        try? Data(fieldNotes.utf8).write(to: notes)
        try? contactSheet().write(to: sheet)
        let date = Date.now.addingTimeInterval(-2 * 3600)
        for url in [notes, sheet] { try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path) }
        return [notes, sheet]
    }

    private static let fieldNotes = """
        Harbor shoot, field notes

        Tue 6:10 am. New Brighton pier
        Low tide 5:52. Pier lights off at 6:20, so the first frames still have them on.
        Shot from the beach steps, 24 mm, f/8. Pier at Dawn is frame 41; 38 to 44 are all usable.

        Tue 9:30 am. Akaroa lighthouse
        Clear sky, light from the east until about 10. Walked around to the harbour side for the
        hills behind the tower. Lighthouse is frame 112. The keeper's gate was locked, so
        nothing from the gallery this time.

        Tue 7:45 pm. Akaroa moorings
        Blue hour lasted about 20 minutes. Tripod on the main wharf, 2 s exposures.
        Harbor at Night is frame 203. Boats swing on the tide, so check sharpness at 100%.

        Wed. Oamaru boat harbour
        Overcast, flat light, good for the old jetty's texture. Shot on the compact as HEIC.

        To do
        - Rope Detail: crop tighter for the onboarding card (square, 1:1).
        - Lighthouse: rename to Harbor Lighthouse before it goes to the app team.
        - Drop Pier at Dawn from this round; marketing wants it for the launch post only.
        - Contact sheet attached for anyone without the full set.
        """

    /// A two-page contact sheet of the sample's photos, captioned like a photographer's proof.
    private static func contactSheet() -> Data {
        let pdf = NSMutableData()
        var page = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(data: pdf),
              let context = CGContext(consumer: consumer, mediaBox: &page, nil) else { return Data() }
        let photos = ["Pier at Dawn.jpg", "Lighthouse.jpg", "Harbor at Night.jpg", "Rope Detail.jpg", "Old Jetty.heic"]
        let images = photos.compactMap { name -> (String, CGImage)? in
            guard let url = SampleContent.photo(named: name), let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 520,
                      kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
            return (name, image)
        }
        let margin: CGFloat = 54, gap: CGFloat = 18, columns = 2
        let cell = (page.width - 2 * margin - gap) / CGFloat(columns)
        let frame = cell * 2 / 3
        func text(_ string: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, at point: CGPoint) {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]))
            context.textPosition = point
            CTLineDraw(line, context)
        }
        for (pageIndex, chunk) in stride(from: 0, to: images.count, by: 4).enumerated() {
            context.beginPDFPage(nil)
            context.setFillColor(.white)
            context.fill(page)
            text("Harbor shoot · contact sheet", size: 16, weight: .semibold, color: .black,
                 at: CGPoint(x: margin, y: page.height - margin - 16))
            text("New Brighton, Akaroa, Oamaru · page \(pageIndex + 1) of \((images.count + 3) / 4)", size: 9,
                 weight: .regular, color: .darkGray, at: CGPoint(x: margin, y: page.height - margin - 32))
            for (index, (name, image)) in images[chunk..<min(chunk + 4, images.count)].enumerated() {
                let x = margin + CGFloat(index % columns) * (cell + gap)
                let top = page.height - margin - 60 - CGFloat(index / columns) * (frame + 46)
                let box = CGRect(x: x, y: top - frame, width: cell, height: frame)
                context.setFillColor(NSColor(white: 0.12, alpha: 1).cgColor)
                context.fill(box)
                let scale = min((box.width - 12) / CGFloat(image.width), (box.height - 12) / CGFloat(image.height))
                let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
                context.draw(image, in: CGRect(x: box.midX - size.width / 2, y: box.midY - size.height / 2,
                                               width: size.width, height: size.height))
                text(name, size: 9, weight: .medium, color: .black, at: CGPoint(x: x, y: box.minY - 14))
            }
            context.endPDFPage()
        }
        context.closePDF()
        return pdf as Data
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
            if defaults.bool(forKey: "StowEdits") { stageEdits(in: model) }
            if let query = defaults.string(forKey: "StowQuery") { model.query = query }
            if defaults.bool(forKey: "StowFind") { model.focusSearch() }
            try? await Task.sleep(for: .milliseconds(400))
            // `-StowGlance YES`: the same archive, place and selection in Glance, mid-screen.
            if defaults.bool(forKey: "StowGlance") {
                let visible = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
                app.glance.collapse(near: CGPoint(x: visible.midX, y: visible.midY), animated: false)
                // Glance shows a list; coming from another view mode can drop the selection, so pick it again.
                if let names = defaults.string(forKey: "StowSelect"), model.selection.isEmpty {
                    try? await Task.sleep(for: .milliseconds(300))
                    model.select(Set(names.split(separator: "|").map { model.folder.isEmpty ? String($0) : model.folder + "/" + $0 }))
                }
            }
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
            if defaults.bool(forKey: "StowUnlock") { model.unlockArchive() }
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
