import AppKit
import UniformTypeIdentifiers

/// Files that come from other apps rather than Finder: chat apps (WeChat, QQ, WeCom, DingTalk,
/// Lark, Telegram) and Mail keep received files inside their own private storage under
/// ~/Library/Containers or ~/Library/Group Containers. Dropping one on Stow usually hands Stow
/// the right to read it; when macOS doesn't, Stow says so in plain words and how to get a copy
/// it can read, instead of a bare "permission denied". Some apps only promise a file while you
/// drag (Mail, Photos, chat attachments not yet downloaded); those are received into a folder of
/// Stow's own first.
enum OtherAppFiles {
    /// The app whose private storage holds a file.
    struct Owner: Equatable {
        var bundleID: String
        var name: String
    }

    /// Names for the apps people most often drag archives out of; anything else is looked up.
    static let knownNames: [String: String] = [
        "com.tencent.xinWeChat": "WeChat", "com.tencent.qq": "QQ", "com.tencent.WeWorkMac": "WeCom",
        "com.alibaba.DingTalkMac": "DingTalk", "com.bytedance.lark": "Lark", "com.electron.lark": "Lark",
        "ru.keepcoder.Telegram": "Telegram", "com.apple.mail": "Mail", "com.apple.MobileSMS": "Messages",
        "com.apple.Photos": "Photos",
    ]

    /// Who keeps `url`, from its path: `…/Library/Containers/<bundle ID>/…` or
    /// `…/Library/Group Containers/<team>.<group ID>/…`. Nil for ordinary folders and for Stow's own.
    static func owner(of url: URL) -> Owner? {
        let components = url.standardizedFileURL.pathComponents
        for (index, component) in components.enumerated() where index >= 1 && components[index - 1] == "Library" {
            guard component == "Containers" || component == "Group Containers", index + 1 < components.count else { continue }
            var identifier = components[index + 1]
            if component == "Group Containers" {
                // "5A4RE8SF68.com.tencent.xinWeChat" → "com.tencent.xinWeChat"; "group.x.y" → "x.y".
                let parts = identifier.split(separator: ".", maxSplits: 1).map(String.init)
                if parts.count == 2, parts[0] == "group" || isTeamID(parts[0]) { identifier = parts[1] }
            }
            if identifier.hasPrefix("app.stow") { return nil }
            return Owner(bundleID: identifier, name: name(for: identifier))
        }
        return nil
    }

    /// Apple team IDs: ten capital letters and digits.
    static func isTeamID(_ text: String) -> Bool {
        text.count == 10 && text.allSatisfy { $0.isASCII && ($0.isUppercase || $0.isNumber) }
    }

    static func name(for bundleID: String) -> String {
        if let known = knownNames[bundleID] { return known }
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
        }
        return bundleID.split(separator: ".").last.map(String.init) ?? bundleID
    }

    /// Whether Stow may read the file's contents right now (folders count as readable).
    static func canRead(_ url: URL) -> Bool {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NONBLOCK)
        guard descriptor >= 0 else { return errno != EACCES && errno != EPERM }
        close(descriptor)
        return true
    }

    /// The failure for a file macOS won't let Stow read, with the way to a copy it can read.
    static func unreadable(_ url: URL, owner: Owner? = nil) -> Failure {
        let name = url.lastPathComponent
        let advice = if let owner = owner ?? self.owner(of: url) {
            String(localized: "It’s kept in \(owner.name)’s own storage, which macOS keeps private. In \(owner.name), save it to Downloads or drag it to the desktop, then open that copy in Stow.")
        } else {
            String(localized: "macOS didn’t give Stow access to it. Drag it onto Stow from Finder, or choose it with File › Open Archive…, and macOS lets Stow read it.")
        }
        var failure = Failure(kind: .other, title: String(localized: "Stow isn’t allowed to read “\(name)”"),
                              advice: advice, action: .showInFinder, code: ErrorCode(.open, .noReadAccess))
        failure.diagnostic = "\(url.path) [\(NSPOSIXErrorDomain) \(EACCES)]"
        return failure
    }

    // MARK: Promised files

    /// Where promised files land: a folder of Stow's own, emptied at launch.
    static let receivedFolder = FileManager.default.temporaryDirectory.appending(path: "Received", directoryHint: .isDirectory)

    static func removeReceived() { try? FileManager.default.removeItem(at: receivedFolder) }

    /// Moves a file an app handed over (it disappears once the handler returns) into a folder of
    /// its own under `receivedFolder`, keeping its name. Synchronous on purpose: it must finish
    /// before the provider's handler returns.
    nonisolated static func keep(_ file: URL, named name: String?, in parent: URL) throws -> URL {
        let folder = parent.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var name = (name ?? file.lastPathComponent).replacingOccurrences(of: "/", with: "-")
        if name.isEmpty || name == "." || name == ".." { name = file.lastPathComponent }
        if (name as NSString).pathExtension.isEmpty, !file.pathExtension.isEmpty { name += "." + file.pathExtension }
        let target = folder.appending(path: name)
        try FileManager.default.copyItem(at: file, to: target)
        return target
    }

    /// Types a promised drop is accepted for: archives and disk images (what the drop zone opens).
    static let promisedTypes: [UTType] = [.archive, .diskImage, .zip]

    /// The files behind `providers` that don't carry a file URL (promises), received into Stow's folder.
    static func receive(_ providers: [NSItemProvider], into parent: URL = receivedFolder) async -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            guard let type = provider.registeredContentTypes.first(where: { type in promisedTypes.contains { type.conforms(to: $0) } })
            else { continue }
            let suggested = provider.suggestedName
            let url: URL? = await withCheckedContinuation { continuation in
                _ = provider.loadFileRepresentation(for: type, openInPlace: false) { file, _, _ in
                    continuation.resume(returning: file.flatMap { try? keep($0, named: suggested, in: parent) })
                }
            }
            if let url { urls.append(url) }
        }
        return urls
    }
}
