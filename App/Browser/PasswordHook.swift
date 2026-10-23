import Foundation

/// How browsing asks for a password — opening an encrypted archive inside another, extracting or
/// previewing encrypted contents. The browser doesn't build its own prompt: whoever creates it
/// injects `ask` (the app wires it to its password sheet). Without one, the engine's "needs a
/// password" is reported. Optional `vaultURL` recalls / saves through `ArchivePasswordVault` (#76).
struct PasswordHook {
    typealias Purpose = PasswordPrompt.Question.Purpose

    /// Asks for `archiveName`'s password; `isRetry` when the last one was rejected. Nil: cancelled.
    var ask: (_ archiveName: String, _ purpose: Purpose, _ isRetry: Bool) async -> String?
    let isWired: Bool

    init(ask: @escaping (_ archiveName: String, _ isRetry: Bool) async -> String?) {
        self.ask = { name, _, retry in await ask(name, retry) }
        isWired = true
    }

    /// Asks through the app's password sheet, worded for what the password is for.
    init(prompt: PasswordPrompt) {
        ask = { name, purpose, retry in
            await prompt.ask(.init(archiveName: name, purpose: purpose, isRetry: retry))
        }
        isWired = true
    }

    private init() {
        ask = { _, _, _ in nil }
        isWired = false
    }

    static let none = PasswordHook()

    /// Runs `operation` with `known` first (then a Keychain recall when `vaultURL` is set and the
    /// vault is on), then asks each time the engine wants a password. Returns the value with the
    /// password that worked. A successful unlock saves into the vault when it is on.
    func retrying<T>(_ archiveName: String, for purpose: Purpose = .open, known: String? = nil,
                     vaultURL: URL? = nil,
                     _ operation: (String?) async throws -> T) async throws(EngineError) -> (value: T, password: String?) {
        var password = known
        var fromVault = false
        if password == nil, let vaultURL, let recalled = ArchivePasswordVault.recalled(for: vaultURL) {
            password = recalled
            fromVault = true
        }
        while true {
            do {
                let value = try await operation(password)
                if let password, let vaultURL {
                    ArchivePasswordVault.remember(password, for: vaultURL)
                }
                return (value, password)
            } catch {
                let error = EngineError(error)
                guard error.needsPassword, isWired else { throw error }
                if fromVault, let vaultURL {
                    ArchivePasswordVault.forget(url: vaultURL)
                    fromVault = false
                }
                guard let next = await ask(archiveName, purpose, password != nil) else { throw EngineError(.cancelled) }
                password = next
            }
        }
    }
}
