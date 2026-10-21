import AppKit
import UniformTypeIdentifiers

/// Which app opens a file type on double-click. Behind a protocol so the logic is testable without
/// changing the Mac's real defaults.
protocol DefaultAppRegistry {
    func defaultApp(for type: UTType) -> URL?
    func setDefaultApp(_ app: URL, for type: UTType) async throws
    func app(withBundleIdentifier identifier: String) -> URL?
    func bundleIdentifier(of app: URL) -> String?
}

struct LaunchServicesRegistry: DefaultAppRegistry {
    func defaultApp(for type: UTType) -> URL? {
        NSWorkspace.shared.urlForApplication(toOpen: type)
    }

    func setDefaultApp(_ app: URL, for type: UTType) async throws {
        try await NSWorkspace.shared.setDefaultApplication(at: app, toOpen: type)
    }

    func app(withBundleIdentifier identifier: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
    }

    func bundleIdentifier(of app: URL) -> String? {
        Bundle(url: app)?.bundleIdentifier
    }
}

/// File Types: choose which archive types open with Stow, remember the app each used before,
/// switch back, and say what actually happened — macOS can ask people to confirm, and they can
/// say no.
@Observable
final class Associations {
    struct Row: Identifiable {
        let type: ArchiveType
        var app: URL?
        var opensWithStow: Bool
        /// Bundle identifier of the app it used before Stow took over.
        var previous: String?
        var id: String { type.id }
    }

    struct Report: Equatable {
        enum Kind: Equatable { case madeDefault, restored }
        var kind: Kind
        var changed: [String] = []
        /// Already the way people asked; nothing to do.
        var unchanged: [String] = []
        /// Type name → why it didn't change (refused, or macOS kept another app).
        var failed: [String: String] = [:]

        var summary: String {
            var parts: [String] = []
            if !changed.isEmpty {
                parts.append(kind == .madeDefault
                    ? String(localized: "\(changed.count) types now open with Stow")
                    : String(localized: "\(changed.count) types switched back"))
            }
            if !unchanged.isEmpty, changed.isEmpty, failed.isEmpty {
                parts.append(kind == .madeDefault ? String(localized: "Already opening with Stow") : String(localized: "Nothing to switch back"))
            }
            if !failed.isEmpty { parts.append(String(localized: "\(failed.count) types not changed")) }
            return parts.joined(separator: " · ")
        }

        var isSuccess: Bool { failed.isEmpty }

    }

    private(set) var rows: [Row] = []
    var selection: Set<String> = []
    private(set) var report: Report?
    private(set) var isWorking = false
    /// macOS asks people to confirm each change in its own dialog; this says which one is waiting.
    private(set) var waitingFor: String?

    private let registry: DefaultAppRegistry
    private let stow: URL
    private let stowIdentifier: String
    private let defaults: UserDefaults
    private static let previousKey = "PreviousDefaultApps"
    /// Used when there's nothing to go back to: the app macOS ships for archives.
    static let archiveUtility = "com.apple.archiveutility"

    init(registry: DefaultAppRegistry = LaunchServicesRegistry(), stow: URL = Bundle.main.bundleURL,
         stowIdentifier: String = Bundle.main.bundleIdentifier ?? "app.stow.Stow", defaults: UserDefaults = .standard) {
        self.registry = registry
        self.stow = stow
        self.stowIdentifier = stowIdentifier
        self.defaults = defaults
        refresh()
        selection = Set(rows.filter(\.opensWithStow).map(\.id))
    }

    private var previous: [String: String] {
        get { defaults.dictionary(forKey: Self.previousKey) as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: Self.previousKey) }
    }

    func refresh() {
        let previous = previous
        rows = ArchiveTypes.all.map { type in
            let app = UTType(type.id).flatMap(registry.defaultApp(for:))
            return Row(type: type, app: app, opensWithStow: isStow(app), previous: previous[type.id])
        }
    }

    func selectSuggested() {
        selection = Set(ArchiveTypes.all.filter(\.suggested).map(\.id))
    }

    /// Makes Stow the default for the selected types, remembering what each used before.
    func makeStowDefault() async {
        await run(.madeDefault) { row in
            if row.opensWithStow { return .unchanged }
            if let current = row.app, let identifier = registry.bundleIdentifier(of: current) {
                var previous = previous
                previous[row.id] = identifier
                self.previous = previous
            }
            return .set(stow)
        }
    }

    /// Gives the selected types back to the app they used before Stow (Archive Utility if none).
    func restorePrevious() async {
        await run(.restored) { row in
            guard row.opensWithStow else { return .unchanged }
            let identifier = row.previous ?? Self.archiveUtility
            guard let app = registry.app(withBundleIdentifier: identifier) else {
                return .fail(String(localized: "The app it used before (\(identifier)) isn’t installed any more."))
            }
            return .set(app)
        }
    }

    private enum Plan {
        case unchanged
        case set(URL)
        case fail(String)
    }

    private func run(_ kind: Report.Kind, plan: (Row) -> Plan) async {
        isWorking = true
        defer { isWorking = false }
        defer { waitingFor = nil }
        var report = Report(kind: kind)
        let chosen = rows.filter { selection.contains($0.id) }
        for (index, row) in chosen.enumerated() {
            guard let type = UTType(row.id) else { continue }
            waitingFor = String(localized: "\(row.type.name) (\(index + 1) of \(chosen.count))")
            switch plan(row) {
            case .unchanged:
                report.unchanged.append(row.type.name)
            case .fail(let message):
                report.failed[row.type.name] = message
            case .set(let app):
                do {
                    try await registry.setDefaultApp(app, for: type)
                    // Trust what Launch Services reports afterwards, not the call's success.
                    let now = registry.defaultApp(for: type)
                    if now?.standardizedFileURL == app.standardizedFileURL || (isStow(now) && app == stow) {
                        report.changed.append(row.type.name)
                        if kind == .restored { forgetPrevious(row.id) }
                    } else {
                        report.failed[row.type.name] = String(localized: "macOS kept \(name(of: now)).")
                    }
                } catch {
                    report.failed[row.type.name] = (error as NSError).localizedDescription
                }
            }
        }
        refresh()
        self.report = report
    }

    private func forgetPrevious(_ id: String) {
        var previous = previous
        previous[id] = nil
        self.previous = previous
    }

    /// Any copy of Stow counts (several builds share a bundle identifier).
    private func isStow(_ app: URL?) -> Bool {
        guard let app else { return false }
        return app.standardizedFileURL == stow.standardizedFileURL || registry.bundleIdentifier(of: app) == stowIdentifier
    }

    func name(of app: URL?) -> String {
        guard let app else { return String(localized: "no app") }
        return FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
    }
}
