import SwiftUI

/// Task-oriented Settings groups for #162: the sidebar shows each category's panes as one group,
/// separated by space rather than headings. `SettingsPane` raw values and deep links stay stable.
nonisolated enum SettingsCategory: String, CaseIterable, Identifiable, Sendable {
    case general, archiveWork, interaction, security, systemIntegration, advanced

    var id: Self { self }

    /// Names for the groups (accessibility, tests, future use); the sidebar itself separates them by space.
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
        case .interaction: [.nextSteps, .glance, .previews]
        case .security: [.passwords]
        case .systemIntegration: [.fileTypes, .integration]
        case .advanced: [.advanced, .licenses]
        }
    }
}

nonisolated enum SettingsPane: String, CaseIterable, Identifiable {
    case general, extraction, installing, packing, nextSteps, glance, previews, passwords, fileTypes, integration, advanced, licenses
    var id: Self { self }

    /// Category that hosts this pane in the #162 information map.
    var category: SettingsCategory {
        switch self {
        case .general: .general
        case .extraction, .installing, .packing: .archiveWork
        case .nextSteps, .glance, .previews: .interaction
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
        case .glance: String(localized: "Glance")
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
        case .glance: "macwindow"
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
        case .nextSteps: NextStepsSettingsView()
        case .glance: GlanceSettingsView()
        case .previews: PreviewSettingsView()
        case .passwords: PasswordSettingsView()
        case .fileTypes: AssociationsView(model: Associations(), showsTitle: false)
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
