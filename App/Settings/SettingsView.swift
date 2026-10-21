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
        .frame(width: 720, height: router.pane == .fileTypes ? 620 : router.pane == .integration ? 560 : 460)
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
