import Testing
@testable import Stow

// Engine errors are matched on their stable failure code, not on their message.
// The message is user-facing text localized by whichever process raised it (often
// StowEngine.xpc, which follows the system language, not the test host's), so
// comparing it would make the suite depend on the Mac's language (#196 follow-up).

/// Expects `body` to throw an `EngineError` with `failure` and a non-empty message.
@discardableResult
func expectEngineFailure<R>(
    _ failure: EngineFailure,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ body: () throws -> R
) -> EngineError? {
    let error = #expect(throws: EngineError.self, sourceLocation: sourceLocation) { try body() }
    checkEngineError(error, is: failure, sourceLocation: sourceLocation)
    return error
}

/// Expects `body` to throw an `EngineError` with `failure` and a non-empty message.
@discardableResult
func expectEngineFailure<R>(
    _ failure: EngineFailure,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ body: () async throws -> R
) async -> EngineError? {
    let error = await #expect(throws: EngineError.self, sourceLocation: sourceLocation) { try await body() }
    checkEngineError(error, is: failure, sourceLocation: sourceLocation)
    return error
}

private func checkEngineError(_ error: EngineError?, is failure: EngineFailure, sourceLocation: SourceLocation) {
    guard let error else { return }
    #expect(error.failure == failure, sourceLocation: sourceLocation)
    #expect(!error.message.isEmpty, sourceLocation: sourceLocation)
}
