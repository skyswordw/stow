import Foundation

/// The contextual actions offered for a selection — the right next step, already on screen.
nonisolated enum NextStep: Hashable, Identifiable, Sendable {
    case installFonts(count: Int)
    case moveToApplications
    case openInstaller
    case openInside
    case quickLook
    case extract

    var id: Self { self }

    var title: String {
        switch self {
        case .installFonts(let count): count == 1 ? "Install Font" : "Install \(count) Fonts"
        case .moveToApplications: "Move to Applications"
        case .openInstaller: "Open Installer"
        case .openInside: "Open Inside"
        case .quickLook: "Quick Look"
        case .extract: "Extract"
        }
    }

    var symbol: String {
        switch self {
        case .installFonts: "textformat"
        case .moveToApplications: "square.and.arrow.down.on.square"
        case .openInstaller: "shippingbox"
        case .openInside: "rectangle.stack"
        case .quickLook: "eye"
        case .extract: "arrow.down.to.line"
        }
    }

    /// Verb used in the progress capsule while the step runs.
    var progressTitle: String {
        switch self {
        case .installFonts: "Installing"
        case .moveToApplications: "Moving"
        case .openInstaller, .openInside, .quickLook: "Opening"
        case .extract: "Extracting"
        }
    }

    var doneTitle: String {
        switch self {
        case .installFonts(let count): count == 1 ? "Font installed" : "\(count) fonts installed"
        case .moveToApplications: "Moved to Applications"
        case .openInstaller, .openInside, .quickLook: "Opened"
        case .extract: "Extracted to Downloads"
        }
    }

    /// At most two suggestions, then Extract. Specific beats generic.
    static func suggestions(for entries: [ArchiveEntry]) -> [NextStep] {
        guard !entries.isEmpty else { return [] }
        let kinds = entries.map(\.kind)
        var steps: [NextStep] = []

        if kinds.allSatisfy({ $0 == .font }) {
            steps.append(.installFonts(count: entries.count))
        } else if entries.count == 1 {
            switch kinds[0] {
            case .app: steps.append(.moveToApplications)
            case .installer: steps.append(.openInstaller)
            case .archive: steps.append(.openInside)
            default: break
            }
        }
        if kinds.contains(where: \.isPreviewable) {
            steps.append(.quickLook)
        }
        return Array(steps.prefix(2)) + [.extract]
    }
}
