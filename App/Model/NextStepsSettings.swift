import Foundation
import SwiftUI

nonisolated extension NextStep {
    /// A step without its details: what Settings › Next Steps shows or hides.
    /// The order is the capsule's: specific steps first, Extract last.
    enum Kind: String, CaseIterable, Identifiable, Sendable {
        case installFonts, moveToApplications, openInstaller, copyTo, openInside, quickLook, pack, extract

        var id: Self { self }

        var title: String {
            switch self {
            case .installFonts: String(localized: "Install Fonts")
            case .moveToApplications: String(localized: "Install App")
            case .openInstaller: String(localized: "Open Installer")
            case .copyTo: String(localized: "Copy to Folder")
            case .openInside: String(localized: "Open Inside")
            case .quickLook: String(localized: "Quick Look")
            case .pack: String(localized: "Pack")
            case .extract: String(localized: "Extract")
            }
        }

        /// When the step is offered, in a few plain words.
        var when: String {
            switch self {
            case .installFonts: String(localized: "When everything selected is a font")
            case .moveToApplications: String(localized: "When an app is selected, or the archive holds one app")
            case .openInstaller: String(localized: "When an installer package is selected")
            case .copyTo: String(localized: "When a disk image says where an item goes")
            case .openInside: String(localized: "When an archive is selected")
            case .quickLook: String(localized: "When something can be previewed")
            case .pack: String(localized: "For any selection: pack it into a new archive")
            case .extract: String(localized: "For any selection: the main button")
            }
        }

        var symbol: String {
            switch self {
            case .installFonts: NextStep.installFonts(count: 2).symbol
            case .moveToApplications: NextStep.moveToApplications.symbol
            case .openInstaller: NextStep.openInstaller.symbol
            case .copyTo: NextStep.copyTo(folder: "").symbol
            case .openInside: NextStep.openInside.symbol
            case .quickLook: NextStep.quickLook.symbol
            case .pack: NextStep.pack.symbol
            case .extract: NextStep.extract.symbol
            }
        }
    }

    var kind: Kind {
        switch self {
        case .installFonts: .installFonts
        case .moveToApplications: .moveToApplications
        case .openInstaller: .openInstaller
        case .copyTo: .copyTo
        case .openInside: .openInside
        case .quickLook: .quickLook
        case .pack: .pack
        case .extract: .extract
        }
    }

    /// The shortcut the menu bar gives the same command, so the More menu shows the same keys.
    var menuShortcut: KeyboardShortcut? {
        switch self {
        case .extract: KeyboardShortcut("e")                    // File › Extract
        case .quickLook: KeyboardShortcut("y")                  // Go › Quick Look
        case .openInside: KeyboardShortcut(.downArrow)          // Go › Open
        default: nil
        }
    }

    /// Every step that applies to `entries`, specific ones first and Extract last.
    static func applicable(for entries: [ArchiveEntry], dropTargets: [DiskImageLayout.DropTarget] = []) -> [NextStep] {
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
        return steps + [.pack, .extract]
    }
}

/// What Next Steps shows: whether it appears at all, and which steps it suggests.
/// Hidden steps are never gone — they wait in the capsule's More menu.
nonisolated struct NextStepsSettings: Equatable, Sendable {
    var isShown = true
    var hidden: Set<NextStep.Kind> = Self.defaultHidden

    /// Pack is there for whoever wants it; most selections are better served by fewer buttons.
    static let defaultHidden: Set<NextStep.Kind> = [.pack]
    static let defaults = NextStepsSettings()
    /// Beside the main button, so the capsule stays one glance wide.
    static let maxSuggestions = 2

    var isDefault: Bool { self == Self.defaults }

    func shows(_ kind: NextStep.Kind) -> Bool { !hidden.contains(kind) }

    mutating func set(_ kind: NextStep.Kind, shown: Bool) {
        if shown { hidden.remove(kind) } else { hidden.insert(kind) }
    }

    /// How the capsule lays out a selection's steps.
    struct Layout: Equatable {
        /// Glass buttons before the main one, most specific first.
        var suggestions: [NextStep] = []
        /// The amber button: Extract, or the first shown step when Extract is hidden.
        var primary: NextStep?
        /// Everything else that applies — hidden steps included — for the More menu.
        var alternatives: [NextStep] = []

        /// The stack's front button: installing, when the selection is something to install (an
        /// app, fonts, an installer package), otherwise the main button. Never runs by itself; it
        /// takes a click like every other action.
        var front: NextStep? { suggestions.first(where: \.isInstall) ?? primary }

        /// The shown steps behind the front one, nearest first: the order they fan out above it.
        var behind: [NextStep] { (suggestions + [primary].compactMap(\.self)).filter { $0 != front } }

        /// More (⋯): every action but the front one, so the menu alone reaches all of them.
        var more: [NextStep] { behind + alternatives }
    }

    func layout(for entries: [ArchiveEntry], dropTargets: [DiskImageLayout.DropTarget] = []) -> Layout {
        let all = NextStep.applicable(for: entries, dropTargets: dropTargets)
        let shown = all.filter { shows($0.kind) }
        let primary = shown.contains(.extract) ? .extract : shown.first
        let suggestions = Array(shown.filter { $0 != primary }.prefix(Self.maxSuggestions))
        let onCapsule = Set(suggestions + [primary].compactMap(\.self))
        return Layout(suggestions: suggestions, primary: primary, alternatives: all.filter { !onCapsule.contains($0) })
    }

    /// With nothing selected, the steps for the archive itself: installing it, when it's one app
    /// (`Archive.installable`), as ArcZip offers. Nothing else, since Extract All has its own button,
    /// and nothing for an installer package yet. A hidden Install App leaves the stack empty and
    /// waits in File › Actions, like a selection's hidden steps. It takes a click, as always.
    func archiveLayout(installable: ArchiveEntry?) -> Layout {
        guard let installable, installable.kind == .app else { return Layout() }
        return shows(.moveToApplications) ? Layout(primary: .moveToApplications)
            : Layout(alternatives: [.moveToApplications])
    }

    // MARK: - Stored in UserDefaults

    static func load(from store: UserDefaults = .standard) -> NextStepsSettings {
        NextStepsSettings(isShown: SettingsKeys.flag(SettingsKeys.nextStepsShown, in: store),
                          hidden: decode(store.string(forKey: SettingsKeys.nextStepsHidden)))
    }

    func save(to store: UserDefaults = .standard) {
        store.set(isShown, forKey: SettingsKeys.nextStepsShown)
        store.set(Self.encode(hidden), forKey: SettingsKeys.nextStepsHidden)
    }

    /// Restore Defaults: Next Steps shows again with its usual suggestions.
    static func restoreDefaults(in store: UserDefaults = .standard) {
        SettingsKeys.reset(.pane(.nextSteps), in: store)
    }

    /// Comma-separated kinds, in Settings order. Unknown names (from a newer Stow) are ignored.
    static func encode(_ hidden: Set<NextStep.Kind>) -> String {
        NextStep.Kind.allCases.filter(hidden.contains).map(\.rawValue).joined(separator: ",")
    }

    /// Nothing stored means the defaults; an empty string means everything is shown.
    static func decode(_ stored: String?) -> Set<NextStep.Kind> {
        guard let stored else { return defaultHidden }
        return Set(stored.split(separator: ",").compactMap { NextStep.Kind(rawValue: String($0)) })
    }
}
