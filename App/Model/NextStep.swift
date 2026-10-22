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
    /// The selection, packed into a new archive with the Pack sentence.
    case pack
    case extract

    var id: Self { self }

    var title: String {
        switch self {
        case .installFonts(let count): count == 1 ? String(localized: "Install Font") : String(localized: "Install \(count) Fonts")
        case .moveToApplications: String(localized: "Install App")
        case .openInstaller: String(localized: "Open Installer")
        case .copyTo(let folder): String(localized: "Copy to “\((folder as NSString).lastPathComponent)”")
        case .openInside: String(localized: "Open Inside")
        case .quickLook: String(localized: "Quick Look")
        case .pack: String(localized: "Pack…")
        case .extract: String(localized: "Extract")
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
        case .pack: "archivebox"
        case .extract: "arrow.down.to.line"
        }
    }

    /// What a failure says Stow couldn't do.
    var failureOperation: Failure.Operation {
        switch self {
        case .installFonts, .moveToApplications, .openInstaller: .install
        case .copyTo: .copy
        case .openInside, .quickLook: .open
        case .pack: .pack
        case .extract: .extract
        }
    }

    /// Verb used in the progress capsule while the step runs.
    var progressTitle: String {
        switch self {
        case .installFonts: String(localized: "Installing")
        case .moveToApplications: String(localized: "Installing")
        case .copyTo: String(localized: "Copying")
        case .openInstaller, .openInside, .quickLook: String(localized: "Opening")
        case .pack: String(localized: "Preparing")
        case .extract: String(localized: "Extracting")
        }
    }

    var doneTitle: String {
        switch self {
        case .installFonts(let count): count == 1 ? String(localized: "Font installed") : String(localized: "\(count) fonts installed")
        case .moveToApplications: String(localized: "Installed in Applications")
        case .copyTo(let folder): String(localized: "Copied to \(FileManager.default.displayName(atPath: folder))")
        case .openInstaller: String(localized: "Opened in Installer")
        case .openInside, .quickLook: String(localized: "Opened")
        case .pack: String(localized: "Ready to pack")
        case .extract: String(localized: "Extracted to Downloads")
        }
    }

    /// At most two suggestions, then Extract. Specific beats generic. `dropTargets` are a disk
    /// image's "drag here" shortcuts (`DiskImageLayout`). Next Steps itself lays out
    /// `NextStepsSettings.layout(for:)`, which also offers Pack and honours Settings.
    static func suggestions(for entries: [ArchiveEntry], dropTargets: [DiskImageLayout.DropTarget] = []) -> [NextStep] {
        let steps = applicable(for: entries, dropTargets: dropTargets).filter { $0 != .pack && $0 != .extract }
        return entries.isEmpty ? [] : Array(steps.prefix(2)) + [.extract]
    }
}
