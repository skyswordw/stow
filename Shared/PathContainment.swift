import Foundation

/// Keeps every extracted item inside the folder it was extracted into.
///
/// Three layers, outermost first: the engine's sandbox can only write to the staging folder it was
/// handed; 7-Zip rewrites `../` and absolute names and refuses links that point outside; and
/// `audit(staging:)` checks what actually landed on disk before anything is moved into place.
nonisolated enum PathContainment {
    /// The relative path an archive entry is written to: empty and `.` components dropped, `..`
    /// dropped (a trailing `..` becomes `_`), leading `/` removed. This mirrors 7-Zip 26.04 exactly —
    /// a test extracts hostile names with the bundled `7zz` and compares.
    static func containedPath(for archivePath: String) -> String {
        let parts = archivePath.split(separator: "/", omittingEmptySubsequences: true)
        var result: [Substring] = []
        for (index, part) in parts.enumerated() {
            switch part {
            case ".": continue
            case "..": if index == parts.count - 1 { result.append("_") }
            default: result.append(part)
            }
        }
        return result.isEmpty ? "_" : result.joined(separator: "/")
    }

    /// Whether the stored name tries to leave the destination (`..` anywhere, or absolute).
    static func escapes(_ archivePath: String) -> Bool {
        archivePath.hasPrefix("/") || archivePath.split(separator: "/").contains("..")
    }

    /// Lexical check for a link stored at `linkPath` (relative to the destination) pointing at
    /// `target`. Used for listing-time Checkup; `audit` does the authoritative on-disk check.
    static func linkEscapes(linkPath: String, target: String) -> Bool {
        if target.hasPrefix("/") { return true }
        var stack = containedPath(for: linkPath).split(separator: "/").dropLast().map(String.init)
        for part in target.split(separator: "/") {
            switch part {
            case ".": continue
            case "..":
                if stack.isEmpty { return true }
                stack.removeLast()
            default: stack.append(String(part))
            }
        }
        return false
    }

    /// Component-wise containment of two already-resolved absolute paths.
    static func isInside(_ path: String, root: String) -> Bool {
        let path = path.split(separator: "/")
        let root = root.split(separator: "/")
        return path.count >= root.count && Array(path.prefix(root.count)) == root
    }

    struct Audit: Equatable, Sendable {
        var removedLinks: [RemovedLink] = []
        var removedItems: [String] = []
    }

    /// Walks an extracted tree and removes anything that could reach outside `root`: symbolic links
    /// whose target resolves outside it (following link chains on disk), and device files or pipes.
    /// Clears set-user-ID and set-group-ID bits. Paths in the result are relative to `root`.
    static func audit(staging root: URL) throws -> Audit {
        let fileManager = FileManager.default
        let rootPath = resolvedPath(root.path)
        var audit = Audit()
        let keys: [URLResourceKey] = [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey]
        guard let walker = fileManager.enumerator(at: root, includingPropertiesForKeys: keys) else {
            return audit
        }
        // Collect first: removing while enumerating can skip siblings.
        let items = walker.compactMap { $0 as? URL }
        for item in items {
            let relative = String(item.path.dropFirst(root.path.count).drop { $0 == "/" })
            let values = try item.resourceValues(forKeys: Set(keys))
            if values.isSymbolicLink == true {
                let target = (try? fileManager.destinationOfSymbolicLink(atPath: item.path)) ?? ""
                if !linkStaysInside(item, target: target, root: rootPath) {
                    try fileManager.removeItem(at: item)
                    audit.removedLinks.append(RemovedLink(path: relative, target: target))
                }
            } else if values.isRegularFile == true {
                try clearSetIDBits(item)
            } else if values.isDirectory != true {
                try fileManager.removeItem(at: item)
                audit.removedItems.append(relative)
            }
        }
        return audit
    }

    private static func linkStaysInside(_ link: URL, target: String, root: String) -> Bool {
        guard !target.isEmpty else { return false }
        let base = target.hasPrefix("/") ? target : link.deletingLastPathComponent().path + "/" + target
        return isInside(resolvedPath(base), root: root)
    }

    /// `realpath` for the longest existing prefix, then lexical for the (nonexistent) rest —
    /// so dangling links are judged by where they would point.
    static func resolvedPath(_ path: String) -> String {
        var existing = path
        var rest: [String] = []
        while !existing.isEmpty, existing != "/" {
            if let real = realpath(existing, nil) {
                defer { free(real) }
                existing = String(cString: real)
                break
            }
            rest.insert((existing as NSString).lastPathComponent, at: 0)
            existing = (existing as NSString).deletingLastPathComponent
        }
        var parts = existing.split(separator: "/").map(String.init)
        for part in rest {
            switch part {
            case ".", "": continue
            case "..": if !parts.isEmpty { parts.removeLast() }
            default: parts.append(part)
            }
        }
        return "/" + parts.joined(separator: "/")
    }

    private static func clearSetIDBits(_ file: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard let mode = (attributes[.posixPermissions] as? NSNumber)?.uint16Value,
              mode & UInt16(S_ISUID | S_ISGID) != 0 else { return }
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: mode & ~UInt16(S_ISUID | S_ISGID))], ofItemAtPath: file.path)
    }
}
