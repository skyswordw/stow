import AppKit

/// How Finder (the Finder Sync extension) hands work to Stow without ever putting a path in a URL.
///
/// The extension posts the request — action and paths — into a mailbox under a random one-time
/// token, then opens `stow://handoff/<token>`. Stow takes the request out of the mailbox (which
/// empties it) and refuses tokens it doesn't know, has already used, or that are older than
/// `lifetime`. A web page or another document can open `stow://` URLs too, but without a
/// matching, fresh request in the mailbox the URL does nothing.
///
/// The mailbox is an App Group container when both sides are signed with a Team ID (#32); ad-hoc
/// builds fall back to a private pasteboard because macOS only opens the group to Team-signed
/// binaries.
nonisolated enum HandoffAction: String, Codable, CaseIterable, Sendable {
    case extractHere, extractTo, open, compress, quickCompress
}

nonisolated struct HandoffRequest: Codable, Equatable, Sendable {
    var action: HandoffAction
    /// Absolute file paths, as Finder selected them.
    var paths: [String]
    var created: Date

    init(action: HandoffAction, paths: [String], created: Date = .now) {
        self.action = action
        self.paths = paths
        self.created = created
    }

    var urls: [URL] { paths.map { URL(filePath: $0) } }
}

/// 128 random bits as 32 lowercase hex digits.
nonisolated struct HandoffToken: Hashable, Sendable, CustomStringConvertible {
    let value: String

    init?(_ value: String) {
        guard value.count == 32, value.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else { return nil }
        self.value = value
    }

    static func random() -> HandoffToken {
        var generator = SystemRandomNumberGenerator()
        let hex = (0..<16).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max, using: &generator)) }
        return HandoffToken(hex.joined())!
    }

    var description: String { value }
}

nonisolated enum HandoffError: Error, Equatable, Sendable {
    /// Not a `stow://handoff/<token>` URL at all.
    case notHandoff
    /// No request under this token: never posted, already taken, or posted by something else.
    case unknownToken
    case expired
    case invalidRequest
}

/// Where requests wait between the extension and the app. One read empties it.
nonisolated protocol HandoffMailbox: Sendable {
    func post(_ data: Data, for token: HandoffToken) throws
    func take(_ token: HandoffToken) -> Data?
}

/// Shared App Group for the Finder hand-off and Finder-menu settings (#32).
///
/// Team-ID-prefixed (`<Team ID>.<bundle prefix>`), not `group.…`: Stow ships with Developer ID and
/// no provisioning profile, and macOS only honours `group.` identifiers that a profile authorizes.
/// A Team-ID-prefixed group is authorized by the code signature itself.
nonisolated enum AppGroup {
    static let teamID = "YNQ2233752"
    /// Both Stow and StowFinderSync list it in their entitlements.
    static let identifier = "\(teamID).app.stow.Stow"

    /// The group container, only when this process can actually write to it. macOS hands back a
    /// path even for builds the sandbox won't let in (ad-hoc, CI, tests), so this checks first;
    /// `nil` means callers fall back to the pasteboard.
    static var containerURL: URL? {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
        else { return nil }
        return isUsable(url) ? url : nil
    }

    static func isUsable(_ url: URL) -> Bool {
        let fm = FileManager.default
        guard (try? fm.createDirectory(at: url, withIntermediateDirectories: true)) != nil else { return false }
        return fm.isWritableFile(atPath: url.path)
    }
}

nonisolated struct Handoff: Sendable {
    static let scheme = "stow"
    static let host = "handoff"
    /// Finder opens Stow within a second or two; anything older is stale (or replayed).
    static let lifetime: TimeInterval = 60
    /// More than this is not a Finder selection anyone made by hand.
    static let maximumPaths = 10_000

    let mailbox: any HandoffMailbox

    /// Uses the App Group container when macOS opens it, otherwise the private pasteboard.
    init(mailbox: (any HandoffMailbox)? = nil) {
        self.mailbox = mailbox ?? Self.defaultMailbox()
    }

    static func defaultMailbox() -> any HandoffMailbox {
        if let root = AppGroup.containerURL {
            return GroupMailbox(file: FileMailbox(root: root), fallback: PasteboardMailbox())
        }
        return PasteboardMailbox()
    }

    static func url(for token: HandoffToken) -> URL {
        URL(string: "\(scheme)://\(host)/\(token.value)")!
    }

    /// Strict: `stow://handoff/<32 hex>` and nothing else — no query, fragment, user or port.
    static func token(in url: URL) -> HandoffToken? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == scheme,
              components.host?.lowercased() == host,
              components.query == nil, components.fragment == nil,
              components.user == nil, components.password == nil, components.port == nil
        else { return nil }
        let path = components.path
        guard path.hasPrefix("/") else { return nil }
        return HandoffToken(String(path.dropFirst()))
    }

    static func isHandoff(_ url: URL) -> Bool {
        url.scheme?.lowercased() == scheme
    }

    /// Extension side: posts the request and returns the URL to open Stow with.
    func send(_ request: HandoffRequest) throws -> URL {
        let token = HandoffToken.random()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try mailbox.post(try encoder.encode(request), for: token)
        return Self.url(for: token)
    }

    /// App side: the request behind `url`, at most once.
    func receive(_ url: URL, now: Date = .now) throws(HandoffError) -> HandoffRequest {
        guard let token = Self.token(in: url) else { throw .notHandoff }
        guard let data = mailbox.take(token) else { throw .unknownToken }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let request = try? decoder.decode(HandoffRequest.self, from: data) else { throw .invalidRequest }
        let age = now.timeIntervalSince(request.created)
        guard age <= Self.lifetime, age > -5 else { throw .expired }
        guard !request.paths.isEmpty, request.paths.count <= Self.maximumPaths,
              request.paths.allSatisfy(Self.isPlausiblePath) else { throw .invalidRequest }
        return request
    }

    private static func isPlausiblePath(_ path: String) -> Bool {
        path.hasPrefix("/") && !path.contains("\0") && !path.split(separator: "/").contains("..")
    }
}

/// One file per token under `root/handoff/`. Used for the App Group container; tests pass a
/// temporary folder. A take deletes the file, so each token works once.
nonisolated struct FileMailbox: HandoffMailbox {
    let root: URL

    private var directory: URL {
        root.appending(path: "handoff", directoryHint: .isDirectory)
    }

    private func fileURL(for token: HandoffToken) -> URL {
        directory.appending(path: "\(token.value).json")
    }

    func post(_ data: Data, for token: HandoffToken) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        sweep(now: .now)
        let url = fileURL(for: token)
        // Refuse to overwrite an existing token file (collision or replay).
        if fm.fileExists(atPath: url.path) { throw HandoffError.invalidRequest }
        try data.write(to: url, options: .withoutOverwriting)
    }

    func take(_ token: HandoffToken) -> Data? {
        let url = fileURL(for: token)
        guard let data = try? Data(contentsOf: url) else { return nil }
        try? FileManager.default.removeItem(at: url)
        return data
    }

    /// Drops request files older than twice the hand-off lifetime (abandoned posts).
    func sweep(now: Date = .now) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return }
        let limit = Handoff.lifetime * 2
        for file in files where file.pathExtension == "json" {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if now.timeIntervalSince(modified) > limit {
                try? fm.removeItem(at: file)
            }
        }
    }
}

/// The App Group mailbox, still reading the pasteboard on take: if the extension couldn't open
/// the group (for example, a mismatched or older build), its request is found anyway.
nonisolated struct GroupMailbox: HandoffMailbox {
    let file: FileMailbox
    let fallback: any HandoffMailbox

    func post(_ data: Data, for token: HandoffToken) throws {
        do { try file.post(data, for: token) } catch { try fallback.post(data, for: token) }
    }

    func take(_ token: HandoffToken) -> Data? {
        // Both are emptied so a token can't be replayed through the other one.
        let fromFile = file.take(token)
        let fromFallback = fallback.take(token)
        return fromFile ?? fromFallback
    }
}

/// A private named pasteboard per request. Works between sandboxed processes signed by anyone —
/// unlike an App Group container, which macOS only opens to builds signed with a Team ID — and
/// `releaseGlobally()` makes each one single-use. Kept as the ad-hoc / CI fallback.
nonisolated struct PasteboardMailbox: HandoffMailbox {
    static let type = NSPasteboard.PasteboardType("app.stow.handoff-request")

    private static func name(for token: HandoffToken) -> NSPasteboard.Name {
        NSPasteboard.Name("app.stow.handoff.\(token.value)")
    }

    func post(_ data: Data, for token: HandoffToken) throws {
        let pasteboard = NSPasteboard(name: Self.name(for: token))
        pasteboard.clearContents()
        guard pasteboard.setData(data, forType: Self.type) else { throw HandoffError.invalidRequest }
    }

    func take(_ token: HandoffToken) -> Data? {
        let pasteboard = NSPasteboard(name: Self.name(for: token))
        defer { pasteboard.releaseGlobally() }
        return pasteboard.data(forType: Self.type)
    }
}

/// The few Finder settings the extension needs from the app. Prefer the App Group container
/// (#32); the named pasteboard remains the fallback when the group isn't available, and the
/// extension keeps the last copy it saw for after a restart.
nonisolated struct FinderMenuSettings: Codable, Equatable, Sendable {
    var showsOnExternalDrives = false

    private static let pasteboard = NSPasteboard.Name("app.stow.finder-settings")
    private static let type = NSPasteboard.PasteboardType("app.stow.finder-settings")
    private static let fileName = "finder-menu-settings.json"

    private static var settingsFileURL: URL? {
        AppGroup.containerURL?.appending(path: fileName)
    }

    func publish() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        if let url = Self.settingsFileURL {
            try? data.write(to: url, options: .atomic)
        }
        let pasteboard = NSPasteboard(name: Self.pasteboard)
        pasteboard.clearContents()
        pasteboard.setData(data, forType: Self.type)
    }

    static func published() -> FinderMenuSettings? {
        if let url = settingsFileURL,
           let data = try? Data(contentsOf: url),
           let settings = try? JSONDecoder().decode(Self.self, from: data) {
            return settings
        }
        return NSPasteboard(name: pasteboard).data(forType: type).flatMap { try? JSONDecoder().decode(Self.self, from: $0) }
    }

    /// Test helper: read/write settings through a folder the way the App Group path does.
    static func publish(_ settings: FinderMenuSettings, into root: URL) throws {
        let data = try JSONEncoder().encode(settings)
        try data.write(to: root.appending(path: fileName), options: .atomic)
    }

    static func published(from root: URL) -> FinderMenuSettings? {
        let url = root.appending(path: fileName)
        return (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Self.self, from: $0) }
    }
}

/// Which Stow items Finder's context menu shows for a selection.
nonisolated enum FinderMenu {
    static func actions(for paths: [String], settings: FinderMenuSettings) -> [HandoffAction] {
        guard !paths.isEmpty else { return [] }
        if !settings.showsOnExternalDrives, paths.contains(where: isOnExternalVolume) { return [] }
        var actions: [HandoffAction] = []
        if paths.allSatisfy({ ArchiveTypes.type(forFileName: $0) != nil }) {
            actions += [.extractHere, .extractTo]
            if paths.count == 1 { actions.append(.open) }
        }
        actions.append(.compress)
        return actions
    }

    /// Other volumes mount under /Volumes; the startup disk's data volume is firmlinked into "/".
    static func isOnExternalVolume(_ path: String) -> Bool {
        path.hasPrefix("/Volumes/")
    }

    static func title(for action: HandoffAction) -> String {
        switch action {
        case .extractHere: String(localized: "Extract Here")
        case .extractTo: String(localized: "Extract To…")
        case .open: String(localized: "Open in Stow")
        case .compress: String(localized: "Compress with Stow…")
        case .quickCompress: String(localized: "Quick Compress")
        }
    }

    static func symbol(for action: HandoffAction) -> String {
        switch action {
        case .extractHere: "arrow.down.doc"
        case .extractTo: "folder.badge.plus"
        case .open: "eye"
        case .compress, .quickCompress: "archivebox"
        }
    }
}
