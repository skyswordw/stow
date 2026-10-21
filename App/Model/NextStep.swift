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
        case .installFonts(let count): count == 1 ? String(localized: "Install Font") : String(localized: "Install \(count) Fonts")
        case .moveToApplications: String(localized: "Install App")
        case .openInstaller: String(localized: "Open Installer")
        case .copyTo(let folder): String(localized: "Copy to “\((folder as NSString).lastPathComponent)”")
        case .openInside: String(localized: "Open Inside")
        case .quickLook: String(localized: "Quick Look")
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
        case .extract: "arrow.down.to.line"
        }
    }

    /// What a failure says Stow couldn't do.
    var failureOperation: Failure.Operation {
        switch self {
        case .installFonts, .moveToApplications, .openInstaller: .install
        case .copyTo: .copy
        case .openInside, .quickLook: .open
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
        case .extract: String(localized: "Extracted to Downloads")
        }
    }

    /// The kinds of suggestion people can turn off (Settings › General › Next Steps, or "Don't
    /// Suggest" on the button). Extract is always there.
    enum Kind: String, CaseIterable, Identifiable, Sendable {
        case installFonts, installApp, openInstaller, copyTo, openInside, quickLook
        var id: Self { self }

        var title: String {
            switch self {
            case .installFonts: String(localized: "Install Fonts")
            case .installApp: String(localized: "Install App")
            case .openInstaller: String(localized: "Open Installer")
            case .copyTo: String(localized: "Copy to a Disk Image’s Folder")
            case .openInside: String(localized: "Open Inside")
            case .quickLook: String(localized: "Quick Look")
            }
        }
    }

    var kind: Kind? {
        switch self {
        case .installFonts: .installFonts
        case .moveToApplications: .installApp
        case .openInstaller: .openInstaller
        case .copyTo: .copyTo
        case .openInside: .openInside
        case .quickLook: .quickLook
        case .extract: nil
        }
    }

    /// Every step that fits the selection, most specific first, Extract left out. `dropTargets`
    /// are a disk image's "drag here" shortcuts (`DiskImageLayout`).
    static func available(for entries: [ArchiveEntry], dropTargets: [DiskImageLayout.DropTarget] = []) -> [NextStep] {
        guard !entries.isEmpty else { return [] }
        let kinds = entries.map(\.kind)
        var steps: [NextStep] = []
        // Applications is left out: apps have Install App for that.
        let targets = dropTargets.filter { $0.folder != "/Applications" }

        if kinds.allSatisfy({ $0 == .font }) {
            steps.append(.installFonts(count: entries.count))
        } else if entries.count == 1 {
            switch kinds[0] {
            case .app: steps.append(.moveToApplications)
            case .installer: steps.append(.openInstaller)
            case .archive: steps.append(.openInside)
            default:
                if let target = targets.first { steps.append(.copyTo(folder: target.folder)) }
            }
        }
        if kinds.contains(where: \.isPreviewable) {
            steps.append(.quickLook)
        }
        // The rest only show in More: the other "drag here" folders.
        if entries.count == 1, kinds[0] != .app, kinds[0] != .installer, kinds[0] != .font {
            for target in targets where !steps.contains(.copyTo(folder: target.folder)) {
                steps.append(.copyTo(folder: target.folder))
            }
        }
        return steps
    }

    /// At most two suggestions, then Extract. Specific beats generic; kinds in `hidden` are left
    /// for the More menu (`alternatives`).
    static func suggestions(for entries: [ArchiveEntry], dropTargets: [DiskImageLayout.DropTarget] = [],
                            hidden: Set<Kind> = []) -> [NextStep] {
        guard !entries.isEmpty else { return [] }
        let shown = available(for: entries, dropTargets: dropTargets).filter { step in step.kind.map { !hidden.contains($0) } ?? true }
        return Array(shown.prefix(2)) + [.extract]
    }

    /// The steps that fit but aren't on the bar: past the first two, or turned off.
    static func alternatives(for entries: [ArchiveEntry], dropTargets: [DiskImageLayout.DropTarget] = [],
                             hidden: Set<Kind> = []) -> [NextStep] {
        let shown = Set(suggestions(for: entries, dropTargets: dropTargets, hidden: hidden))
        return available(for: entries, dropTargets: dropTargets).filter { !shown.contains($0) }
    }
}

/// Which suggestions people turned off. Stored as a comma-separated list so Reset All clears it.
nonisolated enum NextStepPreferences {
    static let key = "nextSteps.hidden"

    static func hidden(in store: UserDefaults = .standard) -> Set<NextStep.Kind> {
        parse(store.string(forKey: key) ?? "")
    }

    static func parse(_ text: String) -> Set<NextStep.Kind> {
        Set(text.split(separator: ",").compactMap { NextStep.Kind(rawValue: String($0)) })
    }

    static func encode(_ kinds: Set<NextStep.Kind>) -> String {
        NextStep.Kind.allCases.filter(kinds.contains).map(\.rawValue).joined(separator: ",")
    }

    static func setHidden(_ kind: NextStep.Kind, _ isHidden: Bool, in store: UserDefaults = .standard) {
        var kinds = hidden(in: store)
        if isHidden { kinds.insert(kind) } else { kinds.remove(kind) }
        store.set(encode(kinds), forKey: key)
    }

    /// Restore Suggestions: every kind shows again.
    static func restore(in store: UserDefaults = .standard) {
        store.removeObject(forKey: key)
    }
}
