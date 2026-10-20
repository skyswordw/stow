import Foundation
import Synchronization

/// Search keys for every entry — paths folded for case, accents and width — prepared once in the
/// background so each keystroke is a plain scan. Built in chunks: search works on what's ready
/// while the rest is still indexing, and the browser stays usable throughout.
nonisolated final class SearchIndex: Sendable {
    struct Key: Sendable {
        let entry: ArchiveEntry
        let path: String
        let name: Substring
    }

    let total: Int
    private let keys = Mutex<[Key]>([])

    init(total: Int) {
        self.total = total
    }

    var indexed: Int { keys.withLock { $0.count } }
    var isComplete: Bool { indexed >= total }

    /// Folds `entries` into keys, `chunk` at a time, reporting how many are ready after each.
    @concurrent
    func build(_ entries: [ArchiveEntry], chunk: Int = 4_000, progress: @Sendable (Int) async -> Void) async {
        var start = 0
        while start < entries.count, !Task.isCancelled {
            let end = min(start + chunk, entries.count)
            let batch = entries[start..<end].map(Self.key)
            let count = keys.withLock { keys in
                keys.append(contentsOf: batch)
                return keys.count
            }
            await progress(count)
            start = end
        }
    }

    /// Matches among the keys ready so far.
    @concurrent
    func search(_ query: String, includingHelpers: Bool) async -> [ArchiveEntry] {
        let terms = Self.terms(in: query)
        guard !terms.isEmpty else { return [] }
        let keys = keys.withLock { $0 }
        var matches: [(ArchiveEntry, Bool)] = []
        for key in keys where includingHelpers || !key.entry.isHelper {
            guard terms.allSatisfy(key.path.contains) else { continue }
            matches.append((key.entry, terms.allSatisfy(key.name.contains)))
            if matches.count % 8_192 == 0, Task.isCancelled { return [] }
        }
        return Self.ranked(matches)
    }

    static func key(_ entry: ArchiveEntry) -> Key {
        let path = fold(entry.path)
        let name = path.lastIndex(of: "/").map { path[path.index(after: $0)...] } ?? path[...]
        return Key(entry: entry, path: path, name: name)
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// Space-separated terms; each must appear somewhere in the path (a term with `/` matches
    /// across folders, like "photos/2024").
    static func terms(in query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map { fold(String($0)) }
    }

    /// Entries whose name matched come first, then path-only matches; each group in path order.
    static func ranked(_ matches: [(ArchiveEntry, Bool)]) -> [ArchiveEntry] {
        let byName = matches.filter(\.1).map(\.0)
        let byPath = matches.filter { !$0.1 }.map(\.0)
        return byName.sorted { $0.path < $1.path } + byPath.sorted { $0.path < $1.path }
    }
}
