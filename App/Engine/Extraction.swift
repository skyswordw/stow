import Foundation

/// Extracts without anything half-written ever appearing where people look:
///
/// 1. The engine extracts and audits inside its own sandbox container (it can't write anywhere else).
/// 2. It streams the result into a staging folder from `.itemReplacementDirectory` on the
///    destination's volume, where Stow audits it again.
/// 3. Each finished item moves into place with one no-clobber rename.
///
/// The engine's output and the staging folder are removed on success, failure and cancel alike.
enum Extraction {
    struct Result: Sendable {
        var placed: [URL]
        var report: ExtractReport
    }

    /// `selection` nil extracts everything: a single top-level item lands as itself, several are
    /// wrapped in a folder named after the archive. Selected items land side by side.
    static func run(_ archive: Archive, selection: [ArchiveEntry]?, to destination: URL,
                    onProgress: @escaping @Sendable (Double) -> Void) async throws(EngineError) -> Result {
        guard let source = archive.source else { throw EngineError(.failed, "This archive isn’t on disk.") }
        let selection = selection.map(topmost)
        let engine = ArchiveEngine.shared
        let output = try await engine.extract(
            source.url, paths: selection.map(archive.storedPaths(for:)) ?? [], onProgress: onProgress)
        defer { engine.discard(output) }
        if Task.isCancelled { throw EngineError(.cancelled) }

        let staging = try makeStaging(for: destination)
        defer { try? FileManager.default.removeItem(at: staging) }
        let root = staging.appending(path: "Contents", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        } catch {
            throw EngineError(.failed, error.localizedDescription)
        }
        try await engine.receive(output, into: root)
        if Task.isCancelled { throw EngineError(.cancelled) }
        LegacyNames.repair(source.renamed, in: root)
        var report = output.report
        let second = try await audit(root)
        report.removedLinks += second.removedLinks.filter { !report.removedLinks.contains($0) }
        report.removedItems += second.removedItems.filter { !report.removedItems.contains($0) }

        let items: [(URL, String)]
        if let selection {
            items = selection
                .map { (root.appending(path: $0.path), $0.name) }
                .filter { exists($0.0) }
        } else {
            let top = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            items = top.count == 1 ? [(top[0], top[0].lastPathComponent)] : top.isEmpty ? [] : [(root, folderName(for: archive))]
        }
        guard !items.isEmpty else { throw EngineError(.failed, "Nothing was extracted.") }
        return Result(placed: try place(items, in: destination), report: report)
    }

    /// On the destination's volume, so the final move is a rename.
    private static func makeStaging(for destination: URL) throws(EngineError) -> URL {
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

    /// Moves each item into `destination` under a free name ("Photos", "Photos 2", …). Each move is
    /// a single atomic rename that never replaces anything; if one fails, earlier ones are undone.
    static func place(_ items: [(URL, String)], in destination: URL) throws(EngineError) -> [URL] {
        var placed: [(from: URL, to: URL)] = []
        for (item, name) in items {
            var attempt = 1
            while true {
                let target = destination.appending(path: numbered(name, attempt))
                if renamex_np(item.path, target.path, UInt32(RENAME_EXCL)) == 0 {
                    placed.append((item, target))
                    break
                }
                let code = errno
                if code == EEXIST, attempt < 10_000 {
                    attempt += 1
                    continue
                }
                for move in placed.reversed() {
                    _ = renamex_np(move.to.path, move.from.path, UInt32(RENAME_EXCL))
                }
                throw EngineError(.failed, "Couldn’t move “\(name)” into place: \(String(cString: strerror(code))).")
            }
        }
        return placed.map(\.to)
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

    /// Drops entries already covered by a selected folder.
    private static func topmost(_ entries: [ArchiveEntry]) -> [ArchiveEntry] {
        let folders = entries.filter(\.isFolder).map { $0.path + "/" }
        return entries.filter { entry in !folders.contains { entry.path.hasPrefix($0) } }
    }

    /// Without following links: a staged link pointing at a sibling still counts.
    private static func exists(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }
}
