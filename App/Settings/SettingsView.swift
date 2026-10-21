import SwiftUI

struct SettingsView: View {
    @State private var router = SettingsRouter.shared
    @AppStorage(SettingsKeys.appearance) private var appearance = "system"
    var body: some View {
        TabView(selection: $router.pane) {
            ForEach(SettingsPane.allCases) { pane in
                pane.content
                    .tabItem { Label(pane.title, systemImage: pane.systemImage) }
                    .tag(pane)
            }
        }
        .frame(minWidth: 720)
        .frame(height: router.pane.fixedHeight)
        // Switching panes resizes the window without animation (DESIGN.md: view switches don't animate).
        .animation(nil, value: router.pane)
        .onAppear { SettingsAppearance.apply() }
        .onChange(of: appearance) { SettingsAppearance.apply() }
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
