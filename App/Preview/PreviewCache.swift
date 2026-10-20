import AppKit
import CryptoKit

/// Files pulled out of the open archive for previews, thumbnails, Open and nested archives.
///
/// One folder per window in Stow's temporary directory. Each file is keyed by the archive's
/// identity (where it is, its size and date), the entry's path and date, so a changed archive never
/// shows a stale preview. The folder stays under `budget` (least recently used goes first; files in
/// use are pinned), is removed when the window's browser goes away or Stow quits, and anything a
/// crashed run left behind is swept on the next launch. Files are read-only: edits made in another
/// app can't silently vanish with the cache.
final class PreviewCache {
    static let budget: Int64 = 512 << 20

    let root: URL
    private struct Item {
        let url: URL
        let size: Int64
        var lastUse: Date
    }
    private var items: [String: Item] = [:]
    private var pins: [String: Int] = [:]
    private var inFlight: [String: Task<URL?, Never>] = [:]
    private var identities: [Archive.ID: String] = [:]
    private var quitObserver: (any NSObjectProtocol)?
    private let engine: ArchiveEngine

    private static let parent = FileManager.default.temporaryDirectory.appending(path: "Previews", directoryHint: .isDirectory)
    private static var swept = false

    init(engine: ArchiveEngine = .shared) {
        self.engine = engine
        if !Self.swept {
            Self.swept = true
            try? FileManager.default.removeItem(at: Self.parent)
        }
        root = Self.parent.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let root = root
        quitObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: nil
        ) { _ in
            try? FileManager.default.removeItem(at: root)
        }
    }

    isolated deinit {
        if let quitObserver { NotificationCenter.default.removeObserver(quitObserver) }
        Self.removeTree(root)
    }

    /// Deletes everything: the browser closed.
    func removeAll() {
        inFlight.values.forEach { $0.cancel() }
        inFlight = [:]
        items = [:]
        Self.removeTree(root)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    var usedBytes: Int64 { items.values.reduce(0) { $0 + $1.size } }

    // MARK: - Lookup

    /// Already extracted, without waiting.
    func cachedFile(for entry: ArchiveEntry, in archive: Archive) -> URL? {
        guard let key = key(for: entry, in: archive), var item = items[key] else { return nil }
        guard FileManager.default.fileExists(atPath: item.url.path) else {
            items[key] = nil
            return nil
        }
        item.lastUse = .now
        items[key] = item
        return item.url
    }

    /// Extracts one entry (once, however many ask at the same time).
    func file(for entry: ArchiveEntry, in archive: Archive, password: String? = nil,
              onProgress: (@Sendable (Double) -> Void)? = nil) async throws(EngineError) -> URL {
        let files = try await files(for: [entry], in: archive, password: password, onProgress: onProgress)
        guard let url = files[entry.path] else { throw EngineError(.failed, "“\(entry.name)” couldn’t be read from the archive.") }
        return url
    }

    /// Extracts several entries with one trip through the engine — solid 7z blocks are decoded once
    /// for all of them. Returns what arrived, by entry path.
    func files(for entries: [ArchiveEntry], in archive: Archive, password: String? = nil,
               onProgress: (@Sendable (Double) -> Void)? = nil) async throws(EngineError) -> [String: URL] {
        var found: [String: URL] = [:]
        var waiting: [(String, Task<URL?, Never>)] = []
        var missing: [(entry: ArchiveEntry, key: String)] = []
        for entry in entries where !entry.isNavigable {
            guard let key = key(for: entry, in: archive) else { continue }
            if let url = cachedFile(for: entry, in: archive) {
                found[entry.path] = url
            } else if let task = inFlight[key] {
                waiting.append((entry.path, task))
            } else if !missing.contains(where: { $0.key == key }) {
                missing.append((entry, key))
            }
        }

        if !missing.isEmpty {
            let batch = Task { () -> Result<[String: URL], EngineError> in
                do throws(EngineError) {
                    return .success(try await extract(missing, from: archive, password: password, onProgress: onProgress))
                } catch {
                    return .failure(error)
                }
            }
            for (entry, key) in missing {
                let task = Task { () -> URL? in
                    defer { self.inFlight[key] = nil }
                    return try? await batch.value.get()[entry.path]
                }
                inFlight[key] = task
                waiting.append((entry.path, task))
            }
            // Report the batch's own failure (a password, a damaged archive) to whoever started it.
            if case .failure(let error) = await batch.value { throw error }
        }
        for (path, task) in waiting {
            if let url = await task.value { found[path] = url }
        }
        return found
    }

    /// Keeps a file through eviction while something shows or browses it.
    func pin(_ url: URL) { pins[url.path, default: 0] += 1 }

    func unpin(_ url: URL) {
        pins[url.path, default: 0] -= 1
        if pins[url.path, default: 0] <= 0 { pins[url.path] = nil }
    }

    // MARK: - Extraction

    private func extract(_ wanted: [(entry: ArchiveEntry, key: String)], from archive: Archive, password: String?,
                         onProgress: (@Sendable (Double) -> Void)?) async throws(EngineError) -> [String: URL] {
        guard let source = archive.source else { throw EngineError(.failed, "This archive isn’t on disk.") }
        // The first stored name is enough to show a file; a package needs everything inside it.
        let paths = wanted.flatMap { item in
            item.entry.isFolder ? archive.storedPaths(for: [item.entry])
                : Array((source.storedPaths[item.entry.path] ?? []).prefix(1))
        }
        guard !paths.isEmpty else { return [:] }
        let output = try await engine.extract(source.url, paths: paths, password: password) { onProgress?($0) }
        defer { engine.discard(output) }

        let incoming = root.appending(path: ".incoming-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { Self.removeTree(incoming) }
        do {
            try FileManager.default.createDirectory(at: incoming, withIntermediateDirectories: true)
        } catch {
            throw EngineError(.failed, error.localizedDescription)
        }
        try await engine.receive(output, into: incoming)
        LegacyNames.repair(source.renamed, in: incoming)

        var placed: [String: URL] = [:]
        for (entry, key) in wanted {
            let from = incoming.appending(path: entry.path)
            let folder = root.appending(path: Self.digest(key), directoryHint: .isDirectory)
            let to = folder.appending(path: entry.name)
            Self.removeTree(folder)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: from, to: to)
            } catch {
                continue
            }
            Self.makeReadOnly(to)
            items[key] = Item(url: to, size: max(entry.size, 1), lastUse: .now)
            placed[entry.path] = to
        }
        evict(keeping: Set(wanted.map(\.key)))
        return placed
    }

    private func evict(keeping fresh: Set<String>) {
        var total = usedBytes
        guard total > Self.budget else { return }
        for (key, item) in items.sorted(by: { $0.value.lastUse < $1.value.lastUse }) {
            guard total > Self.budget else { break }
            guard !fresh.contains(key), pins[item.url.path] == nil else { continue }
            Self.removeTree(item.url.deletingLastPathComponent())
            items[key] = nil
            total -= item.size
        }
    }

    // MARK: - Keys

    func key(for entry: ArchiveEntry, in archive: Archive) -> String? {
        guard let identity = identity(of: archive) else { return nil }
        return "\(identity)\n\(entry.path)\n\(entry.modified.timeIntervalSince1970)\n\(entry.size)"
    }

    private func identity(of archive: Archive) -> String? {
        if let known = identities[archive.id] { return known }
        guard let source = archive.source else { return nil }
        let values = try? source.url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let identity = [source.url.path, "\(values?.fileSize ?? 0)",
                        "\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)",
                        source.nameEncoding?.id ?? "auto"].joined(separator: "|")
        identities[archive.id] = identity
        return identity
    }

    private static func digest(_ key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Files

    private static func makeReadOnly(_ url: URL) {
        guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey]) else { return }
        let all = [url] + walker.compactMap { $0 as? URL }
        for item in all where (try? item.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            try? FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: item.path)
        }
    }

    /// Read-only files are still removable: they live in folders Stow owns.
    private static func removeTree(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
