import Foundation
import Testing
@testable import Stow

@Suite("Password prompt")
@MainActor
struct PasswordPromptTests {
    let prompt = PasswordPrompt()

    @Test func asksUntilThePasswordWorksAndReturnsIt() async throws {
        let task = Task {
            try await prompt.retrying("locked.7z", for: .open) { password -> String in
                switch password {
                case nil: throw EngineError(.passwordRequired)
                case "swordfish": return "listing"
                default: throw EngineError(.wrongPassword)
                }
            }
        }

        let first = try await nextQuestion(from: prompt)
        #expect(first.archiveName == "locked.7z" && first.purpose == .open && !first.isRetry)
        prompt.answer("guess", to: first.id)

        let second = try await nextQuestion(from: prompt, after: first)
        #expect(second.isRetry)
        prompt.answer("swordfish", to: second.id)

        let (value, password) = try await task.value
        #expect(value == "listing" && password == "swordfish")
        #expect(prompt.question == nil)
    }

    @Test func doesNotAskWhenNoPasswordIsNeeded() async throws {
        let (value, password) = try await prompt.retrying("plain.zip", for: .extract) { _ in 42 }
        #expect(value == 42 && password == nil)
    }

    @Test func triesTheKnownPasswordFirst() async throws {
        let (_, password) = try await prompt.retrying("locked.zip", for: .extract, known: "swordfish") { password in
            if password != "swordfish" { throw EngineError(.passwordRequired) }
        }
        #expect(password == "swordfish")
    }

    @Test func otherFailuresPassThroughWithoutAsking() async {
        await #expect(throws: EngineError(.notAnArchive)) {
            try await prompt.retrying("notes.zip", for: .open) { _ in throw EngineError(.notAnArchive) }
        }
    }

    @Test func cancellingTheQuestionCancelsTheOperation() async throws {
        let task = Task {
            try await prompt.retrying("locked.7z", for: .open) { _ in throw EngineError(.passwordRequired) }
        }
        let question = try await nextQuestion(from: prompt)
        prompt.answer(nil, to: question.id)
        await #expect(throws: EngineError(.cancelled)) { try await task.value }
    }

    @Test func cancellingTheTaskDismissesTheQuestion() async throws {
        let task = Task {
            try await prompt.retrying("locked.zip", for: .extract) { _ in throw EngineError(.passwordRequired) }
        }
        _ = try await nextQuestion(from: prompt)
        task.cancel()
        await #expect(throws: EngineError(.cancelled)) { try await task.value }
        #expect(prompt.question == nil)
    }

    @Test func aStaleAnswerIsIgnored() async throws {
        let task = Task {
            try await prompt.retrying("locked.7z", for: .open) { password in
                if password != "right" { throw EngineError(.wrongPassword) }
            }
        }
        let first = try await nextQuestion(from: prompt)
        prompt.answer("wrong", to: first.id)
        let second = try await nextQuestion(from: prompt, after: first)
        prompt.answer("late", to: first.id) // e.g. a sheet that was already closing
        #expect(prompt.question == second)
        prompt.answer("right", to: second.id)
        #expect(try await task.value.password == "right")
    }
}

/// Encrypted archives made by the bundled `7zz`, opened and extracted through the sandboxed engine.
@Suite("Encrypted archives", .enabled(if: SevenZip.bundled() != nil, "7zz isn't bundled — run scripts/fetch-7zip.sh"))
@MainActor
struct EncryptedArchiveTests {
    let folder: TemporaryFolder

    init() throws {
        folder = try TemporaryFolder()
        try FileManager.default.createDirectory(at: folder.url.appending(path: "Docs"), withIntermediateDirectories: false)
        try Data("top secret".utf8).write(to: folder.url.appending(path: "Docs/secret.txt"))
        try Data("also secret".utf8).write(to: folder.url.appending(path: "Docs/plan.txt"))
    }

    /// `options` e.g. `["-mhe=on"]` to encrypt the file list too.
    private func makeArchive(_ name: String, _ options: [String] = []) throws -> URL {
        let archive = folder.url.appending(path: name)
        let process = Process()
        process.executableURL = SevenZip.bundled()!.executable
        process.arguments = ["a", "-bso0", "-bsp0", "-pswordfish"] + options + [archive.path, "Docs"]
        process.currentDirectoryURL = folder.url
        try process.run()
        process.waitUntilExit()
        try #require(process.terminationStatus == 0)
        return archive
    }

    private func makeDestination() throws -> URL {
        let destination = folder.url.appending(path: "Out-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        return destination
    }

    @Test func encryptedFileListNeedsThePasswordToOpen() async throws {
        defer { folder.cleanUp() }
        let archive = try makeArchive("locked.7z", ["-mhe=on"])
        let engine = ArchiveEngine.shared

        await #expect(throws: EngineError(.passwordRequired)) { try await engine.list(archive) }
        await #expect(throws: EngineError(.wrongPassword)) { try await engine.list(archive, password: "guess") }
        let listing = try await engine.list(archive, password: "swordfish")
        #expect(Set(listing.entries.map(\.path)) == ["Docs", "Docs/secret.txt", "Docs/plan.txt"])
    }

    @Test(arguments: ["contents.7z", "contents.zip"])
    func encryptedContentsOpenWithoutAPasswordButNeedOneToExtract(name: String) async throws {
        defer { folder.cleanUp() }
        let url = try makeArchive(name, name.hasSuffix(".zip") ? ["-mem=AES256"] : [])
        let archive = Archive(listing: try await ArchiveEngine.shared.list(url), url: url)
        #expect(archive.isEncrypted)
        #expect(archive.checkup.contains { $0.title == "Contents are encrypted" })

        let destination = try makeDestination()
        await #expect(throws: EngineError(.passwordRequired)) {
            try await Extraction.run(archive, selection: nil, to: destination) { _ in }
        }
        var wrong = archive
        wrong.source?.password = "guess"
        await #expect(throws: EngineError(.wrongPassword)) {
            try await Extraction.run(wrong, selection: nil, to: destination) { _ in }
        }
        #expect(TemporaryFolder.contents(of: destination).isEmpty) // failed attempts leave nothing behind

        var unlocked = archive
        unlocked.source?.password = "swordfish"
        let result = try await Extraction.run(unlocked, selection: nil, to: destination) { _ in }
        #expect(result.placed.map(\.lastPathComponent) == ["Docs"])
        #expect(try String(contentsOf: destination.appending(path: "Docs/secret.txt"), encoding: .utf8) == "top secret")
    }

    /// The same path a drop or the Open panel takes: ask, retry, then remember the password so
    /// extracting doesn't ask again.
    @Test func openingAsksThenExtractingReusesThePassword() async throws {
        defer { folder.cleanUp() }
        let url = try makeArchive("locked.7z", ["-mhe=on"])
        let app = AppState()

        app.open(url)
        let first = try await nextQuestion(from: app.passwords)
        #expect(first.archiveName == "locked.7z" && first.purpose == .open && !first.isRetry)
        app.passwords.answer("guess", to: first.id)
        let second = try await nextQuestion(from: app.passwords, after: first)
        #expect(second.isRetry)
        app.passwords.answer("swordfish", to: second.id)

        let deadline = ContinuousClock.now + .seconds(20)
        while app.browser == nil, app.openFailure == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let archive = try #require(app.browser?.archive)
        #expect(app.openFailure == nil)
        #expect(archive.source?.password == "swordfish")
        #expect(archive.files.count == 2)

        let destination = try makeDestination()
        let result = try await Extraction.run(archive, selection: archive.children(of: "Docs"), to: destination) { _ in }
        #expect(Set(result.placed.map(\.lastPathComponent)) == ["secret.txt", "plan.txt"])
        #expect(app.passwords.question == nil)
    }

    @Test func cancellingThePasswordShowsNoError() async throws {
        defer { folder.cleanUp() }
        let url = try makeArchive("locked.7z", ["-mhe=on"])
        let app = AppState()

        app.open(url)
        let question = try await nextQuestion(from: app.passwords)
        app.passwords.answer(nil, to: question.id)

        let deadline = ContinuousClock.now + .seconds(10)
        while app.isOpening, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!app.isOpening)
        #expect(app.browser == nil && app.openFailure == nil)
    }
}

/// Waits for `prompt` to ask something other than `previous`.
@MainActor
private func nextQuestion(from prompt: PasswordPrompt, after previous: PasswordPrompt.Question? = nil)
    async throws -> PasswordPrompt.Question {
    let deadline = ContinuousClock.now + .seconds(20)
    while ContinuousClock.now < deadline {
        if let question = prompt.question, question != previous { return question }
        try await Task.sleep(for: .milliseconds(5))
    }
    throw EngineError(.failed, "No password question was asked.")
}
