import Foundation
import Testing
@testable import Stow

@Suite("Batch password reuse")
@MainActor
struct BatchPasswordTests {
    private let url = FileManager.default.temporaryDirectory.appending(path: "batch-locked.zip")

    @Test func successfulPasswordsAreReusedOnlyWithinTheSession() async throws {
        let session = BatchPasswordSession()
        var questions = 0
        let hook = PasswordHook { _, _ in questions += 1; return "correct" }
        for _ in 0..<2 {
            let value = try await session.retrying(url, passwords: hook) { password in
                guard password == "correct" else { throw EngineError(.passwordRequired) }
                return 42
            }
            #expect(value == 42)
        }
        #expect(questions == 1 && session.successful == ["correct"])
        session.clear()
        #expect(session.successful.isEmpty)
        _ = try await session.retrying(url, passwords: hook) { password in
            guard password == "correct" else { throw EngineError(.wrongPassword) }
        }
        #expect(questions == 2)
    }

    @Test func rejectedCandidateDoesNotDiscardPasswordForOtherArchives() async throws {
        let session = BatchPasswordSession()
        let first = PasswordHook { _, _ in "first" }
        _ = try await session.retrying(url, passwords: first) { password in
            guard password == "first" else { throw EngineError(.passwordRequired) }
        }
        var retryFlags: [Bool] = []
        let second = PasswordHook { _, retry in
            retryFlags.append(retry)
            return retryFlags.count == 1 ? "wrong" : "second"
        }
        _ = try await session.retrying(url, passwords: second) { password in
            guard password == "second" else { throw EngineError(.wrongPassword) }
        }
        #expect(retryFlags == [false, true])
        #expect(session.successful == ["second", "first"])
        let noPrompt = PasswordHook { _, _ in Issue.record("Expected cached password"); return nil }
        _ = try await session.retrying(url, passwords: noPrompt) { password in
            guard password == "first" else { throw EngineError(.wrongPassword) }
        }
    }

    @Test func skipKeepsPreviousPasswordsAndLaterWorkCanContinue() async throws {
        let session = BatchPasswordSession()
        await expectEngineFailure(.cancelled) {
            try await session.retrying(url, passwords: PasswordHook { _, _ in nil }) { _ in
                throw EngineError(.passwordRequired)
            }
        }
        #expect(session.successful.isEmpty)
        #expect(try await session.retrying(url, passwords: .none) { _ in 7 } == 7)
    }

    @Test func nonPasswordFailureAndCancelledSuccessAreNeverRemembered() async throws {
        let session = BatchPasswordSession()
        var asked = false
        await expectEngineFailure(.notAnArchive) {
            try await session.retrying(url, passwords: PasswordHook { _, _ in asked = true; return "unused" }) { _ in
                throw EngineError(.notAnArchive)
            }
        }
        #expect(!asked)
        let task = Task {
            try await session.retrying(url, passwords: PasswordHook { _, _ in "secret" }) { password in
                guard password != nil else { throw EngineError(.passwordRequired) }
                withUnsafeCurrentTask { $0?.cancel() }
                return 1
            }
        }
        await expectEngineFailure(.cancelled) { try await task.value }
        #expect(session.successful.isEmpty)
    }

    @Test func cancelledWaitDoesNotReplaceAnotherWindowsQuestion() async throws {
        let prompt = PasswordPrompt()
        let owner = Task { await prompt.ask(.init(archiveName: "Owner.zip", purpose: .open, isRetry: false)) }
        for _ in 0..<100 where prompt.question == nil { await Task.yield() }
        let question = try #require(prompt.question)
        let session = BatchPasswordSession()
        let batch = Task {
            try await session.retrying(url, passwords: PasswordHook(prompt: prompt)) { _ in
                throw EngineError(.passwordRequired)
            }
        }
        await Task.yield()
        batch.cancel()
        await expectEngineFailure(.cancelled) { try await batch.value }
        #expect(prompt.question?.id == question.id)
        prompt.answer(nil, to: question.id)
        #expect(await owner.value == nil)
    }
}

@Suite("Batch encrypted extraction", .enabled(if: SevenZip.bundled() != nil, "7zz isn't bundled"))
@MainActor
struct BatchEncryptedExtractionTests {
    @Test func batchReusesVerifiedPasswordsAndContinuesAfterSkipAndFailure() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let sevenZip = try #require(SevenZip.bundled())
        let input = folder.url.appending(path: "input")
        let output = folder.url.appending(path: "archives")
        let work = folder.url.appending(path: "work")
        let destination = folder.url.appending(path: "destination")
        for path in [input, output, work, destination] {
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false)
        }
        // Two files make each archive get its own output folder, avoiding conflict UI.
        try Data("one".utf8).write(to: input.appending(path: "one.txt"))
        try Data("two".utf8).write(to: input.appending(path: "two.txt"))
        var urls: [URL] = []
        for (name, password) in [("first", "same"), ("skip", "different"), ("last", "same")] {
            let target = output.appending(path: name)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
            _ = try await sevenZip.create(CreateRequest(operationID: UUID().uuidString, archiveName: name,
                                                         format: .sevenZip, level: .store, password: password),
                                          from: input, into: target, work: work) { _ in }
            urls.append(target.appending(path: name + ".7z"))
        }
        let bad = output.appending(path: "bad.zip")
        try Data("not an archive".utf8).write(to: bad)
        urls.insert(bad, at: 2)
        let queue = BatchQueue()
        var asked: [String] = []
        queue.passwords = PasswordHook { name, _ in
            asked.append(name)
            return name == "skip.7z" ? nil : "same"
        }
        var cleaned: [URL]?
        queue.aftercare = { sources, _ in cleaned = sources.map(\.archive) }
        queue.enqueue(urls, into: destination)
        for _ in 0..<2_000 where cleaned == nil { try await Task.sleep(for: .milliseconds(10)) }
        #expect(cleaned == [urls[0], urls[3]])
        #expect(asked == ["first.7z", "skip.7z"])
        #expect(queue.summary.completed == 2 && queue.summary.stopped == 1 && queue.summary.failed == 1)
        #expect(try Data(contentsOf: destination.appending(path: "first/one.txt")) == Data("one".utf8))
        #expect(try Data(contentsOf: destination.appending(path: "last/two.txt")) == Data("two".utf8))
        #expect(!FileManager.default.fileExists(atPath: destination.appending(path: "skip").path))
        #expect(urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }
}
