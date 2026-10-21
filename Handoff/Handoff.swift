import AppKit

/// How Finder (the Finder Sync extension) hands work to Stow without ever putting a path in a URL.
///
/// The extension posts the request — action and paths — into a mailbox under a random one-time
/// token, then opens `stow://handoff/<token>`. Stow takes the request out of the mailbox (which
/// empties it) and refuses tokens it doesn't know, has already used, or that are older than
/// `lifetime`. A web page or another document can open `stow://` URLs too, but without a
/// matching, fresh request in the mailbox the URL does nothing.
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

nonisolated struct Handoff: Sendable {
    static let scheme = "stow"
    static let host = "handoff"
    /// Finder opens Stow within a second or two; anything older is stale (or replayed).
    static let lifetime: TimeInterval = 60
    /// More than this is not a Finder selection anyone made by hand.
    static let maximumPaths = 10_000

    let mailbox: any HandoffMailbox

    init(mailbox: any HandoffMailbox = PasteboardMailbox()) {
        self.mailbox = mailbox
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

/// A private named pasteboard per request. Works between sandboxed processes signed by anyone —
/// unlike an App Group container, which macOS only opens to builds signed with a Team ID — and
/// `releaseGlobally()` makes each one single-use.
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

/// The few Finder settings the extension needs from the app. Published on a named pasteboard
/// (same reason as above); the extension keeps the last copy it saw for after a restart.
nonisolated struct FinderMenuSettings: Codable, Equatable, Sendable {
    var showsOnExternalDrives = false

    private static let pasteboard = NSPasteboard.Name("app.stow.finder-settings")
    private static let type = NSPasteboard.PasteboardType("app.stow.finder-settings")

    func publish() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        let pasteboard = NSPasteboard(name: Self.pasteboard)
        pasteboard.clearContents()
        pasteboard.setData(data, forType: Self.type)
    }

    static func published() -> FinderMenuSettings? {
        NSPasteboard(name: pasteboard).data(forType: type).flatMap { try? JSONDecoder().decode(Self.self, from: $0) }
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
