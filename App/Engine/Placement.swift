import Foundation

/// Moves finished, staged items into the destination — and decides what happens when a name is
/// already taken there. Every step is journaled; if anything fails or is stopped, everything done so
/// far is put back, including files that were replaced (they went to the Trash, not away).
enum Placement {
    enum Resolution: Sendable, Equatable { case merge, keepBoth, replace, skip }

    struct Conflict: Sendable {
        let name: String
        let existing: URL
        let incoming: URL
        /// Both are plain folders (not packages like `.app`), so they can be merged.
        let canMerge: Bool
    }

    /// Asked once per conflict; throwing (`.cancelled`) stops and undoes the whole placement.
    typealias Resolver = (Conflict) async throws(EngineError) -> Resolution

    struct Result: Sendable {
        /// Top-level items as they ended up; a merged folder is the existing one.
        var placed: [URL] = []
        /// Everything that was moved in (merged folders contribute their new children, not themselves).
        var added: [URL] = []
        var merged = 0
        var replaced = 0
        var skipped = 0
    }

    /// Stow's behaviour before there were choices: never touch what's there, number the new one.
    static let keepBoth: Resolver = { _ in .keepBoth }

    static func place(_ items: [(URL, String)], in destination: URL,
                      resolve: @escaping Resolver = keepBoth) async throws(EngineError) -> Result {
        let run = Run(resolve: resolve)
        do {
            for (item, name) in items {
                if let url = try await place(item, named: name, in: destination, run) {
                    run.result.placed.append(url)
                }
            }
        } catch {
            run.undo()
            throw error
        }
        run.result.added = run.movedIn
        return run.result
    }

    private static func place(_ item: URL, named name: String, in folder: URL, _ run: Run) async throws(EngineError) -> URL? {
        let target = folder.appending(path: name)
        if try run.move(item, to: target) { return target }

        let conflict = Conflict(name: name, existing: target, incoming: item,
                                canMerge: isPlainFolder(item) && isPlainFolder(target))
        var resolution = try await run.resolve(conflict)
        if resolution == .merge, !conflict.canMerge { resolution = .keepBoth }
        if Task.isCancelled { throw EngineError(.cancelled) }

        switch resolution {
        case .merge:
            run.result.merged += 1
            let children = (try? FileManager.default.contentsOfDirectory(
                at: item, includingPropertiesForKeys: nil, options: [])) ?? []
            for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                _ = try await place(child, named: child.lastPathComponent, in: target, run)
            }
            return target
        case .keepBoth:
            for attempt in 2...10_000 {
                let numbered = folder.appending(path: Extraction.numbered(name, attempt))
                if try run.move(item, to: numbered) { return numbered }
            }
            throw EngineError(.failed, String(localized: "Couldn’t find a free name for “\(name)”."))
        case .replace:
            try run.replace(target, with: item)
            run.result.replaced += 1
            return target
        case .skip:
            run.result.skipped += 1
            return nil
        }
    }

    /// A real folder — not a link, not a bundle that only looks like one in Finder.
    static func isPlainFolder(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey])
        return values?.isDirectory == true && values?.isSymbolicLink != true && values?.isPackage != true
    }

    private final class Run {
        enum Step {
            case moved(from: URL, to: URL)
            case trashed(original: URL, inTrash: URL)
            case swapped(URL, URL)
        }

        let resolve: Resolver
        var result = Result()
        private var steps: [Step] = []

        init(resolve: @escaping Resolver) { self.resolve = resolve }

        /// One atomic no-clobber rename. False when the name is taken.
        func move(_ item: URL, to target: URL) throws(EngineError) -> Bool {
            if renamex_np(item.path, target.path, UInt32(RENAME_EXCL)) == 0 {
                steps.append(.moved(from: item, to: target))
                return true
            }
            let code = errno
            if code == EEXIST { return false }
            throw EngineError(.failed, String(localized: "Couldn’t move “\(target.lastPathComponent)” into place: \(String(cString: strerror(code)))."))
        }

        /// The existing item goes to the Trash so a wrong choice can be undone in Finder. Volumes
        /// without a Trash swap the two atomically; the old one leaves with the staging folder.
        func replace(_ target: URL, with item: URL) throws(EngineError) {
            var trashed: NSURL?
            if (try? FileManager.default.trashItem(at: target, resultingItemURL: &trashed)) != nil, let trashed {
                steps.append(.trashed(original: target, inTrash: trashed as URL))
                guard try move(item, to: target) else {
                    throw EngineError(.failed, String(localized: "“\(target.lastPathComponent)” reappeared while it was being replaced."))
                }
                return
            }
            guard renamex_np(item.path, target.path, UInt32(RENAME_SWAP)) == 0 else {
                throw EngineError(.failed, String(localized: "Couldn’t replace “\(target.lastPathComponent)”: \(String(cString: strerror(errno)))."))
            }
            steps.append(.swapped(item, target))
        }

        var movedIn: [URL] {
            steps.compactMap { step in
                if case .moved(_, let to) = step { to } else { nil }
            }
        }

        func undo() {
            for step in steps.reversed() {
                switch step {
                case .moved(let from, let to): _ = renamex_np(to.path, from.path, UInt32(RENAME_EXCL))
                case .trashed(let original, let inTrash): _ = renamex_np(inTrash.path, original.path, UInt32(RENAME_EXCL))
                case .swapped(let a, let b): _ = renamex_np(a.path, b.path, UInt32(RENAME_SWAP))
                }
            }
            steps.removeAll()
        }
    }
}
