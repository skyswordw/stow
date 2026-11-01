import AppKit
import SwiftUI
import Testing
@testable import Stow

/// Details' column without the inspector's own edge (#242): the shadow and hairline AppKit draws
/// beside it are hidden so the rounded panel is its only outline, and the column still resizes.
@Suite("Details column")
@MainActor
struct DetailsColumnTests {
    @Test func theInspectorsEdgeIsHidden() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        try await fixture.settle()
        let split = try #require(fixture.splitView)
        let seams = split.subviews.filter { ["_NSSplitViewShadowView", "NSSplitDividerView"].contains(String(describing: type(of: $0))) }
        #expect(!seams.isEmpty, "AppKit's inspector edge views changed; revisit InspectorSeams")
        let allHidden = seams.allSatisfy { $0.isHidden }
        #expect(allHidden)
    }

    /// Dragging the boundary between the files and Details still changes Details' width.
    @Test func detailsStillResizesByDraggingItsEdge() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        try await fixture.settle()
        let split = try #require(fixture.splitView)
        let inspector = try #require(split.arrangedSubviews.last)
        let before = inspector.frame.width
        let edge = split.convert(NSPoint(x: inspector.frame.minX - split.dividerThickness / 2, y: split.bounds.midY), to: nil)
        let target = NSPoint(x: edge.x - 60, y: edge.y)

        // The split view tracks a drag in its own loop, pulling the rest of the gesture from the queue.
        for (type, point) in [(NSEvent.EventType.leftMouseDragged, NSPoint(x: edge.x - 30, y: edge.y)),
                              (.leftMouseDragged, target), (.leftMouseUp, target)] {
            NSApp.postEvent(try fixture.mouse(type, at: point), atStart: false)
        }
        fixture.window.sendEvent(try fixture.mouse(.leftMouseDown, at: edge))
        try await fixture.settle()

        #expect(inspector.frame.width > before + 20, "Details was \(before) pt wide and is \(inspector.frame.width) pt")
        // And its edge stays hidden after the resize.
        let dividerHidden = split.subviews.filter { String(describing: type(of: $0)) == "NSSplitDividerView" }.allSatisfy { $0.isHidden }
        #expect(dividerHidden)
    }

    private final class Fixture {
        let window: NSWindow
        let host: NSHostingController<AnyView>

        init() {
            let model = BrowserModel(archive: Archive(name: "Details.zip", format: .zip, files: [
                ArchiveEntry(path: "alpha.txt", isFolder: false, size: 1, packedSize: 1, modified: .now),
            ]))
            let app = AppState()
            app.browser = model
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 700),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            host = NSHostingController(rootView: AnyView(BrowserView(model: model).environment(app)))
            host.sceneBridgingOptions = [.toolbars, .title]
            window.contentViewController = host
            window.orderFront(nil)
            host.view.layoutSubtreeIfNeeded()
        }

        var splitView: NSSplitView? {
            func find(in view: NSView) -> NSSplitView? {
                if let split = view as? NSSplitView, split.arrangedSubviews.count == 2 { return split }
                return view.subviews.lazy.compactMap { find(in: $0) }.first
            }
            return find(in: host.view)
        }

        func mouse(_ type: NSEvent.EventType, at point: NSPoint) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                             clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1))
        }

        func settle() async throws {
            host.view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(300))
            host.view.layoutSubtreeIfNeeded()
        }

        func close() {
            window.contentViewController = nil
            window.orderOut(nil)
        }
    }
}
