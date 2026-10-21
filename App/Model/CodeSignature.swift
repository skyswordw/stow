import Foundation
import Security

/// What macOS will think of an app before anyone opens it: code signature, who signed it and
/// whether Apple notarized it — told in plain words for Checkup and the install confirmation.
nonisolated enum CodeSignature {
    /// Raw facts read from the bundle with `SecStaticCode`.
    struct Facts: Equatable, Sendable {
        enum Validity: Equatable, Sendable { case valid, unsigned, invalid(OSStatus) }
        enum Anchor: Equatable, Sendable { case apple, appStore, developerID, other, none }

        var validity: Validity
        var isAdHoc = false
        var anchor: Anchor = .none
        var isNotarized = false
        /// "Developer ID Application: Jane Doe (TEAM123)" → "Jane Doe".
        var signer: String?
    }

    enum Verdict: Equatable, Sendable {
        case apple, appStore
        case notarized(signer: String?)
        case notNotarized(signer: String?)
        case adHoc, unsigned
        /// Signed, but files changed since — damaged or tampered with.
        case broken
        /// Signed with a certificate macOS doesn't trust for apps.
        case untrusted

        /// Whether installing should stop and ask first.
        var needsConfirmation: Bool {
            switch self {
            case .apple, .appStore, .notarized: false
            default: true
            }
        }

        /// One line naming the app: "“Harbor” isn’t notarized by Apple".
        func headline(app name: String) -> String {
            switch self {
            case .apple: "“\(name)” is made by Apple"
            case .appStore: "“\(name)” is from the Mac App Store"
            case .notarized: "“\(name)” is signed and notarized"
            case .notNotarized: "“\(name)” isn’t notarized by Apple"
            case .adHoc: "“\(name)” isn’t signed by a known developer"
            case .unsigned: "“\(name)” isn’t signed"
            case .broken: "“\(name)” has a broken signature"
            case .untrusted: "“\(name)” is signed with an unknown certificate"
            }
        }

        var finding: CheckupFinding {
            switch self {
            case .apple:
                CheckupFinding(severity: .fine, title: "Made by Apple", detail: "Signed by Apple and unchanged.")
            case .appStore:
                CheckupFinding(severity: .fine, title: "From the Mac App Store", detail: "Signed by Apple for the App Store and unchanged.")
            case .notarized(let signer):
                CheckupFinding(severity: .fine, title: "Signed and notarized",
                               detail: "Signed by \(signer ?? "a registered developer") and checked by Apple for malware.")
            case .notNotarized(let signer):
                CheckupFinding(severity: .caution, title: "Not notarized by Apple",
                               detail: "Signed by \(signer ?? "a registered developer"), but Apple hasn’t checked it for malware. macOS will block it the first time unless you allow it in System Settings › Privacy & Security.")
            case .adHoc:
                CheckupFinding(severity: .caution, title: "Not signed by a known developer",
                               detail: "It carries only a local signature, so nobody vouches for who made it. macOS will block it the first time it opens.")
            case .unsigned:
                CheckupFinding(severity: .caution, title: "Not signed",
                               detail: "There’s no signature, so there’s no way to tell who made it or whether it was changed. macOS will block it the first time it opens.")
            case .broken:
                CheckupFinding(severity: .caution, title: "Signature is broken",
                               detail: "Files inside changed after the developer signed it. It may be damaged or tampered with — get a fresh copy from the developer.")
            case .untrusted:
                CheckupFinding(severity: .caution, title: "Signed by an unknown certificate",
                               detail: "The certificate isn’t one macOS trusts for apps, so the signature says nothing about who made it.")
            }
        }
    }

    static func classify(_ facts: Facts) -> Verdict {
        switch facts.validity {
        case .unsigned: return .unsigned
        case .invalid: return .broken
        case .valid: break
        }
        if facts.isAdHoc { return .adHoc }
        switch facts.anchor {
        case .apple: return .apple
        case .appStore: return .appStore
        case .developerID: return facts.isNotarized ? .notarized(signer: facts.signer) : .notNotarized(signer: facts.signer)
        case .other, .none: return .untrusted
        }
    }

    static func assess(_ bundle: URL) -> Verdict { classify(facts(for: bundle)) }

    static func facts(for bundle: URL) -> Facts {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundle as CFURL, [], &code) == errSecSuccess, let code else {
            return Facts(validity: .unsigned)
        }
        let strict = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        let status = SecStaticCodeCheckValidityWithErrors(code, strict, nil, nil)
        var facts = Facts(validity: status == errSecSuccess ? .valid
                          : status == errSecCSUnsigned ? .unsigned : .invalid(status))
        var info: CFDictionary?
        SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        let details = info as? [String: Any] ?? [:]
        let flags = (details[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        facts.isAdHoc = flags & SecCodeSignatureFlags.adhoc.rawValue != 0
        let leaf = (details[kSecCodeInfoCertificates as String] as? [SecCertificate])?.first
        facts.signer = leaf.flatMap { SecCertificateCopySubjectSummary($0) as String? }.map(signerName)
        guard facts.validity == .valid else { return facts }

        func satisfies(_ requirement: String) -> Bool {
            var compiled: SecRequirement?
            guard SecRequirementCreateWithString(requirement as CFString, [], &compiled) == errSecSuccess else { return false }
            return SecStaticCodeCheckValidity(code, [], compiled) == errSecSuccess
        }
        facts.anchor = if satisfies("anchor apple") { .apple }
            else if satisfies("anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.9]") { .appStore }
            else if satisfies("anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists") { .developerID }
            else if leaf != nil { .other } else { .none }
        facts.isNotarized = facts.anchor == .developerID && satisfies("notarized")
        return facts
    }

    /// "Developer ID Application: Jane Doe (TEAM123)" → "Jane Doe".
    static func signerName(_ summary: String) -> String {
        var name = summary
        if let colon = name.range(of: ": ") { name = String(name[colon.upperBound...]) }
        if name.hasSuffix(")"), let open = name.range(of: " (", options: .backwards) { name = String(name[..<open.lowerBound]) }
        return name
    }
}
