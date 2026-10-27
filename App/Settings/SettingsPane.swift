import SwiftUI

/// Task-oriented Settings groups for #162. Claude Code may restyle navigation around this map;
/// `SettingsPane` raw values and deep links stay stable.
nonisolated enum SettingsCategory: String, CaseIterable, Identifiable, Sendable {
    case general, archiveWork, interaction, security, systemIntegration, advanced

    var id: Self { self }

    /// Proposal titles for a sidebar; Claude may revise wording. Keep English source keys stable once shipped.
    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .archiveWork: String(localized: "Archive Work")
        case .interaction: String(localized: "Interaction")
        case .security: String(localized: "Security")
        case .systemIntegration: String(localized: "System Integration")
        case .advanced: String(localized: "Advanced")
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .archiveWork: "shippingbox"
        case .interaction: "capsule.on.rectangle"
        case .security: "lock"
        case .systemIntegration: "puzzlepiece.extension"
        case .advanced: "slider.horizontal.3"
        }
    }

    /// Panes shown under this category, in toolbar / sidebar order.
    var panes: [SettingsPane] {
        switch self {
        case .general: [.general]
        case .archiveWork: [.extraction, .installing, .packing]
        case .interaction: [.nextSteps, .previews]
        case .security: [.passwords]
        case .systemIntegration: [.fileTypes, .integration]
        case .advanced: [.advanced, .licenses]
        }
    }
}

nonisolated enum SettingsPane: String, CaseIterable, Identifiable {
    case general, extraction, installing, packing, nextSteps, previews, passwords, fileTypes, integration, advanced, licenses
    var id: Self { self }

    /// Category that hosts this pane in the #162 information map.
    var category: SettingsCategory {
        switch self {
        case .general: .general
        case .extraction, .installing, .packing: .archiveWork
        case .nextSteps, .previews: .interaction
        case .passwords: .security
        case .fileTypes, .integration: .systemIntegration
        case .advanced, .licenses: .advanced
        }
    }

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .extraction: String(localized: "Extraction")
        case .installing: String(localized: "Installing")
        case .packing: String(localized: "Packing")
        case .nextSteps: String(localized: "Actions")
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
        case .nextSteps: "capsule.on.rectangle"
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
        case .general: 700
        case .passwords: 560
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
        case .nextSteps: NextStepsSettingsView()
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

    /// Deep-link helper used by Welcome, Actions › Customize, demo scenes, and Integration.
    func show(_ pane: SettingsPane) {
        self.pane = pane
        open()
    }

    func show(rawValue: String?) {
        show(rawValue.flatMap(SettingsPane.init(rawValue:)) ?? .general)
    }

    var category: SettingsCategory { pane.category }
}
