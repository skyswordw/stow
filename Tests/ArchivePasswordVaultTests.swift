import Foundation
import Testing
@testable import Stow

@Suite("Archive password vault")
struct ArchivePasswordVaultTests {
    /// Isolates the shared vault store and the remember-passwords preference for one test.
    private func withVault<T>(_ body: (MemoryArchivePasswordStore, UserDefaults, URL) throws -> T) throws -> T {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let archive = folder.url.appending(path: "locked.7z")
        try Data("archive-bytes".utf8).write(to: archive)
        let store = MemoryArchivePasswordStore()
        let previous = ArchivePasswordVault.store
        ArchivePasswordVault.store = store
        defer { ArchivePasswordVault.store = previous }

        let suite = "ArchivePasswordVaultTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        // `SettingsKeys.flag` reads `.standard`; point the key there and restore after.
        let prior = UserDefaults.standard.object(forKey: SettingsKeys.rememberPasswords)
        defer {
            if let prior {
                UserDefaults.standard.set(prior, forKey: SettingsKeys.rememberPasswords)
            } else {
                UserDefaults.standard.removeObject(forKey: SettingsKeys.rememberPasswords)
            }
        }
        UserDefaults.standard.set(true, forKey: SettingsKeys.rememberPasswords)
        return try body(store, defaults, archive)
    }

    @Test func identityUsesPathSizeAndDate() throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let url = folder.url.appending(path: "notes.zip")
        try Data("hello".utf8).write(to: url)
        let first = try #require(ArchivePasswordIdentity.make(url: url))
        let again = try #require(ArchivePasswordIdentity.make(url: url))
        #expect(first == again)
        #expect(first.account.count == 64)
        #expect(first.path == url.standardizedFileURL.resolvingSymlinksInPath().path)

        try Data("hello!".utf8).write(to: url) // size change → new identity
        let changed = try #require(ArchivePasswordIdentity.make(url: url))
        #expect(changed.account != first.account)
    }

    @Test func temporaryPathsAreNotVaultable() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "Previews/x/inner.7z")
        #expect(ArchivePasswordIdentity.make(url: url) == nil)
        #expect(!ArchivePasswordIdentity.isVaultable(url))
    }

    @Test func storeLookupForgetAndWipe() throws {
        try withVault { store, _, archive in
            let identity = try #require(ArchivePasswordIdentity.make(url: archive))
            try store.save("swordfish", for: identity, displayName: "locked.7z")
            #expect(store.password(for: identity) == "swordfish")
            #expect(store.entries().map(\.displayName) == ["locked.7z"])

            try store.forget(identity)
            #expect(store.password(for: identity) == nil)
            #expect(store.entries().isEmpty)

            try store.save("one", for: identity, displayName: "locked.7z")
            let otherFile = archive.deletingLastPathComponent().appending(path: "other.zip")
            try Data("other".utf8).write(to: otherFile)
            let other = try #require(ArchivePasswordIdentity.make(url: otherFile))
            try store.save("two", for: other, displayName: "other.zip")
            #expect(store.entries().count == 2)
            try store.wipe()
            #expect(store.entries().isEmpty)
            #expect(store.password(for: identity) == nil)
        }
    }

    @Test func facadeRespectsOptInToggle() throws {
        try withVault { store, _, archive in
            ArchivePasswordVault.remember("swordfish", for: archive)
            #expect(store.password(for: try #require(ArchivePasswordIdentity.make(url: archive))) == "swordfish")
            #expect(ArchivePasswordVault.recalled(for: archive) == "swordfish")

            UserDefaults.standard.set(false, forKey: SettingsKeys.rememberPasswords)
            #expect(ArchivePasswordVault.recalled(for: archive) == nil)
            ArchivePasswordVault.remember("ignored", for: archive)
            // Store still has the earlier value; disabled vault neither reads nor overwrites.
            #expect(store.password(for: try #require(ArchivePasswordIdentity.make(url: archive))) == "swordfish")
        }
    }

    @Test func forgetAfterRejectedRecall() throws {
        try withVault { store, _, archive in
            ArchivePasswordVault.remember("old", for: archive)
            #expect(ArchivePasswordVault.recalled(for: archive) == "old")
            ArchivePasswordVault.forget(url: archive)
            #expect(store.password(for: try #require(ArchivePasswordIdentity.make(url: archive))) == nil)
        }
    }
}

@Suite("Password prompt with vault")
@MainActor
struct PasswordPromptVaultTests {
    @Test func recallsSavedPasswordWithoutAsking() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let archive = folder.url.appending(path: "locked.7z")
        try Data("bytes".utf8).write(to: archive)

        let store = MemoryArchivePasswordStore()
        let previous = ArchivePasswordVault.store
        ArchivePasswordVault.store = store
        defer { ArchivePasswordVault.store = previous }
        let prior = UserDefaults.standard.object(forKey: SettingsKeys.rememberPasswords)
        defer {
            if let prior { UserDefaults.standard.set(prior, forKey: SettingsKeys.rememberPasswords) }
            else { UserDefaults.standard.removeObject(forKey: SettingsKeys.rememberPasswords) }
        }
        UserDefaults.standard.set(true, forKey: SettingsKeys.rememberPasswords)
        ArchivePasswordVault.remember("swordfish", for: archive)

        let prompt = PasswordPrompt()
        let (value, password) = try await prompt.retrying("locked.7z", for: .open, vaultURL: archive) { password in
            if password != "swordfish" { throw EngineError(.passwordRequired) }
            return "ok"
        }
        #expect(value == "ok" && password == "swordfish")
        #expect(prompt.question == nil)
    }

    @Test func savesSuccessfulPasswordWhenVaultIsOn() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let archive = folder.url.appending(path: "locked.7z")
        try Data("bytes".utf8).write(to: archive)

        let store = MemoryArchivePasswordStore()
        let previous = ArchivePasswordVault.store
        ArchivePasswordVault.store = store
        defer { ArchivePasswordVault.store = previous }
        let prior = UserDefaults.standard.object(forKey: SettingsKeys.rememberPasswords)
        defer {
            if let prior { UserDefaults.standard.set(prior, forKey: SettingsKeys.rememberPasswords) }
            else { UserDefaults.standard.removeObject(forKey: SettingsKeys.rememberPasswords) }
        }
        UserDefaults.standard.set(true, forKey: SettingsKeys.rememberPasswords)

        let prompt = PasswordPrompt()
        let task = Task {
            try await prompt.retrying("locked.7z", for: .open, vaultURL: archive) { password -> String in
                guard password == "swordfish" else { throw EngineError(.passwordRequired) }
                return "listing"
            }
        }
        let question = try await nextVaultQuestion(from: prompt)
        prompt.answer("swordfish", to: question.id)
        let (value, password) = try await task.value
        #expect(value == "listing" && password == "swordfish")
        #expect(ArchivePasswordVault.recalled(for: archive) == "swordfish")
    }

    @Test func dropsRejectedVaultPasswordAndAsksAgain() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let archive = folder.url.appending(path: "locked.7z")
        try Data("bytes".utf8).write(to: archive)

        let store = MemoryArchivePasswordStore()
        let previous = ArchivePasswordVault.store
        ArchivePasswordVault.store = store
        defer { ArchivePasswordVault.store = previous }
        let prior = UserDefaults.standard.object(forKey: SettingsKeys.rememberPasswords)
        defer {
            if let prior { UserDefaults.standard.set(prior, forKey: SettingsKeys.rememberPasswords) }
            else { UserDefaults.standard.removeObject(forKey: SettingsKeys.rememberPasswords) }
        }
        UserDefaults.standard.set(true, forKey: SettingsKeys.rememberPasswords)
        ArchivePasswordVault.remember("stale", for: archive)

        let prompt = PasswordPrompt()
        let task = Task {
            try await prompt.retrying("locked.7z", for: .open, vaultURL: archive) { password -> String in
                switch password {
                case "swordfish": return "ok"
                case "stale": throw EngineError(.wrongPassword)
                default: throw EngineError(.passwordRequired)
                }
            }
        }
        let question = try await nextVaultQuestion(from: prompt)
        #expect(question.isRetry) // vault password was tried and rejected
        #expect(ArchivePasswordVault.recalled(for: archive) == nil)
        prompt.answer("swordfish", to: question.id)
        #expect(try await task.value.password == "swordfish")
        #expect(ArchivePasswordVault.recalled(for: archive) == "swordfish")
    }
}

@MainActor
private func nextVaultQuestion(from prompt: PasswordPrompt, after previous: PasswordPrompt.Question? = nil)
    async throws -> PasswordPrompt.Question {
    let deadline = ContinuousClock.now + .seconds(20)
    while ContinuousClock.now < deadline {
        if let question = prompt.question, question != previous { return question }
        try await Task.sleep(for: .milliseconds(5))
    }
    throw EngineError(.failed, "No password question was asked.")
}
