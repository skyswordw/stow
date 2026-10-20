import Foundation

/// The contextual actions offered for a selection — the right next step, already on screen.
nonisolated enum NextStep: Hashable, Identifiable, Sendable {
    case installFonts(count: Int)
    case moveToApplications
    case openInstaller
    /// A disk image's "drag here" shortcut for something that isn't an app (plug-ins, screen savers…).
    case copyTo(folder: String)
    case openInside
    case quickLook
    case extract

    var id: Self { self }

    var title: String {
        switch self {
        case .installFonts(let count): count == 1 ? "Install Font" : "Install \(count) Fonts"
        case .moveToApplications: "Install App"
        case .openInstaller: "Open Installer"
        case .copyTo(let folder): "Copy to “\((folder as NSString).lastPathComponent)”"
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
        case .copyTo: "folder.badge.plus"
        case .openInside: "rectangle.stack"
        case .quickLook: "eye"
        case .extract: "arrow.down.to.line"
        }
    }

    /// Verb used in the progress capsule while the step runs.
    var progressTitle: String {
        switch self {
        case .installFonts: "Installing"
        case .moveToApplications: "Installing"
        case .copyTo: "Copying"
        case .openInstaller, .openInside, .quickLook: "Opening"
        case .extract: "Extracting"
        }
    }

    var doneTitle: String {
        switch self {
        case .installFonts(let count): count == 1 ? "Font installed" : "\(count) fonts installed"
        case .moveToApplications: "Installed in Applications"
        case .copyTo(let folder): "Copied to \(FileManager.default.displayName(atPath: folder))"
        case .openInstaller: "Opened in Installer"
        case .openInside, .quickLook: "Opened"
        case .extract: "Extracted to Downloads"
        }
    }

    /// At most two suggestions, then Extract. Specific beats generic. `dropTargets` are a disk
    /// image's "drag here" shortcuts (`DiskImageLayout`).
    static func suggestions(for entries: [ArchiveEntry], dropTargets: [DiskImageLayout.DropTarget] = []) -> [NextStep] {
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
            default:
                if let target = dropTargets.first(where: { $0.folder != "/Applications" }) {
                    steps.append(.copyTo(folder: target.folder))
                }
            }
        }
        if kinds.contains(where: \.isPreviewable) {
            steps.append(.quickLook)
        }
        return Array(steps.prefix(2)) + [.extract]
    }
}
