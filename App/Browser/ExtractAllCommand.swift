import AppKit

/// File > Extract All follows the key archive window, including Glance and its text editors.
/// Settings, Tray and sheets must never extract from an archive behind them.
@Observable
final class ExtractAllCommand {
    static let shared = ExtractAllCommand()
    private(set) var target: BrowserModel?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private let currentWindow: () -> NSWindow?

    var isEnabled: Bool {
        target != nil && target?.extractAllUnavailableReason == nil
    }

    init(currentWindow: @escaping () -> NSWindow? = { NSApp.keyWindow }) {
        self.currentWindow = currentWindow
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                     NSWindow.willBeginSheetNotification, NSWindow.didEndSheetNotification,
                     NSWindow.didUpdateNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        refresh()
    }

    isolated deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    func refresh() {
        let next = Self.model(in: currentWindow())
        if target !== next { target = next }
    }

    static func model(in window: NSWindow?) -> BrowserModel? {
        guard let window, window.sheetParent == nil, window.attachedSheet == nil,
              NSApp.modalWindow == nil,
              let delegate = window.delegate as? EditingWindowDelegate,
              let model = delegate.model, model.editingWindow === window else { return nil }
        return model
    }

    func perform(in window: NSWindow?) {
        // Recheck both window ownership and availability: focus or activity can change after
        // the menu opens. Use the button's archive-wide path, never the selection's Extract.
        guard let model = Self.model(in: window), model.extractAllUnavailableReason == nil else { return }
        model.extractAll()
    }
}
