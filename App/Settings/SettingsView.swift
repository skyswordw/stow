import SwiftUI

/// The Settings window (#162): a fixed sidebar of every page, grouped by `SettingsCategory`, beside
/// one scrolling page. The window keeps its size when the page changes; a long page scrolls instead.
struct SettingsView: View {
    @State private var router = SettingsRouter.shared
    @AppStorage(SettingsKeys.appearance) private var appearance = "system"

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(router: router)
                .toolbar(removing: .sidebarToggle)
                // After the toolbar modifier: before it, the width was ignored (144 pt).
                .navigationSplitViewColumnWidth(SettingsLayout.sidebarWidth)
        } detail: {
            router.pane.content
                .accessibilityElement(children: .contain)
                .navigationTitle(router.pane.title)
        }
        .frame(width: SettingsLayout.width)
        .frame(minHeight: SettingsLayout.minHeight, maxHeight: .infinity)
        // Switching pages doesn't animate (DESIGN.md: view switches don't animate).
        .animation(nil, value: router.pane)
        .onAppear { SettingsAppearance.apply() }
        .onChange(of: appearance) { SettingsAppearance.apply() }
    }
}

enum SettingsLayout {
    static let sidebarWidth: CGFloat = 196
    /// Sidebar plus a 560-pt page: wide enough for the grouped forms in both languages.
    static let width: CGFloat = 756
    /// The window opens at its minimum: tall enough for File Types' list and buttons and for most
    /// pages without scrolling; people can make it taller.
    static let minHeight: CGFloat = 600
}

/// Every page, in `SettingsCategory` order; categories are separated by space, the way System
/// Settings groups its sidebar, so no group repeats the name of the only page in it.
private struct SettingsSidebar: View {
    let router: SettingsRouter

    /// A sidebar click can't leave nothing selected.
    private var selection: Binding<SettingsPane?> {
        Binding(get: { router.pane }, set: { if let pane = $0 { router.pane = pane } })
    }

    var body: some View {
        List(selection: selection) {
            ForEach(SettingsCategory.allCases) { category in
                Section {
                    ForEach(category.panes) { pane in
                        Label(pane.title, systemImage: pane.systemImage)
                            .tag(pane)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

enum SettingsAppearance {
    static func apply() {
        let override = UserDefaults.standard.string(forKey: "StowAppearance")
        let choice = override.flatMap(SettingsKeys.Appearance.init(rawValue:)) ?? SettingsKeys.appearance()
        NSApp.appearance = switch choice {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}
