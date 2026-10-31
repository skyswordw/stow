import Foundation
import Testing
@testable import Stow

@Suite("Source access recovery")
@MainActor
struct SourceReadAccessTests {
    let file = URL(filePath: "/Users/example/Attachments/report.zip")

    @Test func rememberedScopesAreRestoredBeforeTheFirstRead() async throws {
        var restored = false
        let access = SourceReadAccess(probe: { _ in restored ? nil : EPERM }, choose: { _ in
            Issue.record("A saved grant must be restored before asking again")
            return nil
        }, restore: { restored = true })
        #expect(try await access.acquire(file) == nil)
        #expect(restored)
    }

    @Test(arguments: [nil, ENOENT, EIO] as [Int32?])
    func ordinaryOpenDoesNotRequestPermission(_ code: Int32?) async throws {
        let access = SourceReadAccess(probe: { _ in code }, choose: { _ in
            Issue.record("Readable or non-permission failure must not show a picker")
            return nil
        })
        #expect(try await access.acquire(file) == nil)
    }

    @Test func folderGrantIsVerifiedBeforeRememberingAndReleasedOnce() async throws {
        var readable = false, starts = 0, stops = 0
        var remembered: [URL] = []
        let folder = file.deletingLastPathComponent()
        let access = SourceReadAccess(probe: { _ in readable ? nil : EPERM }, choose: { _ in folder },
                                      start: { _ in starts += 1; readable = true; return true },
                                      stop: { _ in stops += 1 }, remember: { url in
            #expect(readable)
            remembered.append(url)
        })
        let grant = try #require(try await access.acquire(file))
        #expect(grant.url == folder && remembered == [folder])
        #expect(starts == 1 && stops == 0)
        grant.release()
        grant.release()
        #expect(stops == 1)
        // The next file in an already-readable location does not prompt again.
        #expect(try await access.acquire(folder.appending(path: "next.zip")) == nil)
        #expect(starts == 1)
    }

    @Test func singleFileDoesNotSaveAFolderGrant() async throws {
        var readable = false
        let access = SourceReadAccess(probe: { _ in readable ? nil : EACCES }, choose: { _ in file },
                                      start: { _ in readable = true; return true }, stop: { _ in },
                                      remember: { _ in Issue.record("Must not persist a parent grant") })
        let grant = try #require(try await access.acquire(file))
        #expect(grant.url == file)
        grant.release()
    }

    @Test(arguments: [EACCES, EPERM])
    func residualDenialHasRealCodeAndDoesNotLoop(_ code: Int32) async throws {
        var prompts = 0, stops = 0
        let access = SourceReadAccess(probe: { _ in code }, choose: { _ in prompts += 1; return file },
                                      start: { _ in true }, stop: { _ in stops += 1 },
                                      remember: { _ in Issue.record("Unreadable grants must not be saved") })
        do {
            _ = try await access.acquire(file)
            Issue.record("Expected denial")
        } catch let error as SourceReadAccess.Denied {
            #expect(error.code == code)
            let failure = OtherAppFiles.unreadable(file, code: error.code)
            #expect(failure.code.description == "OPN-101")
            #expect(failure.kind == .noReadAccess)
            #expect(failure.diagnostic.contains("NSPOSIXErrorDomain \(code)"))
        }
        #expect(prompts == 1 && stops == 1)
    }

    @Test func cancelDoesNotAcquireOrSaveAnything() async throws {
        let access = SourceReadAccess(probe: { _ in EPERM }, choose: { _ in nil },
                                      start: { _ in Issue.record("Cancelled"); return true },
                                      remember: { _ in Issue.record("Cancelled") })
        await #expect(throws: CancellationError.self) { _ = try await access.acquire(file) }
    }

    @Test func stalePickerCompletionCannotAcquireOrSaveAccess() async throws {
        var continuation: CheckedContinuation<URL?, Never>?
        let access = SourceReadAccess(probe: { _ in EPERM }, choose: { _ in
            await withCheckedContinuation { continuation = $0 }
        }, start: { _ in Issue.record("Stale result acquired access"); return true },
        remember: { _ in Issue.record("Stale result saved access") })
        let task = Task { try await access.acquire(file) }
        try await waitUntil { continuation != nil }
        task.cancel()
        continuation?.resume(returning: file)
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }

    @Test func broadOrUnrelatedSelectionsAreRejected() async throws {
        let folder = file.deletingLastPathComponent()
        #expect(SourceReadAccess.accepts(file, for: file))
        #expect(SourceReadAccess.accepts(folder, for: file))
        for selection in [folder.deletingLastPathComponent(), URL(filePath: "/"),
                          folder.appending(path: "different.zip"), URL(string: "https://example.com/report.zip")!] {
            #expect(!SourceReadAccess.accepts(selection, for: file))
            let access = SourceReadAccess(probe: { _ in EPERM }, choose: { _ in selection },
                                          start: { _ in Issue.record("Invalid selection acquired access"); return true })
            await #expect(throws: CocoaError.self) { _ = try await access.acquire(file) }
        }
    }

    @Test func fileRemovedDuringPickerIsNotReportedAsPermissionDenial() async throws {
        var reads = 0, stops = 0
        let access = SourceReadAccess(probe: { _ in reads += 1; return reads == 1 ? EPERM : ENOENT },
                                      choose: { _ in file }, start: { _ in true }, stop: { _ in stops += 1 })
        do {
            _ = try await access.acquire(file)
            Issue.record("Expected missing-file error")
        } catch {
            let error = error as NSError
            #expect(error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT))
        }
        #expect(stops == 1)
    }

    @Test func persistenceFailureDoesNotDiscardUsableSessionAccess() async throws {
        var reads = 0, stops = 0
        let access = SourceReadAccess(probe: { _ in reads += 1; return reads == 1 ? EPERM : nil },
                                      choose: { _ in file.deletingLastPathComponent() },
                                      start: { _ in true }, stop: { _ in stops += 1 },
                                      remember: { _ in throw CocoaError(.fileWriteUnknown) })
        let grant = try #require(try await access.acquire(file))
        #expect(grant.persistenceError != nil && stops == 0)
        grant.release()
        #expect(stops == 1)
    }

    @Test func implicitAccessWorksEvenWhenNoExplicitScopeIsStarted() async throws {
        var reads = 0
        let access = SourceReadAccess(probe: { _ in reads += 1; return reads == 1 ? EPERM : nil },
                                      choose: { _ in file }, start: { _ in false },
                                      stop: { _ in Issue.record("Unbalanced scope release") })
        let grant = try #require(try await access.acquire(file))
        grant.release()
    }

    @Test func openContinuesThroughTheRealEngineAfterRecovery() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let archive = folder.url.appending(path: "recovered.zip")
        try ZipFixture(entries: [.file("hello.txt", "recovered")]).write(to: archive)
        let original = try Data(contentsOf: archive)
        let app = AppState()
        var reads = 0, prompts = 0, stops = 0
        app.sourceReadAccess = SourceReadAccess(probe: { url in
            reads += 1
            return reads == 1 ? EPERM : OtherAppFiles.readError(url)
        }, choose: { _ in prompts += 1; return archive }, start: { _ in true }, stop: { _ in stops += 1 })
        app.open(archive)
        try await waitUntilFinished(app)
        #expect(app.openFailure == nil)
        #expect(app.browser?.archive.name == "recovered.zip")
        #expect(app.browser?.archive.files.contains(where: { $0.name == "hello.txt" }) == true)
        #expect(prompts == 1 && stops == 0)
        #expect(try Data(contentsOf: archive) == original)
        app.closeArchive()
        try await waitUntil { app.browser == nil }
        #expect(stops == 1)
    }

    @Test func supersededOpenCannotReplaceTheNewBrowserOrShowAnError() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let next = folder.url.appending(path: "next.zip")
        try ZipFixture(entries: [.file("next.txt", "next")]).write(to: next)
        let app = AppState()
        var continuation: CheckedContinuation<URL?, Never>?
        app.sourceReadAccess = SourceReadAccess(probe: { $0 == file ? EPERM : nil }, choose: { _ in
            await withCheckedContinuation { continuation = $0 }
        }, start: { _ in Issue.record("Superseded grant activated"); return true })
        app.open(file)
        try await waitUntil { continuation != nil }
        app.open(next)
        continuation?.resume(returning: file)
        try await waitUntilFinished(app)
        #expect(app.openFailure == nil)
        #expect(app.browser?.archive.name == "next.zip")
        app.closeArchive()
    }

    private func waitUntilFinished(_ app: AppState) async throws {
        try await waitUntil { !app.isOpening }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(20)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try #require(condition(), "Timed out waiting for source recovery")
    }
}

@Suite("Source folder bookmark persistence")
@MainActor
struct SourceFolderBookmarkTests {
    @Test func removingDemoGrantsPreservesRealAuthorization() throws {
        let name = "Stow.DemoGrants.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var starts = 0, stops = 0, writes = 0
        let operations = FolderAccess.Bookmarks(resolve: { data in
            (URL(filePath: String(decoding: data, as: UTF8.self)), false)
        }, create: { url in writes += 1; return Data(url.path.utf8) },
        start: { _ in starts += 1; return true }, stop: { _ in stops += 1 })
        let real = URL(filePath: "/Users/example/Attachments")
        let demo = URL(filePath: "/Volumes/Projects/Harbor")
        let store = FolderAccess(defaults: defaults, bookmarks: operations)
        try store.rememberSourceFolder(real)
        let saved = defaults.array(forKey: "FolderGrants") as? [Data]

        store.showGrantsForDemo([demo])
        #expect(store.displayedGrants == [demo])
        #expect(!store.covers(demo))
        store.removeDisplayedGrant(demo)
        #expect(store.displayedGrants.isEmpty)
        #expect(store.grants == [real] && store.covers(real))
        #expect(defaults.array(forKey: "FolderGrants") as? [Data] == saved)
        #expect(starts == 1 && stops == 0 && writes == 1)

        let restored = FolderAccess(defaults: defaults, bookmarks: operations)
        #expect(restored.displayedGrants == [real])
        restored.removeDisplayedGrant(real)
        #expect(restored.grants.isEmpty && stops == 1)
        store.revoke(real)
    }

    @Test func protectedDescendantSurvivesRestoreAndIndependentRemoval() throws {
        let name = "Stow.SourceGrants.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var starts: [URL] = [], stops: [URL] = []
        let operations = FolderAccess.Bookmarks(resolve: { data in
            (URL(filePath: String(decoding: data, as: UTF8.self)), false)
        }, create: { Data($0.path.utf8) }, start: { starts.append($0); return true }, stop: { stops.append($0) })
        let parent = URL(filePath: "/Users/example/Library")
        let child = parent.appending(path: "Containers/chat/Data/Files")
        let store = FolderAccess(defaults: defaults, bookmarks: operations)
        try store.rememberSourceFolder(parent)
        try store.rememberSourceFolder(child)
        #expect(store.grants == [parent, child])
        // A fresh explicit selection refreshes the old lease without losing the narrower grant.
        try store.rememberSourceFolder(parent)
        #expect(Set(store.grants) == [parent, child])
        #expect(stops == [parent])
        let restored = FolderAccess(defaults: defaults, bookmarks: operations)
        #expect(Set(restored.grants) == [parent, child])
        store.revoke(parent)
        #expect(store.grants == [child])
        let remaining = FolderAccess(defaults: defaults, bookmarks: operations)
        #expect(remaining.grants == [child])
        for grant in store.grants { store.revoke(grant) }
        for grant in restored.grants { restored.revoke(grant) }
        for grant in remaining.grants { remaining.revoke(grant) }
        #expect(starts.count == stops.count)
    }

    @Test func bookmarkFailurePreservesExistingSavedAndActiveGrants() throws {
        let name = "Stow.SourceGrants.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let old = URL(filePath: "/Users/example/Old")
        let new = URL(filePath: "/Users/example/New")
        var fail = false, starts = 0, stops = 0
        let operations = FolderAccess.Bookmarks(resolve: { data in
            (URL(filePath: String(decoding: data, as: UTF8.self)), false)
        }, create: { url in
            if fail { throw CocoaError(.fileWriteUnknown) }
            return Data(url.path.utf8)
        }, start: { _ in starts += 1; return true }, stop: { _ in stops += 1 })
        let store = FolderAccess(defaults: defaults, bookmarks: operations)
        try store.rememberSourceFolder(old)
        let saved = defaults.array(forKey: "FolderGrants") as? [Data]
        fail = true
        #expect(throws: CocoaError.self) { try store.rememberSourceFolder(new) }
        #expect(store.grants == [old] && starts == 1 && stops == 0)
        #expect(defaults.array(forKey: "FolderGrants") as? [Data] == saved)
        fail = false
        store.revoke(old)
        #expect(stops == 1)
    }

    @Test func staleBookmarkIsRefreshedAndUnresolvableBookmarkIsDropped() throws {
        let name = "Stow.SourceGrants.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let folder = URL(filePath: "/Users/example/Attachments")
        defaults.set([Data("stale".utf8), Data("missing".utf8)], forKey: "FolderGrants")
        let operations = FolderAccess.Bookmarks(resolve: { data in
            if data == Data("missing".utf8) { throw CocoaError(.fileNoSuchFile) }
            return (folder, true)
        }, create: { _ in Data("fresh".utf8) }, start: { _ in true }, stop: { _ in })
        let store = FolderAccess(defaults: defaults, bookmarks: operations)
        #expect(store.grants == [folder])
        #expect(defaults.array(forKey: "FolderGrants") as? [Data] == [Data("fresh".utf8)])
        store.revoke(folder)
    }
}
