import Foundation
import Testing
@testable import Stow

@Suite("Failures in plain words")
@MainActor
struct FailureTests {
    @Test func runningAppOffersRetryWithoutDamageAdvice() {
        // Typed conditions win over both message and destination heuristics.
        let message = "“Data Error” is open. Quit it, then install again."
        let error = EngineError(.appRunning, message)
        for wrapped in [error, EngineError(error.nsError)] {
            let failure = Failure(wrapped, .install, name: "Tool", destination: URL(filePath: "/tmp"))
            #expect(failure.kind == .appRunning && failure.action == .tryAgain)
            #expect(failure.code.description == "INS-161")
            #expect(failure.advice == message)
            #expect(failure.brief == message)
            #expect(!failure.report.contains("archive may be damaged"))
        }
    }

    @Test func notAnArchiveOffersFinder() {
        let failure = Failure(EngineError(.notAnArchive), .open, name: "Invoice.pdf")
        #expect(failure.kind == .notAnArchive && failure.action == .showInFinder)
        #expect(failure.title.contains("Invoice.pdf"))
    }

    @Test(arguments: ["CRC Failed : Docs/Q3.pdf", "Data Error : Docs/Q3.pdf"])
    func damagedDataNamesTheFile(_ message: String) {
        let failure = Failure(EngineError(.failed, message), .extract, name: "Backup.zip")
        #expect(failure.kind == .damaged && failure.action == nil)
        #expect(failure.advice.contains("Docs/Q3.pdf"))
    }

    @Test func damagedHeadersAreDamageToo() {
        let failure = Failure(EngineError(.failed, "7-Zip couldn’t finish: Unexpected end of archive"), .open, name: "Backup.zip")
        #expect(failure.kind == .damaged && failure.action == .showInFinder)
        #expect(Failure.damagedFile(in: "Headers Error") == "")
        #expect(Failure.damagedFile(in: "Something else") == nil)
    }

    @Test func passwordsSendPeopleToTheBrowser() {
        for error in [EngineError(.passwordRequired), EngineError(.wrongPassword)] {
            let failure = Failure(error, .extract, name: "Locked.7z")
            #expect(failure.kind == .needsPassword && failure.action == .openInStow)
        }
    }

    @Test func fullDiskFromCodesAndWords() {
        let posix = Failure(NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC)), .extract, name: "Big.zip")
        let cocoa = Failure(NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError), .pack, name: "Big.zip")
        let words = Failure(EngineError(.failed, "7-Zip couldn’t finish: errno=28 : No space left on device"), .extract, name: "Big.zip")
        for failure in [posix, cocoa, words] {
            #expect(failure.kind == .diskFull && failure.action == .chooseFolder)
        }
    }

    @Test func noWriteAccessFromCodesAndTheFolder() throws {
        let cocoa = Failure(NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError), .extract, name: "A.zip",
                            destination: URL(filePath: "/Users/Shared"))
        #expect(cocoa.kind == .noWriteAccess && cocoa.title.contains("Shared"))
        // A folder Stow can't write to explains a failure whose words don't.
        let locked = FileManager.default.temporaryDirectory.appending(path: "Locked \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: locked.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: locked.path)
            try? FileManager.default.removeItem(at: locked)
        }
        let folder = Failure(EngineError(.failed, "7-Zip couldn’t finish: E_FAIL"), .extract, name: "A.zip", destination: locked)
        #expect(folder.kind == .noWriteAccess && folder.action == .chooseFolder)
    }

    @Test func anythingElseSaysWhatStowWasDoingAndOffersTryAgain() {
        let failure = Failure(EngineError(.failed, "7-Zip couldn’t finish: E_FAIL"), .install, name: "Harbor")
        #expect(failure.kind == .other && failure.action == .tryAgain)
        #expect(failure.title == Failure.Operation.install.couldNot("Harbor"))
        #expect(failure.advice.hasPrefix("7-Zip couldn’t finish: E_FAIL."))
    }

    @Test func inputPermissionFailuresNeverOfferDestinationRecovery() {
        let errors: [any Error] = [
            NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM)),
            EngineError(.failed, "inner.zip : opening : errno=1 : Operation not permitted"),
        ]
        for error in errors {
            let failure = Failure(error, .open, name: "inner.zip")
            #expect(failure.kind == .noReadAccess)
            #expect(failure.action == .tryAgain)
            #expect(failure.code == ErrorCode(.open, .noReadAccess))
        }
        let failure = Failure(EngineError(.failed, "inner.zip : opening : errno=1 : Operation not permitted"),
                              .extract, name: "inner.zip", destination: URL(filePath: "/tmp"))
        #expect(failure.kind == .noReadAccess && failure.action != .chooseFolder)
    }

    @Test func briefWordsForRows() {
        #expect(Failure(EngineError(.passwordRequired), .extract, name: "x").brief != "")
        let other = Failure(EngineError(.failed, "boom"), .extract, name: "x")
        #expect(!other.brief.contains("x.zip"))
    }
}
