import Foundation

/// A failure in plain words: what happened, what to do about it, and the one thing Stow can do
/// next. Every error alert, failed capsule and failed batch row says it the same way.
struct Failure: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case notAnArchive, damaged, needsPassword, diskFull, noWriteAccess, engine, other
    }

    /// The one next step a failure offers, besides dismissing it.
    enum Action: Equatable, Sendable {
        /// Run the same step again.
        case tryAgain
        /// Run it again somewhere else (the step asks where).
        case chooseFolder
        /// Reveal the file in Finder.
        case showInFinder
        /// Open the archive in Stow's window, where its password can be entered.
        case openInStow
        /// Hand the file to macOS (disk images Stow can't read; Finder mounts them).
        case openInFinder

        var title: String {
            switch self {
            case .tryAgain: String(localized: "Try Again")
            case .chooseFolder: String(localized: "Choose Another Folder")
            case .showInFinder: String(localized: "Show in Finder")
            case .openInStow: String(localized: "Open in Stow")
            case .openInFinder: String(localized: "Open in Finder")
            }
        }

        var symbol: String {
            switch self {
            case .tryAgain: "arrow.clockwise"
            case .chooseFolder: "folder.badge.plus"
            case .showInFinder: "folder"
            case .openInStow: "lock.open"
            case .openInFinder: "macwindow"
            }
        }
    }

    /// What Stow was doing; it picks the words for the catch-all case.
    enum Operation: Sendable {
        case open, extract, install, pack, copy

        func couldNot(_ name: String) -> String {
            switch self {
            case .open: String(localized: "Couldn’t open “\(name)”")
            case .extract: String(localized: "Couldn’t extract “\(name)”")
            case .install: String(localized: "Couldn’t install “\(name)”")
            case .pack: String(localized: "Couldn’t pack “\(name)”")
            case .copy: String(localized: "Couldn’t copy from “\(name)”")
            }
        }
    }

    var kind: Kind
    /// What happened, as a short sentence: "“Field Recordings.7z” is damaged".
    var title: String
    /// What to do about it: one or two sentences.
    var advice: String
    var action: Action?

    /// A few words for a row that already shows the file's name.
    var brief: String {
        switch kind {
        case .notAnArchive: String(localized: "Not an archive Stow can read")
        case .damaged: String(localized: "Damaged — download it again")
        case .needsPassword: String(localized: "Needs its password")
        case .diskFull: String(localized: "Not enough space")
        case .noWriteAccess: String(localized: "Can’t save to this folder")
        case .engine: title
        case .other: String(localized: "Didn’t finish — try again")
        }
    }

    var symbol: String {
        switch kind {
        case .needsPassword: "lock.fill"
        case .diskFull: "externaldrive.fill.badge.exclamationmark"
        case .noWriteAccess: "folder.fill.badge.minus"
        default: "exclamationmark.triangle.fill"
        }
    }

    /// A message that has no more to say (Stow's own limits, like nesting depth).
    init(_ title: String, advice: String = "", action: Action? = nil) {
        self.init(kind: .other, title: title, advice: advice, action: action)
    }

    init(kind: Kind, title: String, advice: String, action: Action? = nil) {
        self.kind = kind
        self.title = title
        self.advice = advice
        self.action = action
    }

    /// Explains `error` from `operation` on the archive (or file) `name`. `destination` is where
    /// Stow was writing, if anywhere: a full or read-only folder is recognised there even when the
    /// engine's words don't say so. `needs` is roughly how much it meant to write.
    init(_ error: any Error, _ operation: Operation, name: String, destination: URL? = nil, needs bytes: Int64 = 0) {
        let engine = EngineError(error)
        let cause = Self.cause(of: error, message: engine.message, destination: destination)
        switch (engine.failure, cause) {
        case (.notAnArchive, _):
            self.init(kind: .notAnArchive,
                      title: String(localized: "“\(name)” isn’t an archive Stow can read"),
                      advice: String(localized: "It may be another kind of file, or it didn’t finish downloading. Download it again, or open it with the app it came from."),
                      action: .showInFinder)
        case (.passwordRequired, _), (.wrongPassword, _):
            self.init(kind: .needsPassword,
                      title: String(localized: "“\(name)” needs its password"),
                      advice: String(localized: "Open it in Stow to enter the password, then extract it from there."),
                      action: .openInStow)
        case (.engineMissing, _), (.incompatibleVersion, _):
            self.init(kind: .engine, title: engine.message,
                      advice: String(localized: "Download Stow again and replace the copy in Applications. Your archives aren’t affected."))
        case (.connectionLost, _):
            self.init(kind: .engine, title: String(localized: "Stow’s archive engine stopped unexpectedly"),
                      advice: String(localized: "Nothing was left half-written. Try again; if it keeps happening, restart your Mac."),
                      action: .tryAgain)
        case (_, .damaged(let file)):
            let part = file.map { String(localized: "Part of it (“\($0)”) doesn’t match what was packed.") }
                ?? String(localized: "Part of it doesn’t match what was packed.")
            self.init(kind: .damaged, title: String(localized: "“\(name)” is damaged"),
                      advice: part + " " + String(localized: "Download it again, or ask the sender for a fresh copy."),
                      action: operation == .open ? .showInFinder : nil)
        case (_, .diskFull(let volume)):
            var needed = ""
            if bytes > 0, let free = destination.flatMap(Self.availableCapacity), free < bytes {
                needed = String(localized: "It needs about \(bytes.bytes); \(free.bytes) is free.") + " "
            }
            self.init(kind: .diskFull,
                      title: volume.map { String(localized: "There isn’t enough space on “\($0)”") }
                          ?? String(localized: "There isn’t enough space"),
                      advice: needed + String(localized: "Free up some space, or choose a folder on another disk. Nothing was left half-written."),
                      action: .chooseFolder)
        case (_, .noWriteAccess(let folder)):
            self.init(kind: .noWriteAccess,
                      title: folder.map { String(localized: "Stow can’t save to “\($0)”") }
                          ?? String(localized: "Stow can’t save there"),
                      advice: String(localized: "The folder is read-only or belongs to someone else. Choose another folder, such as Downloads."),
                      action: .chooseFolder)
        default:
            let detail = engine.message.trimmingCharacters(in: .whitespacesAndNewlines)
            let sentence = detail.isEmpty || detail.hasSuffix(".") ? detail : detail + "."
            self.init(kind: .other, title: operation.couldNot(name),
                      advice: (sentence.isEmpty ? "" : sentence + " ")
                          + String(localized: "Try again; if it fails the same way, the archive may be damaged."),
                      action: .tryAgain)
        }
    }

    // MARK: - Diagnosis

    enum Cause: Equatable {
        case damaged(file: String?)
        case diskFull(volume: String?)
        case noWriteAccess(folder: String?)
    }

    /// Reads the cause from the error's code when it still has one, from 7-Zip's own (English,
    /// unlocalised) words in the message, and finally from the destination itself.
    static func cause(of error: any Error, message: String, destination: URL?) -> Cause? {
        let volume = destination.flatMap(volumeName)
        let folder = destination.map { FileManager.default.displayName(atPath: $0.path) }
        if let code = posixCode(error) {
            if code == ENOSPC || code == EDQUOT { return .diskFull(volume: volume) }
            if code == EACCES || code == EPERM || code == EROFS { return .noWriteAccess(folder: folder) }
        }
        if let damage = damagedFile(in: message) { return .damaged(file: damage.isEmpty ? nil : damage) }
        let lower = message.lowercased()
        if ["no space left", "not enough space", "errno=28", "disk is full", "out of space"].contains(where: lower.contains) {
            return .diskFull(volume: volume)
        }
        if ["permission denied", "operation not permitted", "read-only file system", "errno=13", "errno=30", "don’t have permission"]
            .contains(where: lower.contains) {
            return .noWriteAccess(folder: folder)
        }
        guard let destination else { return nil }
        if let free = availableCapacity(destination), free < 1 << 20 { return .diskFull(volume: volume) }
        if FileManager.default.fileExists(atPath: destination.path), !FolderAccess.canWrite(destination) {
            return .noWriteAccess(folder: folder)
        }
        return nil
    }

    /// 7-Zip's damage reports: "Data Error : Docs/a.txt", "CRC Failed : …", "Unexpected end of
    /// archive", "Headers Error". Returns the damaged file's name ("" when 7-Zip didn't name one).
    static func damagedFile(in message: String) -> String? {
        let markers = ["Data Error", "CRC Failed", "Unexpected end of archive", "Headers Error", "Unconfirmed start of archive"]
        guard let marker = markers.first(where: message.contains) else { return nil }
        guard marker == "Data Error" || marker == "CRC Failed",
              let separator = message.range(of: " : ", options: .backwards) else { return "" }
        return message[separator.upperBound...].trimmingCharacters(in: .whitespaces)
    }

    private static func posixCode(_ error: any Error) -> Int32? {
        var current: NSError? = error as NSError
        while let error = current {
            if error.domain == NSPOSIXErrorDomain { return Int32(error.code) }
            if error.domain == NSCocoaErrorDomain {
                switch error.code {
                case NSFileWriteOutOfSpaceError: return ENOSPC
                case NSFileWriteNoPermissionError, NSFileWriteVolumeReadOnlyError: return EACCES
                default: break
                }
            }
            current = error.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return nil
    }

    static func availableCapacity(_ url: URL) -> Int64? {
        let existing = sequence(first: url) { $0.path == "/" ? nil : $0.deletingLastPathComponent() }
            .first { FileManager.default.fileExists(atPath: $0.path) }
        guard let values = try? existing?.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let capacity = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return capacity
    }

    private static func volumeName(_ url: URL) -> String? {
        try? url.resourceValues(forKeys: [.volumeLocalizedNameKey]).volumeLocalizedName
    }
}
