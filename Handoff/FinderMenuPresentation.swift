import AppKit

/// Finder synchronously asks for a menu on either its XPC queue or the main thread.
/// AppKit objects are created on main, then handed back to Finder's callback.
nonisolated enum FinderMenuPresentation {
    private struct MenuBox: @unchecked Sendable {
        let menu: NSMenu
    }

    static func makeMenu(actions: [HandoffAction], selectors: [Selector]) -> NSMenu {
        let build: @MainActor @Sendable () -> MenuBox = {
            let menu = NSMenu(title: "Stow")
            for (action, selector) in zip(actions, selectors) {
                let item = NSMenuItem(title: FinderMenu.title(for: action), action: selector, keyEquivalent: "")
                item.image = NSImage(systemSymbolName: FinderMenu.symbol(for: action), accessibilityDescription: nil)
                menu.addItem(item)
            }
            return MenuBox(menu: menu)
        }
        if Thread.isMainThread { return MainActor.assumeIsolated(build).menu }
        return DispatchQueue.main.sync { MainActor.assumeIsolated(build) }.menu
    }
}
