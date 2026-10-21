import AppKit

/// Which toolbar items give way first when the window is narrow. Extract All is the primary action
/// and never goes into the overflow menu; the view switcher, Tray, Glance and New Archive (also in the menu
/// bar) go first. SwiftUI has no priority of its own, so this sets AppKit's on the items it makes,
/// matched by their labels.
enum ToolbarPriority {
    private static var observed: Set<ObjectIdentifier> = []
    private static let first = String(localized: "Extract All")
    private static let last = [String(localized: "View"), String(localized: "Tray"), String(localized: "Glance"),
                                String(localized: "New Archive")]

    static func install(in window: NSWindow) {
        guard observed.insert(ObjectIdentifier(window)).inserted else { return }
        // The toolbar arrives after the window, and SwiftUI rebuilds its items (the inspector
        // toggling, another archive) without AppKit announcing them; a dozen label checks per update
        // keeps up with all of that.
        NotificationCenter.default.addObserver(forName: NSWindow.didUpdateNotification, object: window,
                                               queue: .main) { [weak window] _ in
            MainActor.assumeIsolated { window?.toolbar?.items.forEach(apply) }
        }
    }

    static func apply(_ item: NSToolbarItem) {
        let priority: NSToolbarItem.VisibilityPriority = item.label == first ? .high
            : last.contains(item.label) ? .low : .standard
        if item.visibilityPriority != priority, priority != .standard { item.visibilityPriority = priority }
    }
}
