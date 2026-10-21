import SwiftUI

nonisolated enum SettingsPane: String, CaseIterable, Identifiable {
    case general, extraction, installing, packing, previews, passwords, fileTypes, integration, advanced, licenses
    var id: Self { self }
    var title: String {
        switch self {
        case .general: "General"
        case .extraction: "Extraction"
        case .installing: "Installing"
        case .packing: "Packing"
        case .previews: "Previews"
        case .passwords: "Passwords"
        case .fileTypes: "File Types"
        case .integration: "Integration"
        case .advanced: "Advanced"
        case .licenses: "Licenses"
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
