import AppKit

/// A stable code for every failure Stow explains, for bug reports: "EXT-120" is "extracting, the
/// archive's data is damaged" in any language and in every version. Never renumber: add new reasons
/// with new numbers. The table lives in ERROR-CODES.md, and `ErrorCodeTests` pins it.
nonisolated struct ErrorCode: Hashable, Sendable, CustomStringConvertible {
    /// What Stow was doing.
    enum Area: String, CaseIterable, Sendable {
        case open = "OPN", extract = "EXT", install = "INS", pack = "PCK", copy = "CPY", general = "GEN"
    }

    /// Why it failed. Hundreds group causes: 10x the file, 11x passwords, 12x damage, 13x–14x the
    /// destination, 15x the engine, 16x–18x Stow's own rules, 199 anything else.
    enum Reason: Int, CaseIterable, Sendable {
        case notAnArchive = 100
        case passwordRequired = 110
        case wrongPassword = 111
        case damagedData = 120
        case damagedStructure = 121
        case diskFull = 130
        case noWriteAccess = 140
        case engineMissing = 150
        case engineOutdated = 151
        case engineStopped = 152
        case changedOnDisk = 160
        case cancelled = 170
        case limit = 180
        case unknown = 199
    }

    var area: Area
    var reason: Reason

    init(_ area: Area, _ reason: Reason) {
        self.area = area
        self.reason = reason
    }

    var description: String { "\(area.rawValue)-\(reason.rawValue)" }

    /// The engine's own failure, before Stow reads a cause from its words.
    static func reason(for failure: EngineFailure) -> Reason {
        switch failure {
        case .incompatibleVersion: .engineOutdated
        case .engineMissing: .engineMissing
        case .connectionLost: .engineStopped
        case .notAnArchive: .notAnArchive
        case .passwordRequired: .passwordRequired
        case .wrongPassword: .wrongPassword
        case .cancelled: .cancelled
        case .failed: .unknown
        case .changedOnDisk: .changedOnDisk
        }
    }
}

extension Failure.Operation {
    var area: ErrorCode.Area {
        switch self {
        case .open: .open
        case .extract: .extract
        case .install: .install
        case .pack: .pack
        case .copy: .copy
        }
    }
}

/// Everything a bug report needs about one failure, as plain text people can paste into an email
/// or an issue. Labels stay in English so whoever reads the report can; the title and advice are
/// what people saw, in their language.
enum ErrorReport {
    static func text(for failure: Failure, date: Date = .now, environment: Environment = .current) -> String {
        var lines = ["Stow error \(failure.code)", failure.title]
        if !failure.advice.isEmpty { lines.append(failure.advice) }
        lines.append("")
        if !failure.diagnostic.isEmpty {
            lines.append("Details: " + failure.diagnostic)
        }
        lines.append("Stow \(environment.appVersion) · macOS \(environment.systemVersion) · \(environment.architecture)")
        lines.append("Time: " + Date.ISO8601FormatStyle(timeZone: .current).format(date))
        return lines.joined(separator: "\n")
    }

    struct Environment: Sendable {
        var appVersion: String
        var systemVersion: String
        var architecture: String

        static var current: Environment {
            let info = Bundle.main.infoDictionary ?? [:]
            let version = info["CFBundleShortVersionString"] as? String ?? "?"
            let build = info["CFBundleVersion"] as? String ?? "?"
            let system = ProcessInfo.processInfo.operatingSystemVersion
            #if arch(arm64)
            let architecture = "Apple silicon"
            #else
            let architecture = "Intel"
            #endif
            return Environment(appVersion: "\(version) (\(build))",
                               systemVersion: "\(system.majorVersion).\(system.minorVersion).\(system.patchVersion)",
                               architecture: architecture)
        }
    }

    /// The error's own words and every domain and code under it, outermost first:
    /// "No space left on device [NSCocoaErrorDomain 640 → NSPOSIXErrorDomain 28]".
    static func diagnostic(for error: any Error, message: String) -> String {
        var codes: [String] = []
        var current: NSError? = (error as? EngineError)?.nsError ?? error as NSError
        while let error = current, codes.count < 6 {
            codes.append("\(error.domain) \(error.code)")
            current = error.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        let words = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let chain = codes.isEmpty ? "" : "[" + codes.joined(separator: " → ") + "]"
        return [words, chain].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

extension ErrorReport {
    /// What a failure's "Copy Details" needs: the code to show and the text to copy.
    struct Copyable: Equatable {
        var code: String
        var text: String

        init(_ failure: Failure) {
            code = failure.code.description
            text = failure.report
        }

        func copy(to pasteboard: NSPasteboard = .general) {
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }
    }
}
