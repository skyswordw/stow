import SwiftUI

nonisolated enum SettingsPane: String, CaseIterable, Identifiable {
    case general, extraction, installing, packing, previews, passwords, fileTypes, integration, advanced, licenses
    var id: Self { self }
    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .extraction: String(localized: "Extraction")
        case .installing: String(localized: "Installing")
        case .packing: String(localized: "Packing")
        case .previews: String(localized: "Previews")
        case .passwords: String(localized: "Passwords")
        case .fileTypes: String(localized: "File Types")
        case .integration: String(localized: "Integration")
        case .advanced: String(localized: "Advanced")
        case .licenses: String(localized: "Licenses")
        }
    }
    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .extraction: "archivebox"
        case .installing: "square.and.arrow.down"
        case .packing: "shippingbox"
        case .previews: "eye"
        case .passwords: "lock"
        case .fileTypes: "doc.on.doc"
        case .integration: "puzzlepiece.extension"
        case .advanced: "slider.horizontal.3"
        case .licenses: "doc.text"
        }
    }
    /// `nil` lets short panes size the window to their content.
    var fixedHeight: CGFloat? {
        switch self {
        case .fileTypes: 620
        case .licenses: 560
        default: nil
        }
    }
    @MainActor @ViewBuilder var content: some View {
        switch self {
        case .general: GeneralSettingsView()
        case .extraction: ExtractionOptionsView()
        case .installing: InstallOptionsView()
        case .packing: PackingSettingsView()
        case .previews: PreviewSettingsView()
        case .passwords: PasswordSettingsView()
        case .fileTypes: AssociationsView(model: Associations())
        case .integration: IntegrationView()
        case .advanced: AdvancedSettingsView()
        case .licenses: LicensesView()
        }
    }
}

@Observable
final class SettingsRouter {
    static let shared = SettingsRouter()
    var pane: SettingsPane = .general
    var open: () -> Void = {}
}
