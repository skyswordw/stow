import Foundation

/// Turns what the engine saw into plain-word Checkup findings — before extracting (from the listing)
/// and after (from what the containment audit removed).
nonisolated enum Checkup {
    struct ListingScan: Sendable {
        var escapingPaths: [String] = []
        var links: [ListedEntry] = []
        var helperFiles = 0
        var encryptedFiles = 0
        var caseCollisions: [[String]] = []
        var totalSize: Int64 = 0
        var archiveSize: Int64 = 0
    }

    static func findings(for scan: ListingScan) -> [CheckupFinding] {
        var findings: [CheckupFinding] = []

        if let first = scan.escapingPaths.first {
            let count = scan.escapingPaths.count
            findings.append(CheckupFinding(
                severity: .handled,
                title: count == 1 ? "1 path tried to leave the folder" : "\(count) paths tried to leave the folder",
                detail: count == 1
                    ? "“\(first)” will be kept inside the destination folder instead."
                    : "“\(first)” and \(count - 1) more will be kept inside the destination folder instead."
            ))
        }

        let outsideLinks = scan.links.filter { link in
            link.linkTarget.map { PathContainment.linkEscapes(linkPath: link.path, target: $0) } ?? false
        }
        if !outsideLinks.isEmpty {
            findings.append(CheckupFinding(
                severity: .handled,
                title: plural(outsideLinks.count, "link points", "links point") + " outside the folder",
                detail: "“\(outsideLinks[0].path)” → “\(outsideLinks[0].linkTarget ?? "")”. Links like this aren’t created when you extract."
            ))
        } else if !scan.links.isEmpty {
            findings.append(CheckupFinding(
                severity: .info,
                title: plural(scan.links.count, "symbolic link", "symbolic links") + " inside",
                detail: "Any that point outside the destination folder are left out when you extract."
            ))
        }

        if let collision = scan.caseCollisions.first, collision.count > 1 {
            findings.append(CheckupFinding(
                severity: .caution,
                title: plural(scan.caseCollisions.count, "name differs", "names differ") + " only by capital letters",
                detail: "“\(collision[0])” and “\(collision[1])” can’t sit side by side on this Mac. Both are kept; the second gets a number added."
            ))
        }

        let ratio = Double(scan.totalSize) / Double(max(scan.archiveSize, 1))
        if scan.totalSize > 1_000_000_000, ratio > 100 {
            findings.append(CheckupFinding(
                severity: .caution,
                title: "Expands to \(scan.totalSize.bytes)",
                detail: "That’s \(Int(ratio))× the size of the archive. Make sure there’s room before extracting."
            ))
        }

        if scan.encryptedFiles > 0 {
            findings.append(CheckupFinding(
                severity: .info,
                title: "Contents are encrypted",
                detail: "You’ll need the password to extract \(scan.encryptedFiles == 1 ? "the file" : "these files")."
            ))
        }

        if scan.helperFiles > 0 {
            findings.append(CheckupFinding(
                severity: .info,
                title: plural(scan.helperFiles, "macOS helper file", "macOS helper files") + " hidden",
                detail: "“.DS_Store” and “._” files are hidden here and won’t be extracted."
            ))
        }

        if !findings.contains(where: { $0.severity == .handled || $0.severity == .caution }) {
            findings.append(CheckupFinding(
                severity: .fine,
                title: "Names and sizes look normal",
                detail: "Nothing tries to leave the folder, nothing expands unusually and no names collide."
            ))
        }
        return findings
    }

    /// What the on-disk audit had to remove during an extraction.
    static func findings(for report: ExtractReport) -> [CheckupFinding] {
        var findings: [CheckupFinding] = []
        if let first = report.removedLinks.first {
            findings.append(CheckupFinding(
                severity: .handled,
                title: plural(report.removedLinks.count, "link pointed", "links pointed") + " outside the folder",
                detail: "“\(first.path)” → “\(first.target)” was left out so nothing outside the folder can be reached."
            ))
        }
        if let first = report.removedItems.first {
            findings.append(CheckupFinding(
                severity: .handled,
                title: plural(report.removedItems.count, "special file", "special files") + " left out",
                detail: "“\(first)” is a device file or pipe, which can’t be extracted safely."
            ))
        }
        return findings
    }

    private static func plural(_ count: Int, _ one: String, _ many: String) -> String {
        "\(count) \(count == 1 ? one : many)"
    }
}

nonisolated extension Archive {
    /// Maps an engine listing into the browser's model: names are shown where they will actually be
    /// written, folders are synthesized from file paths, and the listing-time Checkup runs.
    init(listing: ArchiveListing, url: URL) {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let fallbackDate = values?.contentModificationDate ?? .now
        var scan = Checkup.ListingScan(archiveSize: listing.physicalSize ?? Int64(values?.fileSize ?? 0))
        var storedPaths: [String: [String]] = [:]
        var files: [String: ArchiveEntry] = [:]
        var explicitFolders: [String: Date] = [:]

        for item in listing.entries {
            if MacHelperFiles.matches(item.path) {
                if !item.isFolder { scan.helperFiles += 1 }
                continue
            }
            let path = PathContainment.containedPath(for: item.path)
            storedPaths[path, default: []].append(item.path)
            if PathContainment.escapes(item.path) { scan.escapingPaths.append(item.path) }
            if item.isSymlink { scan.links.append(item) }
            if item.isEncrypted { scan.encryptedFiles += 1 }
            if item.isFolder {
                explicitFolders[path] = item.modified ?? fallbackDate
            } else {
                files[path] = ArchiveEntry(path: path, isFolder: false, size: item.size,
                                           packedSize: item.packedSize ?? 0,
                                           modified: item.modified ?? fallbackDate)
            }
        }

        // Explicit folder entries only matter when empty; the rest are synthesized from file paths.
        var ancestors = Set<String>()
        for path in files.keys {
            var parent = (path as NSString).deletingLastPathComponent
            while !parent.isEmpty, ancestors.insert(parent).inserted {
                parent = (parent as NSString).deletingLastPathComponent
            }
        }
        var entries = Array(files.values)
        for (path, modified) in explicitFolders where !ancestors.contains(path) && files[path] == nil {
            entries.append(ArchiveEntry(path: path, isFolder: true, size: 0, packedSize: 0, modified: modified))
        }

        scan.totalSize = files.values.reduce(0) { $0 + $1.size }
        scan.caseCollisions = Dictionary(grouping: files.keys) { $0.lowercased() }
            .values.filter { $0.count > 1 }.map { $0.sorted() }.sorted { $0[0] < $1[0] }

        self.init(name: url.lastPathComponent,
                  format: ArchiveFormat(sevenZipType: listing.type, name: url.lastPathComponent),
                  isEncrypted: scan.encryptedFiles > 0,
                  files: entries,
                  checkup: Checkup.findings(for: scan))
        source = ArchiveSource(url: url, storedPaths: storedPaths)
    }

    /// The archive's own names for these entries; a folder stands for everything under it.
    func storedPaths(for selection: [ArchiveEntry]) -> [String] {
        guard let source else { return [] }
        var paths: [String] = []
        for entry in selection {
            paths += source.storedPaths[entry.path] ?? []
            if entry.isFolder {
                let prefix = entry.path + "/"
                for (path, stored) in source.storedPaths where path.hasPrefix(prefix) {
                    paths += stored
                }
            }
        }
        return Array(Set(paths)).sorted()
    }

    /// Adds findings from an extraction, once each.
    mutating func record(_ findings: [CheckupFinding]) {
        for finding in findings where !checkup.contains(where: { $0.title == finding.title }) {
            checkup.insert(finding, at: checkup.firstIndex { $0.severity == .info || $0.severity == .fine } ?? checkup.endIndex)
        }
        if checkup.contains(where: { $0.severity == .handled }) {
            checkup.removeAll { $0.severity == .fine }
        }
    }
}
