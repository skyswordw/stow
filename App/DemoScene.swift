import AppKit

/// Launch-argument hooks for design review and screenshots:
///
///     Stow.app/Contents/MacOS/Stow -StowScene grid -StowSnapshot YES
///
/// Scenes: welcome, grid, list, fonts, search, activity, pack, tray, open (`-StowOpen <path>`).
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
            app.packRequest = PackRequest(files: SampleArchive.packCandidates)
        case "open":
            // A real archive through the engine: -StowScene open -StowOpen <path inside the sandbox>
            if let path = defaults.string(forKey: "StowOpen") { app.open(URL(filePath: path)) }
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
                guard let window = NSApp.windows.first(where: { !($0 is NSPanel) && $0.isVisible }) else { return }
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

    /// Captures the window as the window server composited it — glass, shadows and all.
    /// `CGWindowListCreateImage` is hidden from the SDK but still exported; an app may
    /// capture its own windows without Screen Recording permission.
    private static func snapshot(_ window: NSWindow, name: String) -> URL? {
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
