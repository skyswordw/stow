import Foundation
import Testing
@testable import Stow

@Suite("Code signature")
struct CodeSignatureTests {
    typealias Facts = CodeSignature.Facts

    @Test(arguments: [
        (Facts(validity: .unsigned), CodeSignature.Verdict.unsigned),
        (Facts(validity: .invalid(-67054), anchor: .developerID), .broken),
        (Facts(validity: .valid, isAdHoc: true), .adHoc),
        (Facts(validity: .valid, anchor: .apple), .apple),
        (Facts(validity: .valid, anchor: .appStore), .appStore),
        (Facts(validity: .valid, anchor: .developerID, isNotarized: true, signer: "Jane"), .notarized(signer: "Jane")),
        (Facts(validity: .valid, anchor: .developerID, signer: "Jane"), .notNotarized(signer: "Jane")),
        (Facts(validity: .valid, anchor: .other), .untrusted),
    ])
    func classification(facts: Facts, verdict: CodeSignature.Verdict) {
        #expect(CodeSignature.classify(facts) == verdict)
        #expect(verdict.needsConfirmation == (verdict.finding.severity == .caution))
    }

    @Test func signerNameDropsRoleAndTeam() {
        #expect(CodeSignature.signerName("Developer ID Application: Jane Doe (TEAM123)") == "Jane Doe")
        #expect(CodeSignature.signerName("Apple Mac OS Application Signing") == "Apple Mac OS Application Signing")
    }

    @Test func systemAppIsApple() {
        #expect(CodeSignature.assess(URL(filePath: "/System/Applications/Calculator.app")) == .apple)
    }

    @Test func unsignedAndBrokenBundles() throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let app = folder.url.appending(path: "Plain.app/Contents/MacOS", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: app.appending(path: "Plain"))
        #expect(CodeSignature.assess(folder.url.appending(path: "Plain.app")) == .unsigned)
    }
}
