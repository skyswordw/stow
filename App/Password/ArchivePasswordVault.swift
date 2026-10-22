import CryptoKit
import Foundation
import Security

/// Where an archive password is keyed in the vault: path + size + modification date (#76).
///
/// Same shape as the preview cache's archive identity — enough to tell “this file” from a
/// replaced one without reading the whole archive. Ephemeral paths (preview cache, received-file
/// drops) are not vaultable; those passwords stay session-only.
nonisolated struct ArchivePasswordIdentity: Hashable, Sendable {
    /// Keychain account / store key — hex SHA-256 of the identity string, never the password.
    let account: String
    /// Absolute path used for display and for rebuilding the identity later.
    let path: String
    let size: Int64
    let modified: TimeInterval

    /// `nil` when the URL isn't a stable file people would reopen (missing, or under Stow's
    /// temporary preview / received-file folders).
    static func make(url: URL) -> ArchivePasswordIdentity? {
        guard isVaultable(url) else { return nil }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey])
        guard values?.isRegularFile != false else { return nil }
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        let size = Int64(values?.fileSize ?? 0)
        let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let digest = SHA256.hash(data: Data("\(path)|\(size)|\(modified)".utf8))
            .map { String(format: "%02x", $0) }.joined()
        return ArchivePasswordIdentity(account: digest, path: path, size: size, modified: modified)
    }

    /// Preview-cache extracts and Mail/chat received drops live under `temporaryDirectory`;
    /// those paths vanish, so they stay session-only.
    static func isVaultable(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        let temporary = FileManager.default.temporaryDirectory.standardizedFileURL.resolvingSymlinksInPath().path
        return !path.hasPrefix(temporary + "/")
    }
}

/// One saved entry as Settings lists it — never includes the password itself.
nonisolated struct ArchivePasswordEntry: Identifiable, Hashable, Sendable {
    var id: String { identity.account }
    let identity: ArchivePasswordIdentity
    let displayName: String
}

/// Backing store for the vault. The Keychain implementation is the product default; tests inject
/// an in-memory store so CI never needs real Keychain secrets.
nonisolated protocol ArchivePasswordStoring: Sendable {
    func password(for identity: ArchivePasswordIdentity) -> String?
    func save(_ password: String, for identity: ArchivePasswordIdentity, displayName: String) throws
    func forget(_ identity: ArchivePasswordIdentity) throws
    func wipe() throws
    func entries() -> [ArchivePasswordEntry]
}

/// Opt-in Keychain-backed archive passwords (#76). Off by default — when off, behaviour matches
/// session-only memory on `ArchiveSource`. Passwords leave the process only into the user's
/// Keychain (main app only; not the XPC or Finder extension).
nonisolated enum ArchivePasswordVault {
    /// Product store. Tests replace this with `MemoryArchivePasswordStore`.
    nonisolated(unsafe) static var store: any ArchivePasswordStoring = KeychainArchivePasswordStore()

    static var isEnabled: Bool { SettingsKeys.flag(SettingsKeys.rememberPasswords) }

    /// Looks up a saved password when the vault is on and `url` is vaultable; otherwise nil.
    static func recalled(for url: URL) -> String? {
        guard isEnabled, let identity = ArchivePasswordIdentity.make(url: url) else { return nil }
        return store.password(for: identity)
    }

    /// Saves after a password unlocked the archive, when the vault is on. No-op when off or when
    /// `url` isn't vaultable. Never logs the password.
    static func remember(_ password: String, for url: URL) {
        guard isEnabled, !password.isEmpty, let identity = ArchivePasswordIdentity.make(url: url) else { return }
        try? store.save(password, for: identity, displayName: url.lastPathComponent)
    }

    /// Drops a saved entry after a recalled password was rejected (file changed, or wrong entry).
    static func forget(url: URL) {
        guard let identity = ArchivePasswordIdentity.make(url: url) else { return }
        try? store.forget(identity)
    }

    static func forget(_ entry: ArchivePasswordEntry) {
        try? store.forget(entry.identity)
    }

    static func wipe() {
        try? store.wipe()
    }

    static func entries() -> [ArchivePasswordEntry] {
        store.entries().sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }
}

// MARK: - In-memory (tests)

nonisolated final class MemoryArchivePasswordStore: ArchivePasswordStoring, @unchecked Sendable {
    private struct Item {
        var password: String
        var displayName: String
        var identity: ArchivePasswordIdentity
    }

    private let lock = NSLock()
    private var items: [String: Item] = [:]

    func password(for identity: ArchivePasswordIdentity) -> String? {
        lock.withLock { items[identity.account]?.password }
    }

    func save(_ password: String, for identity: ArchivePasswordIdentity, displayName: String) throws {
        lock.withLock {
            items[identity.account] = Item(password: password, displayName: displayName, identity: identity)
        }
    }

    func forget(_ identity: ArchivePasswordIdentity) throws {
        lock.withLock { items[identity.account] = nil }
    }

    func wipe() throws {
        lock.withLock { items.removeAll() }
    }

    func entries() -> [ArchivePasswordEntry] {
        lock.withLock {
            items.values.map { ArchivePasswordEntry(identity: $0.identity, displayName: $0.displayName) }
        }
    }
}

// MARK: - Keychain

/// Generic passwords under `service`, keyed by the identity digest. Access group is app-only
/// (`…Stow.archive-password`), not the App Group shared with Finder Sync.
nonisolated struct KeychainArchivePasswordStore: ArchivePasswordStoring {
    static let service = "app.stow.Stow.archive-password"
    /// Distinct from the App Group id so Finder Sync never sees these items.
    static let accessGroup = "\(AppGroup.teamID).app.stow.Stow.archive-password"

    func password(for identity: ArchivePasswordIdentity) -> String? {
        var query: [String: Any] = baseQuery(account: identity.account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(_ password: String, for identity: ArchivePasswordIdentity, displayName: String) throws {
        guard let data = password.data(using: .utf8) else { return }
        try forget(identity)
        var query: [String: Any] = baseQuery(account: identity.account)
        query[kSecValueData as String] = data
        query[kSecAttrLabel as String] = displayName
        query[kSecAttrComment as String] = identity.path
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status) }
    }

    func forget(_ identity: ArchivePasswordIdentity) throws {
        let status = SecItemDelete(baseQuery(account: identity.account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status) }
    }

    func wipe() throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service
        ]
        query[kSecAttrAccessGroup as String] = Self.accessGroup
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status) }
    }

    func entries() -> [ArchivePasswordEntry] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccessGroup as String: Self.accessGroup,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let rows = result as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard let account = row[kSecAttrAccount as String] as? String else { return nil }
            let path = row[kSecAttrComment as String] as? String ?? ""
            let name = row[kSecAttrLabel as String] as? String
                ?? (path as NSString).lastPathComponent
            let identity = ArchivePasswordIdentity(account: account, path: path, size: 0, modified: 0)
            return ArchivePasswordEntry(identity: identity, displayName: name.isEmpty ? account : name)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: Self.accessGroup
        ]
    }

    private struct KeychainError: Error {
        let status: OSStatus
        init(_ status: OSStatus) { self.status = status }
    }
}
