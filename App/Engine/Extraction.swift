import Foundation

/// Extracts without anything half-written ever appearing where people look:
///
/// 1. The engine extracts and audits inside its own sandbox container (it can't write anywhere else).
/// 2. It streams the result into a staging folder from `.itemReplacementDirectory` on the
///    destination's volume, where Stow audits it again.
/// 3. Each finished item moves into place with one rename (`Placement`), which also settles
///    same-name conflicts.
///
/// The engine's output and the staging folder are removed on success, failure and cancel alike.
enum Extraction {
    struct Options {
        var allFolder = Preferences.ExtractAllFolder.automatic
        /// `__MACOSX`, `._*`, `.DS_Store`, `Thumbs.db`… are left out (see `MacHelperFiles`).
        var skipSystemFiles = true
        var resolve: Placement.Resolver = Placement.keepBoth

        /// From the person's settings; conflicts resolved by `resolve`.
        static func current(resolve: @escaping Placement.Resolver) -> Options {
            let values = Preferences.current
            return Options(allFolder: values.extractAllFolder, skipSystemFiles: values.skipSystemFiles, resolve: resolve)
        }
    }

    struct Result: Sendable {
        var placed: [URL]
        var report: ExtractReport
        var placement = Placement.Result()
        var restoredMetadata = AppleDouble.Restored()

        /// Checkup lines for what the audit removed and what Mac details came back.
        var findings: [CheckupFinding] {
            Checkup.findings(for: report) + Checkup.findings(for: restoredMetadata)
        }
    }

    /// `selection` nil extracts everything (see `Options.allFolder` for where it lands). Selected
    /// items land side by side.
    static func run(_ archive: Archive, selection: [ArchiveEntry]?, to destination: URL, options: Options = Options(),
                    onProgress: @escaping @Sendable (Double) -> Void) async throws(EngineError) -> Result {
        let staged = try await stage(archive, selection: selection, near: destination,
                                     skipSystemFiles: options.skipSystemFiles, onProgress: onProgress)
        defer { staged.discard() }
        let items = staged.items(allFolder: options.allFolder, folderName: folderName(for: archive))
        guard !items.isEmpty else { throw EngineError(.failed, "Nothing was extracted.") }
        let placement = try await Placement.place(items, in: destination, resolve: options.resolve)
        // Downloaded archive → downloaded contents, so Gatekeeper checks apps and scripts from it.
        if let source = archive.source?.url { Quarantine.propagate(from: source, to: placement.added) }
        return Result(placed: placement.placed, report: staged.report, placement: placement,
                      restoredMetadata: staged.restoredMetadata)
    }

    /// Extracted and audited, waiting next to `destination` (same volume) to be moved into place.
    struct Staged {
        /// The staging folder; `root` holds the archive's contents.
        let folder: URL
        let root: URL
        let selection: [ArchiveEntry]?
        let report: ExtractReport
        var restoredMetadata = AppleDouble.Restored()

        /// The selected entries as they landed, or the archive's top-level items.
        func items(allFolder: Preferences.ExtractAllFolder, folderName: String) -> [(URL, String)] {
            if let selection {
                return selection
                    .map { (root.appending(path: $0.path), $0.name) }
                    .filter { Extraction.exists($0.0) }
            }
            let top = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            guard !top.isEmpty else { return [] }
            if top.count == 1 {
                let only = top[0]
                let alreadyNamed = only.lastPathComponent == folderName && Placement.isPlainFolder(only)
                if allFolder == .automatic || alreadyNamed { return [(only, only.lastPathComponent)] }
            }
            return [(root, folderName)]
        }

        func url(for entry: ArchiveEntry) -> URL { root.appending(path: entry.path) }

        func discard() { try? FileManager.default.removeItem(at: folder) }
    }

    /// Extracts into a staging folder on `destination`'s volume and audits it there.
    static func stage(_ archive: Archive, selection: [ArchiveEntry]?, near destination: URL, skipSystemFiles: Bool = true,
                      onProgress: @escaping @Sendable (Double) -> Void) async throws(EngineError) -> Staged {
        guard let source = archive.source else { throw EngineError(.failed, "This archive isn’t on disk.") }
        let selection = selection.map(topmost)
        // A Mac's AppleDouble files come along so their details can be put back (always: they're
        // the files' own details, not clutter). The engine reads them; the files themselves can't
        // cross over, since sandboxed directory listings hide `._` names.
        let restoreMetadata = !archive.appleDoublePaths.isEmpty
        var paths = selection.map(archive.storedPaths(for:)) ?? []
        if restoreMetadata, !paths.isEmpty { paths += appleDoubles(for: paths, in: archive.appleDoublePaths) }
        let engine = ArchiveEngine.shared
        let output = try await engine.extract(
            source.url, paths: paths, excludeMacHelperFiles: skipSystemFiles, restoreMacMetadata: restoreMetadata,
            onProgress: onProgress)
        defer { engine.discard(output) }
        if Task.isCancelled { throw EngineError(.cancelled) }

        let folder = try makeStaging(for: destination)
        let root = folder.appending(path: "Contents", directoryHint: .isDirectory)
        do {
            do {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            } catch {
                throw EngineError(.failed, error.localizedDescription)
            }
            try await engine.receive(output, into: root)
            if Task.isCancelled { throw EngineError(.cancelled) }
            // Names 7-Zip decoded with the wrong code page get the names shown in the browser.
            LegacyNames.repair(source.renamed, in: root)
            // A disk image's window dressing (background art, volume icon, the Applications alias)
            // only means something in Finder's window for that image.
            for extra in archive.installerExtras {
                try? FileManager.default.removeItem(at: root.appending(path: extra))
            }
            let restored = AppleDouble.apply(output.report.macMetadata, in: root)
            var report = output.report
            report.macMetadata = [:]
            let second = try await audit(root)
            report.removedLinks += second.removedLinks.filter { !report.removedLinks.contains($0) }
            report.removedItems += second.removedItems.filter { !report.removedItems.contains($0) }
            return Staged(folder: folder, root: root, selection: selection, report: report, restoredMetadata: restored)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw EngineError(error)
        }
    }

    /// Inside the destination itself: the final move is a rename, and — because the person chose
    /// that folder — what Stow writes there isn't marked "created by a sandboxed app, may not run"
    /// (see `com.apple.security.files.user-selected.executable` in App/Stow.entitlements). Staged
    /// in Stow's container instead, extracted apps and packages would refuse to open.
    /// Falls back to the system's replacement folder on volumes where that isn't possible.
    private static func makeStaging(for destination: URL) throws(EngineError) -> URL {
        let inside = destination.appending(path: ".stow-staging-\(UUID().uuidString)", directoryHint: .isDirectory)
        if (try? FileManager.default.createDirectory(at: inside, withIntermediateDirectories: false)) != nil {
            return inside
        }
        do {
            return try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                               appropriateFor: destination, create: true)
        } catch {
            throw EngineError(.failed, error.localizedDescription)
        }
    }

    /// Stow doesn't take the engine's word for it.
    @concurrent
    private static func audit(_ root: URL) async throws(EngineError) -> PathContainment.Audit {
        do {
            return try PathContainment.audit(staging: root)
        } catch {
            throw EngineError(.failed, error.localizedDescription)
        }
    }

    /// "Report.pdf" → "Report 2.pdf"; folders and extensionless names just get the number.
    static func numbered(_ name: String, _ attempt: Int) -> String {
        guard attempt > 1 else { return name }
        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        return ext.isEmpty || stem.isEmpty ? "\(name) \(attempt)" : "\(stem) \(attempt).\(ext)"
    }

    /// "Harbor Handoff.zip" → "Harbor Handoff"; "logs.tar.gz" → "logs".
    static func folderName(for archive: Archive) -> String {
        let name = archive.name
        for suffix in [".tar.gz", ".tgz", ".tar.xz", ".txz", ".tar.bz2", ".tbz2"] where name.lowercased().hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
        }
        let stem = (name as NSString).deletingPathExtension
        return stem.isEmpty ? name : stem
    }

    /// The AppleDouble companions (`__MACOSX/dir/._name`, `dir/._name`) of the given stored paths.
    static func appleDoubles(for paths: [String], in available: Set<String>) -> [String] {
        paths.flatMap { path -> [String] in
            let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
            let name = (trimmed as NSString).lastPathComponent
            let parent = (trimmed as NSString).deletingLastPathComponent
            let inline = parent.isEmpty ? "._\(name)" : "\(parent)/._\(name)"
            return [inline, "__MACOSX/" + inline].filter(available.contains)
        }
    }

    /// Drops entries already covered by a selected folder.
    private static func topmost(_ entries: [ArchiveEntry]) -> [ArchiveEntry] {
        let folders = entries.filter(\.isFolder).map { $0.path + "/" }
        return entries.filter { entry in !folders.contains { entry.path.hasPrefix($0) } }
    }

    /// Without following links: a staged link pointing at a sibling still counts.
    static func exists(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }
}
