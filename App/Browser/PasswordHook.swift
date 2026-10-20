import Foundation

/// How browsing asks for a password — opening an encrypted archive inside another, or previewing
/// encrypted contents. The browser doesn't build its own prompt: whoever creates it injects `ask`
/// (wired to the app's password sheet). Without one, the engine's "needs a password" is reported.
struct PasswordHook {
    /// Asks for `archiveName`'s password; `isRetry` when the last one was rejected. Nil: cancelled.
    var ask: (_ archiveName: String, _ isRetry: Bool) async -> String?
    let isWired: Bool

    init(ask: @escaping (_ archiveName: String, _ isRetry: Bool) async -> String?) {
        self.ask = ask
        isWired = true
    }

    private init() {
        ask = { _, _ in nil }
        isWired = false
    }

    static let none = PasswordHook()

    /// Runs `operation` with `known` first, then asks each time the engine wants a password.
    /// Returns the value with the password that worked.
    func retrying<T>(_ archiveName: String, known: String? = nil,
                     _ operation: (String?) async throws -> T) async throws(EngineError) -> (value: T, password: String?) {
        var password = known
        while true {
            do {
                return (try await operation(password), password)
            } catch {
                let error = EngineError(error)
                guard error.failure == .passwordRequired || error.failure == .wrongPassword else { throw error }
                guard isWired else { throw error }
                guard let next = await ask(archiveName, password != nil) else { throw EngineError(.cancelled) }
                password = next
            }
        }
    }
}
