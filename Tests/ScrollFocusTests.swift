import AppKit
import SwiftUI
import Testing
@testable import Stow

@MainActor
@Suite("Scrolling keyboard focus", .serialized)
struct ScrollFocusTests {
    @Test func packWindowFollowsItsMeasuredContentInsteadOfClippingTheFooter() async throws {
        let draft = ArchiveDraft()
        var options = PackOptions()
        options.setCustomFormat(.sevenZip)
        options.usesPassword = true
        draft.configuration = .init(options: options, name: "Focus", overrides: [:])
        let window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 580, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let measurement = State()
        let host = NSHostingController(rootView: PackSheet(
            request: PackRequest(files: SampleArchive.packCandidates), draft: draft).environment(AppState())
            .onGeometryChange(for: CGSize.self, of: \.size) { measurement.measuredSize = $0 })
        // Reproduce an already-created sheet retaining its first frame while the form grows.
        host.sizingOptions = []
        window.contentViewController = host
        defer { window.contentViewController = nil; window.close(); draft.close() }
        for _ in 0..<15 {
            host.view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(30))
        }
        #expect(host.view.frame.height > 300)
        let actualHeight = host.view.frame.height
        let fittedHeight = measurement.measuredSize.height
        #expect(abs(actualHeight - fittedHeight) < 1)
        let settledSize = window.frame.size
        for _ in 0..<10 {
            host.view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(30))
        }
        #expect(window.frame.size == settledSize, "Content measurement must not create a resize loop")
    }

    @Test func offscreenFieldsAreRevealedInBothDirectionsWithoutLosingTyping() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        try await fixture.settle()
        #expect(try #require(fixture.state.frames[9]).minY > Fixture.height)

        fixture.state.requested = 9
        try await fixture.settle()
        try fixture.expectVisible(9)
        let editor = try #require(fixture.window.firstResponder as? NSTextView)
        editor.insertText("last", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(fixture.state.text[9] == "last")

        fixture.state.requested = 0
        try await fixture.settle()
        try fixture.expectVisible(0)
        let first = try #require(fixture.window.firstResponder as? NSTextView)
        first.insertText("first", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(fixture.state.text[0] == "first")
        #expect(fixture.state.text[9] == "last")
    }

    @Test func visibleFocusDoesNotMoveTheScrollPosition() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        try await fixture.settle()
        fixture.state.requested = 4
        try await fixture.settle()
        try fixture.expectVisible(4)
        let before = try #require(fixture.state.frames[4])
        fixture.state.requested = 5
        try await fixture.settle()
        try fixture.expectVisible(5)
        #expect(abs(try #require(fixture.state.frames[4]).minY - before.minY) < 1)
    }

    @Observable final class State {
        var measuredSize = CGSize.zero
        var requested: Int?
        var text = Array(repeating: "", count: 10)
        var frames: [Int: CGRect] = [:]
    }

    private struct Form: View {
        @Bindable var state: State
        @FocusState private var focused: Int?

        var body: some View {
            ScrollView {
                VStack(spacing: 20) {
                    ForEach(0..<10, id: \.self) { index in
                        TextField("Field \(index)", text: $state.text[index])
                            .textFieldStyle(.roundedBorder)
                            .focused($focused, equals: index)
                            .revealsKeyboardFocus(focused == index)
                            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named("viewport")) }) {
                                state.frames[index] = $0
                            }
                    }
                }
                .padding(24)
            }
            .followsKeyboardFocus(margin: 20)
            .coordinateSpace(name: "viewport")
            .frame(width: 300, height: Fixture.height)
            .onChange(of: state.requested) { _, value in focused = value }
        }
    }

    private final class Fixture {
        static let height: CGFloat = 180
        let state = State()
        let window: NSWindow
        init() {
            window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 300, height: Self.height),
                              styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: Form(state: state))
            window.contentView?.layoutSubtreeIfNeeded()
        }

        func settle() async throws {
            for _ in 0..<8 {
                window.contentView?.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(30))
            }
        }

        func expectVisible(_ index: Int) throws {
            let frame = try #require(state.frames[index])
            #expect(frame.minY >= 19)
            #expect(frame.maxY <= Self.height - 19)
        }

        func close() { window.contentViewController = nil; window.close() }
    }
}
