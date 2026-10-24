import AppKit
import Foundation
import Testing
@testable import Stow

@Suite("Error codes and details")
@MainActor
struct ErrorCodeTests {
    /// The published table (ERROR-CODES.md). Changing a number breaks every bug report that quotes it.
    @Test func tableIsPinned() {
        let reasons = Dictionary(uniqueKeysWithValues: ErrorCode.Reason.allCases.map { ("\($0)", $0.rawValue) })
        #expect(reasons == [
            "notAnArchive": 100, "noReadAccess": 101, "missingVolume": 102, "passwordRequired": 110, "wrongPassword": 111,
            "damagedData": 120, "damagedStructure": 121, "diskFull": 130, "noWriteAccess": 140,
            "engineMissing": 150, "engineOutdated": 151, "engineStopped": 152,
            "changedOnDisk": 160, "cancelled": 170, "limit": 180, "unknown": 199,
        ])
        #expect(ErrorCode.Area.allCases.map(\.rawValue) == ["OPN", "EXT", "INS", "PCK", "CPY", "GEN"])
        #expect(ErrorCode(.extract, .damagedData).description == "EXT-120")
    }

    @Test func engineFailuresMapOneToOne() {
        let pairs: [(EngineFailure, ErrorCode.Reason)] = [
            (.incompatibleVersion, .engineOutdated), (.engineMissing, .engineMissing), (.connectionLost, .engineStopped),
            (.notAnArchive, .notAnArchive), (.passwordRequired, .passwordRequired), (.wrongPassword, .wrongPassword),
            (.missingVolume, .missingVolume), (.cancelled, .cancelled), (.failed, .unknown), (.changedOnDisk, .changedOnDisk),
        ]
        for (failure, reason) in pairs { #expect(ErrorCode.reason(for: failure) == reason) }
        // Engine raw values cross XPC; they're part of the contract too.
        #expect(EngineFailure.incompatibleVersion.rawValue == 1 && EngineFailure.changedOnDisk.rawValue == 9)
    }

    @Test func failuresCarryStableCodes() {
        let cases: [(any Error, Failure.Operation, String)] = [
            (EngineError(.notAnArchive), Failure.Operation.open, "OPN-100"),
            (EngineError(.missingVolume), .open, "OPN-102"),
            (EngineError(.passwordRequired), .extract, "EXT-110"),
            (EngineError(.wrongPassword), .extract, "EXT-111"),
            (EngineError(.failed, "Data Error : Docs/Q3.pdf"), .extract, "EXT-120"),
            (EngineError(.failed, "CRC Failed : Docs/Q3.pdf"), .copy, "CPY-120"),
            (EngineError(.failed, "7-Zip couldn’t finish: Unexpected end of archive"), .open, "OPN-121"),
            (EngineError(.failed, "Headers Error"), .open, "OPN-121"),
            (NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC)), .pack, "PCK-130"),
            (NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError), .extract, "EXT-130"),
            (NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError), .install, "INS-140"),
            (EngineError(.engineMissing), .extract, "EXT-150"),
            (EngineError(.incompatibleVersion), .open, "OPN-151"),
            (EngineError(.connectionLost), .pack, "PCK-152"),
            (EngineError(.changedOnDisk), .open, "OPN-160"),
            (EngineError(.failed, "E_FAIL"), .extract, "EXT-199"),
        ]
        for (error, operation, code) in cases {
            #expect(Failure(error, operation, name: "Backup.zip").code.description == code, "\(error)")
        }
    }

    @Test func stowsOwnMessagesHaveCodesToo() {
        #expect(Failure("Too deep").code == ErrorCode(.general, .limit))
        #expect(Failure(kind: .diskFull, title: "t", advice: "").code.description == "GEN-130")
        #expect(Failure(kind: .other, title: "t", advice: "", code: ErrorCode(.open, .limit)).code.description == "OPN-180")
    }

    @Test func diagnosticKeepsWordsAndEveryCode() {
        let posix = NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))
        let cocoa = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError,
                            userInfo: [NSUnderlyingErrorKey: posix])
        #expect(ErrorReport.diagnostic(for: cocoa, message: " No space left on device \n")
            == "No space left on device [NSCocoaErrorDomain 640 → NSPOSIXErrorDomain 28]")
        let failure = Failure(EngineError(.failed, "Data Error : Docs/Q3.pdf"), .extract, name: "Backup.zip")
        #expect(failure.diagnostic == "Data Error : Docs/Q3.pdf [app.stow.engine 8]")
    }

    @Test func reportHasEverythingABugReportNeeds() {
        let failure = Failure(EngineError(.failed, "CRC Failed : Docs/Q3.pdf"), .extract, name: "Backup.zip")
        let environment = ErrorReport.Environment(appVersion: "0.1.0 (1)", systemVersion: "27.0.0", architecture: "Apple silicon")
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let text = ErrorReport.text(for: failure, date: date, environment: environment)
        let lines = text.components(separatedBy: "\n")
        #expect(lines[0] == "Stow error EXT-120")
        #expect(lines[1] == failure.title)
        #expect(lines[2] == failure.advice)
        #expect(text.contains("Details: CRC Failed : Docs/Q3.pdf [app.stow.engine 8]"))
        #expect(text.contains("Stow 0.1.0 (1) · macOS 27.0.0 · Apple silicon"))
        #expect(text.contains("Time: " + Date.ISO8601FormatStyle(timeZone: .current).format(date)))
        #expect(!failure.report.isEmpty && failure.report.hasPrefix("Stow error EXT-120"))
    }

    @Test func copyPutsTheReportOnThePasteboard() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("StowTests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let failure = Failure(EngineError(.notAnArchive), .open, name: "Invoice.pdf")
        let copyable = ErrorReport.Copyable(failure)
        #expect(copyable.code == "OPN-100")
        copyable.copy(to: pasteboard)
        #expect(pasteboard.string(forType: .string) == copyable.text)
    }

    @Test func failureCardsOfferCopyDetails() {
        let failure = Failure(EngineError(.connectionLost), .pack, name: "Handoff.zip")
        let prompt = Prompt(failure)
        #expect(prompt.report?.code == "PCK-152")
        #expect(prompt.report?.text.hasPrefix("Stow error PCK-152") == true)
    }
}
