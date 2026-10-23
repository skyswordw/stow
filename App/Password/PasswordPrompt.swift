import Foundation

/// Asks for an archive's password when the engine says it needs one, one question at a time.
///
/// What people type stays in memory: it travels to the engine inside a request and is kept on the
/// open archive's `ArchiveSource` so the next extraction doesn't ask again. With the optional
/// Keychain vault (#76) on, a password that unlocked a stable archive is also saved in the user's
/// Keychain and recalled on a later launch — never on argv, never logged. It goes away when the
/// archive is closed (memory) or when the vault entry is forgotten.
@Observable
final class PasswordPrompt {
    struct Question: Identifiable, Equatable {
        enum Purpose { case open, extract, unlock }

        let id = UUID()
        let archiveName: String
        let purpose: Purpose
        /// The last password was rejected.
        let isRetry: Bool
    }

    private(set) var question: Question?
    private var continuation: CheckedContinuation<String?, Never>?

    /// Shows `question` and waits for the answer; nil means cancelled. Cancelling the calling task
    /// dismisses the question.
    func ask(_ question: Question) async -> String? {
        if let current = self.question { answer(nil, to: current.id) }
        let id = question.id
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                self.question = question
            }
        } onCancel: {
            Task { @MainActor in self.answer(nil, to: id) }
        }
    }

    /// Answers the question with `id` if it's still the one being asked; nil cancels it.
    func answer(_ password: String?, to id: Question.ID) {
        guard question?.id == id else { return }
        question = nil
        continuation.take()?.resume(returning: password)
    }

    /// Runs `operation` with `known` first (then a Keychain recall when `vaultURL` is set and the
    /// vault is on), then asks each time the engine says a password is needed or was wrong.
    /// Returns the result with the password that worked (nil if none was needed). Cancelling the
    /// question throws `.cancelled`. A successful unlock saves into the vault when it is on.
    func retrying<T>(_ archiveName: String, for purpose: Question.Purpose, known: String? = nil,
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
                guard error.needsPassword else { throw error }
                if fromVault, let vaultURL {
                    ArchivePasswordVault.forget(url: vaultURL)
                    fromVault = false
                }
                let question = Question(archiveName: archiveName, purpose: purpose, isRetry: password != nil)
                guard let next = await ask(question) else { throw EngineError(.cancelled) }
                password = next
            }
        }
    }
}

extension EngineError {
    /// The engine stopped for a password: none was given, or the one given was wrong.
    var needsPassword: Bool { failure == .passwordRequired || failure == .wrongPassword }
}
