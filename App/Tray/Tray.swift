import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TrayItem: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var size: Int64
    var url: URL?

    var contentType: UTType {
        UTType(filenameExtension: (name as NSString).pathExtension) ?? .data
    }
}

/// A floating shelf at the screen edge that collects files from anywhere.
/// It enters and leaves along the same edge.
@Observable
final class TrayController {
    var items: [TrayItem] = []
    private(set) var isShown = false
    private var panel: NSPanel?
    weak var app: AppState?

    private let size = CGSize(width: 288, height: 420)

    func toggle() { isShown ? hide() : show() }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        guard let screen = NSScreen.main?.visibleFrame else { return }
        let final = CGRect(x: screen.maxX - size.width - 16,
                           y: screen.midY - size.height / 2,
                           width: size.width, height: size.height)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.setFrame(reduceMotion ? final : final.offsetBy(dx: 24, dy: 0), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        isShown = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1) // strong ease-out
            panel.animator().setFrame(final, display: true)
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel else { return }
        isShown = false
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18 // leaving is faster than arriving
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
            if !reduceMotion { panel.animator().setFrame(panel.frame.offsetBy(dx: 24, dy: 0), display: true) }
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
        }
    }

    func add(_ urls: [URL]) {
        let existing = Set(items.compactMap(\.url))
        items += urls.filter { !existing.contains($0) }.map {
            TrayItem(name: $0.lastPathComponent, size: $0.fileSize, url: $0)
        }
    }

    func remove(_ item: TrayItem) {
        items.removeAll { $0.id == item.id }
    }

    private func makePanel() -> NSPanel {
        let panel = TrayPanel(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: true)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        let host = NSHostingView(rootView: TrayView(tray: self).environment(app ?? AppState()))
        host.sizingOptions = []
        panel.contentView = host
        return panel
    }
}

private final class TrayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

struct TrayView: View {
    let tray: TrayController
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                if tray.items.isEmpty { empty } else { list }
            }
            .frame(maxHeight: .infinity)
            if !tray.items.isEmpty { footer }
        }
        .frame(width: 288, height: 420)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(.tint, lineWidth: 2)
                .opacity(isTargeted ? 1 : 0)
        }
        .dropDestination(for: URL.self) { urls, _ in
            tray.add(urls)
            return true
        } isTargeted: { isTargeted = $0 }
        .animation(Motion.resolved(Motion.target, reduceMotion: reduceMotion), value: isTargeted)
    }

    private var header: some View {
        HStack {
            Text("Tray").font(.headline)
            if !tray.items.isEmpty {
                Text("\(tray.items.count)")
                    .font(.caption.weight(.semibold))
                    .liveNumber()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.tint.opacity(0.15), in: .capsule)
                    .foregroundStyle(.tint)
            }
            Spacer()
            Button("Close", systemImage: "xmark") { tray.hide() }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, Space.l)
        .padding(.top, Space.l)
        .padding(.bottom, Space.s)
    }

    private var empty: some View {
        VStack(spacing: Space.s) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
            Text("Drop files here to gather them")
                .font(.callout.weight(.medium))
            Text("Collect from different folders, then pack or drag them out together.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: Radius.panel)
                .strokeBorder(.separator, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                .padding(Space.m)
        }
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: Space.xs) {
                ForEach(tray.items) { item in
                    TrayRow(item: item) { tray.remove(item) }
                }
            }
            .padding(.horizontal, Space.s)
        }
    }

    private var footer: some View {
        HStack(spacing: Space.s) {
            Text(tray.items.reduce(Int64(0)) { $0 + $1.size }.bytes)
                .font(.caption)
                .foregroundStyle(.secondary)
                .liveNumber()
            Spacer()
            Button("Clear") { tray.items.removeAll() }
                .buttonStyle(.glass)
            Button("Pack", systemImage: "archivebox") {
                app.packRequest = PackRequest(files: tray.items.map { PackFile(path: $0.name, size: $0.size) })
                NSApp.activate()
            }
            .buttonStyle(.glassProminent)
        }
        .controlSize(.large)
        .padding(Space.m)
    }
}

private struct TrayRow: View {
    let item: TrayItem
    let onRemove: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: Space.s) {
            NativeIcon(type: item.contentType)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.name).font(.callout).lineLimit(1).truncationMode(.middle)
                Text(item.size.bytes).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer(minLength: 0)
            Button("Remove", systemImage: "minus.circle.fill", action: onRemove)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .opacity(isHovering ? 1 : 0)
        }
        .padding(Space.s)
        .background(.primary.opacity(isHovering ? 0.06 : 0), in: .rect(cornerRadius: Radius.card))
        .contentShape(.rect)
        .onHover { isHovering = $0 }
        .modifier(DragOut(url: item.url))
    }
}

/// Only real files can be dragged out; sample items stay put.
private struct DragOut: ViewModifier {
    let url: URL?

    func body(content: Content) -> some View {
        if let url { content.draggable(url) } else { content }
    }
}
