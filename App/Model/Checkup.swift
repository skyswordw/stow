import Foundation

/// Turns what the engine saw into plain-word Checkup findings — before extracting (from the listing)
/// and after (from what the containment audit removed).
nonisolated enum Checkup {
    struct ListingScan: Sendable {
        var escapingPaths: [String] = []
        var links: [ListedEntry] = []
        var helperFiles = 0
        var installerExtras = 0
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
                title: count == 1 ? String(localized: "1 path tried to leave the folder") : String(localized: "\(count) paths tried to leave the folder"),
                detail: count == 1
                    ? String(localized: "“\(first)” will be kept inside the destination folder instead.")
                    : String(localized: "“\(first)” and \(count - 1) more will be kept inside the destination folder instead.")
            ))
        }

        let outsideLinks = scan.links.filter { link in
            link.linkTarget.map { PathContainment.linkEscapes(linkPath: link.path, target: $0) } ?? false
        }
        if !outsideLinks.isEmpty {
            findings.append(CheckupFinding(
                severity: .handled,
                title: String(localized: "\(outsideLinks.count) links point outside the folder"),
                detail: String(localized: "“\(outsideLinks[0].path)” → “\(outsideLinks[0].linkTarget ?? "")”. Links like this aren’t created when you extract.")
            ))
        } else if !scan.links.isEmpty {
            findings.append(CheckupFinding(
                severity: .info,
                title: String(localized: "\(scan.links.count) symbolic links inside"),
                detail: String(localized: "Any that point outside the destination folder are left out when you extract.")
            ))
        }

        if let collision = scan.caseCollisions.first, collision.count > 1 {
            findings.append(CheckupFinding(
                severity: .caution,
                title: String(localized: "\(scan.caseCollisions.count) names differ only by capital letters"),
                detail: String(localized: "“\(collision[0])” and “\(collision[1])” can’t sit side by side on this Mac. Both are kept; the second gets a number added.")
            ))
        }

        let ratio = Double(scan.totalSize) / Double(max(scan.archiveSize, 1))
        if scan.totalSize > 1_000_000_000, ratio > 100 {
            findings.append(CheckupFinding(
                severity: .caution,
                title: String(localized: "Expands to \(scan.totalSize.bytes)"),
                detail: String(localized: "That’s \(Int(ratio))× the size of the archive. Make sure there’s room before extracting.")
            ))
        }

        if scan.encryptedFiles > 0 {
            findings.append(CheckupFinding(
                severity: .info,
                title: String(localized: "Contents are encrypted"),
                detail: String(localized: "You’ll need the password to extract \(scan.encryptedFiles == 1 ? String(localized: "the file") : String(localized: "these files")).")
            ))
        }

        if scan.helperFiles > 0 {
            findings.append(CheckupFinding(
                severity: .info,
                title: String(localized: "\(scan.helperFiles) macOS helper files hidden"),
                detail: String(localized: "“.DS_Store” and “._” files are hidden here and won’t be extracted.")
            ))
        }

        if scan.installerExtras > 0 {
            findings.append(CheckupFinding(
                severity: .info,
                title: String(localized: "Installer layout hidden"),
                detail: String(localized: "The background picture, volume icon and “drag here” shortcuts only lay out this disk image’s window in Finder. They’re hidden and won’t be extracted.")
            ))
        }

        if !findings.contains(where: { $0.severity == .handled || $0.severity == .caution }) {
            findings.append(CheckupFinding(
                severity: .fine,
                title: String(localized: "Names and sizes look normal"),
                detail: String(localized: "Nothing tries to leave the folder, nothing expands unusually and no names collide.")
            ))
        }
        return findings
    }

    /// A disk image's checksums, checked in the background after it opens.
    static func diskImageFinding(damaged message: String?) -> CheckupFinding {
        guard let message else {
            return CheckupFinding(severity: .fine, title: String(localized: "Disk image checks out"),
                                  detail: String(localized: "Every block matches the checksums the image was made with."))
        }
        return CheckupFinding(severity: .caution, title: String(localized: "Disk image is damaged"),
                              detail: String(localized: "Some data doesn’t match its checksum (\(message)) — download it again before installing anything from it."))
    }

    /// Finder tags, comments and other Mac details put back from AppleDouble files.
    static func findings(for restored: AppleDouble.Restored) -> [CheckupFinding] {
        guard restored.files > 0 else { return [] }
        return [CheckupFinding(
            severity: .info,
            title: String(localized: "Mac details restored"),
            detail: String(localized: "Finder tags, comments and other details packed by a Mac were put back on \(restored.files) files.")
        )]
    }

    /// What the on-disk audit had to remove during an extraction.
    static func findings(for report: ExtractReport) -> [CheckupFinding] {
        var findings: [CheckupFinding] = []
        if let first = report.removedLinks.first {
            findings.append(CheckupFinding(
                severity: .handled,
                title: String(localized: "\(report.removedLinks.count) links pointed outside the folder"),
                detail: String(localized: "“\(first.path)” → “\(first.target)” was left out so nothing outside the folder can be reached.")
            ))
        }
        if let first = report.removedItems.first {
            findings.append(CheckupFinding(
                severity: .handled,
                title: String(localized: "\(report.removedItems.count) special files left out"),
                detail: String(localized: "“\(first)” is a device file or pipe, which can’t be extracted safely.")
            ))
        }
        return findings
    }

}

nonisolated extension Archive {
    /// Maps an engine listing into the browser's model: names are shown where they will actually be
    /// written, folders are synthesized from file paths, and the listing-time Checkup runs. Names
    /// stored in an older encoding are read with `nameEncoding` (nil: whichever suits each name).
    init(listing: ArchiveListing, url: URL, name: String? = nil, nameEncoding: NameEncoding? = nil) {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let fallbackDate = values?.contentModificationDate ?? .now
        var scan = Checkup.ListingScan(archiveSize: listing.physicalSize ?? Int64(values?.fileSize ?? 0))
        var storedPaths: [String: [String]] = [:]
        var renamed: [String: String] = [:]
        var legacyNames: [Data] = []
        var files: [String: ArchiveEntry] = [:]
        var helpers: [String: ArchiveEntry] = [:]
        var explicitFolders: [String: Date] = [:]
        var appleDoublePaths = Set<String>()
        let displayName = name ?? url.lastPathComponent
        let format = ArchiveFormat(sevenZipType: listing.type, name: displayName)
        let layout = format == .dmg || format == .iso
            ? DiskImageLayout.layout(of: listing.entries.map {
                (PathContainment.containedPath(for: $0.path), $0.isFolder, $0.isSymlink, $0.linkTarget)
            })
            : DiskImageLayout.Layout()

        for item in listing.entries {
            var shown = item.path
            if let raw = item.rawPath {
                shown = NameEncoding.decode(raw, as: nameEncoding)
                if String(data: raw, encoding: .utf8) == nil, legacyNames.count < 200 { legacyNames.append(raw) }
            }
            let path = PathContainment.containedPath(for: shown)
            storedPaths[path, default: []].append(item.path)
            if item.rawPath != nil {
                let written = PathContainment.containedPath(for: item.path)
                if written != path { renamed[written] = path }
            }
            if MacHelperFiles.matches(item.path) {
                if !item.isFolder {
                    scan.helperFiles += 1
                    helpers[path] = ArchiveEntry(path: path, isFolder: false, size: item.size,
                                                 packedSize: item.packedSize ?? 0,
                                                 modified: item.modified ?? fallbackDate, isHelper: true)
                    if (item.path as NSString).lastPathComponent.hasPrefix("._") {
                        appleDoublePaths.insert(item.path)
                    }
                }
                continue
            }
            if layout.hides(path) {
                if layout.extras.contains(path) { scan.installerExtras += 1 }
                continue
            }
            if PathContainment.escapes(shown) { scan.escapingPaths.append(shown) }
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
            var parent = ArchiveEntry.parent(of: path)
            while !parent.isEmpty, ancestors.insert(parent).inserted {
                parent = ArchiveEntry.parent(of: parent)
            }
        }
        var entries = Array(files.values)
        for (path, modified) in explicitFolders where !ancestors.contains(path) && files[path] == nil {
            entries.append(ArchiveEntry(path: path, isFolder: true, size: 0, packedSize: 0, modified: modified))
        }

        scan.totalSize = files.values.reduce(0) { $0 + $1.size }
        scan.caseCollisions = Dictionary(grouping: files.keys) { $0.lowercased() }
            .values.filter { $0.count > 1 }.map { $0.sorted() }.sorted { $0[0] < $1[0] }

        self.init(name: displayName,
                  format: format,
                  isEncrypted: scan.encryptedFiles > 0,
                  files: entries,
                  helpers: Array(helpers.values),
                  checkup: Checkup.findings(for: scan))
        source = ArchiveSource(url: url, renamed: renamed, legacyNames: legacyNames,
                               nameEncoding: nameEncoding,
                               listing: listing.entries.contains { $0.rawPath != nil } ? listing : nil,
                               storedPaths: storedPaths)
        volumeRoot = layout.volumeRoot
        installerExtras = layout.extras
        self.appleDoublePaths = appleDoublePaths
        dropTargets = layout.dropTargets
    }

    /// The archive's own names for these entries; a folder stands for everything under it.
    func storedPaths(for selection: [ArchiveEntry]) -> [String] {
        guard let source else { return [] }
        var paths: [String] = []
        for entry in selection {
            paths += source.storedPaths[entry.path] ?? []
            if entry.isFolder {
                let prefix = entry.path + "/"
                for (path, stored) in source.storedPaths where path.hasPrefix(prefix) && !MacHelperFiles.matches(path) {
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
