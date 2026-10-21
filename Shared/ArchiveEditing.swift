import Foundation

nonisolated enum EditableFormat: String, Codable, CaseIterable, Sendable {
    case zip, sevenZip, tar

    init?(listingType: String, fileName: String) {
        let name = fileName.lowercased()
        guard !name.contains(".tar."), name.range(of: #"\.(\d{3,}|z\d+|r\d+)$|(^|\.)part\d+\.|\.(tgz|tbz2?|txz|gz|bz2|xz|lz|lzma|zst)$"#,
                         options: .regularExpression) == nil else { return nil }
        switch listingType.lowercased() {
        case "zip": self = .zip
        case "7z": self = .sevenZip
        case "tar": self = .tar
        default: return nil
        }
    }

    var fileExtension: String { self == .sevenZip ? "7z" : rawValue }
}

nonisolated enum EditOperation: Codable, Hashable, Sendable {
    case add(destinationFolder: String, items: [String])
    case replace(path: String, item: String)
    case delete(paths: [String])
    case rename(from: String, to: String)
}

nonisolated struct EditRequest: Codable, Sendable {
    var version = EngineContract.version
    var operationID: String
    var format: EditableFormat
    var operations: [EditOperation]
    var password: String?
    var encryptNewItems = true
    var verify = true
}

nonisolated struct EditReport: Codable, Sendable {
    var version = EngineContract.version
    var size: Int64
    var verified: Bool
    var listing: ArchiveListing
}

/// Pure planning. Arguments use ../work.<extension>, relative to the engine's laid-out tree.
nonisolated enum EditPlan {
    struct Source: Equatable, Sendable {
        var item: String
        var path: String
        var requiresRegularFile = false
    }

    struct Step: Equatable, Sendable {
        var arguments: [String]
        var sources: [Source] = []
    }

    private struct Node {
        var entry: ListedEntry
        var original: String?
        var item: String?
        var requiresRegularFile = false
    }

    private static func refuse(_ message: String) -> EngineError { EngineError(.failed, message) }
    private static func inside(_ path: String, _ root: String) -> Bool {
        path == root || path.hasPrefix(root + "/")
    }

    private static func validate(_ path: String) throws(EngineError) {
        // Even after --, 7-Zip interprets @name as a list file rather than a literal entry.
        guard !path.hasPrefix("@") else {
            throw refuse(String(localized: "Names beginning with @ cannot be edited safely."))
        }
        guard !path.isEmpty, !path.contains("\0"), !path.contains("\n"), !path.contains("\r"),
              !PathContainment.escapes(path), PathContainment.containedPath(for: path) == path else {
            throw refuse(String(localized: "An edit path is outside the archive or is not a clean relative path."))
        }
    }

    private static func nodes(_ ops: [EditOperation], _ listing: ArchiveListing, sources: [ListedEntry]) throws(EngineError) -> [Node] {
        var nodes = listing.entries.map { Node(entry: $0, original: $0.path) }
        var known = Set<String>()
        for node in nodes {
            try validate(node.entry.path)
            guard known.insert(node.entry.path).inserted else {
                throw refuse(String(localized: "The archive contains duplicate paths and cannot be edited safely."))
            }
        }
        func exists(_ path: String) -> Bool { nodes.contains { inside($0.entry.path, path) } }
        func parentIsSafe(_ path: String) -> Bool {
            !nodes.contains { inside(path, $0.entry.path) && path != $0.entry.path && (!$0.entry.isFolder || $0.entry.isSymlink) }
        }
        for op in ops {
            switch op {
            case let .add(folder, items):
                if !folder.isEmpty { try validate(folder) }
                for item in items {
                    try validate(item)
                    guard !item.contains("/") else { throw refuse(String(localized: "Added items must have top-level staging names.")) }
                    let path = folder.isEmpty ? item : folder + "/" + item
                    guard !exists(path), parentIsSafe(path) else {
                        throw refuse(String(localized: "An edit would overwrite an existing path or write inside a file."))
                    }
                    let tree = sources.filter { inside($0.path, item) }
                    if tree.isEmpty {
                        nodes.append(Node(entry: ListedEntry(path: path, isFolder: false, size: 0), item: item))
                    } else {
                        for source in tree {
                            var entry = source
                            entry.path = path + source.path.dropFirst(item.count)
                            try validate(entry.path)
                            nodes.append(Node(entry: entry, item: source.path))
                        }
                    }
                }
            case let .replace(path, item):
                try validate(path)
                try validate(item)
                guard let index = nodes.firstIndex(where: { $0.entry.path == path }),
                      !nodes[index].entry.isFolder, !nodes[index].entry.isSymlink else {
                    throw refuse(String(localized: "Only an existing regular file can be replaced."))
                }
                guard nodes[index].entry.rawPath == nil else {
                    throw refuse(String(localized: "This name uses an unknown text encoding, so Stow can’t rename or delete it safely."))
                }
                if let source = sources.first(where: { $0.path == item }) {
                    guard !source.isFolder, !source.isSymlink else {
                        throw refuse(String(localized: "Only an existing regular file can be replaced."))
                    }
                    var entry = source
                    entry.path = path
                    nodes[index].entry = entry
                }
                nodes[index].item = item
                nodes[index].requiresRegularFile = true
            case let .delete(paths):
                guard Set(paths).count == paths.count else { throw refuse(String(localized: "An edit contains duplicate paths.")) }
                for path in paths {
                    try validate(path)
                    guard exists(path) else { throw refuse(String(localized: "An edit refers to an entry that no longer exists.")) }
                    guard !nodes.contains(where: { inside($0.entry.path, path) && $0.entry.rawPath != nil }) else {
                        throw refuse(String(localized: "This name uses an unknown text encoding, so Stow can’t rename or delete it safely."))
                    }
                    nodes.removeAll { inside($0.entry.path, path) }
                }
            case let .rename(from, to):
                try validate(from)
                try validate(to)
                guard exists(from) else { throw refuse(String(localized: "An edit refers to an entry that no longer exists.")) }
                guard !inside(to, from), !exists(to), parentIsSafe(to) else {
                    throw refuse(String(localized: "A rename target already exists or is inside its source."))
                }
                guard !nodes.contains(where: { inside($0.entry.path, from) && $0.entry.rawPath != nil }) else {
                    throw refuse(String(localized: "This name uses an unknown text encoding, so Stow can’t rename or delete it safely."))
                }
                for index in nodes.indices where inside(nodes[index].entry.path, from) {
                    nodes[index].entry.path = to + nodes[index].entry.path.dropFirst(from.count)
                }
            }
        }
        return nodes
    }

    static func steps(for operations: [EditOperation], listing: ArchiveListing,
                      format: EditableFormat, sources: [ListedEntry] = []) throws(EngineError) -> [Step] {
        let nodes = try nodes(operations, listing, sources: sources)
        let archive = "../work." + format.fileExtension
        let common = ["-y", "-spd", "-bso0", "-bsp1", "-sccUTF-8"]
        var result: [Step] = []
        let kept = Set(nodes.filter { $0.item == nil }.compactMap(\.original))
        let deleted = listing.entries.map(\.path).filter { !kept.contains($0) }
        let roots = deleted.filter { path in !deleted.contains { $0 != path && inside(path, $0) } }.sorted()
        if !roots.isEmpty { result.append(Step(arguments: ["d"] + common + ["--", archive] + roots)) }
        var moving = nodes.filter { $0.item == nil && $0.original != nil }
        var pairs: [String] = []
        var temporaryIndex = 0
        while let candidate = moving.indices.filter({ moving[$0].original != moving[$0].entry.path })
            .min(by: { moving[$0].original!.split(separator: "/").count < moving[$1].original!.split(separator: "/").count }) {
            let pending = moving.indices.filter { moving[$0].original != moving[$0].entry.path }
                .sorted { moving[$0].original!.split(separator: "/").count < moving[$1].original!.split(separator: "/").count }
            let available = pending.first { index in
                let target = moving[index].entry.path
                let source = moving[index].original!
                let waitsForParent = pending.contains { parent in
                    parent != index && moving[parent].entry.isFolder
                        && inside(target, moving[parent].entry.path)

                }
                return !waitsForParent && !moving.contains { node in
                    let current = node.original!
                    return !inside(current, source) && (inside(current, target)
                        || (!node.entry.isFolder && inside(target, current)))
                }
            }
            let index = available ?? candidate
            let source = moving[index].original!
            let target: String
            if available != nil {
                target = moving[index].entry.path
            } else {
                // A valid sequence can swap two names through a user-chosen intermediate name.
                // Keep that sequence possible after normalization by breaking the cycle privately.
                repeat { temporaryIndex += 1 }
                while listing.entries.contains(where: { inside($0.path, ".stow-edit-\(temporaryIndex)") })
                    || nodes.contains(where: { inside($0.entry.path, ".stow-edit-\(temporaryIndex)") })
                target = ".stow-edit-\(temporaryIndex)"
            }
            pairs += [source, target]
            for child in moving.indices where inside(moving[child].original!, source) {
                moving[child].original = target + moving[child].original!.dropFirst(source.count)
            }
        }
        // Dependent moves use separate commands so each sees the preceding result;
        // a parent rename changes the child's next source.
        for offset in stride(from: 0, to: pairs.count, by: 2) {
            result.append(Step(arguments: ["rn"] + common + ["--", archive, pairs[offset], pairs[offset + 1]]))
        }
        let plannedSources = nodes.compactMap { node in node.item.map { Source(item: $0, path: node.entry.path, requiresRegularFile: node.requiresRegularFile) } }
        if !plannedSources.isEmpty {
            result.append(Step(arguments: ["a", "-t" + format.fileExtension, "-snl", "-spf2"]
                               + (format == .tar ? [] : ["-mx5"])
                               + (format == .zip ? ["-mcu=on"] : []) + common
                               + ["--", archive] + plannedSources.map(\.path).sorted(), sources: plannedSources))
        }
        result.append(Step(arguments: ["t"] + common + ["--", archive]))
        return result
    }

    static func apply(_ ops: [EditOperation], to listing: ArchiveListing, sources: [ListedEntry] = []) -> ArchiveListing {
        guard let nodes = try? nodes(ops, listing, sources: sources) else { return listing }
        var result = listing
        result.entries = nodes.map(\.entry)
        result.physicalSize = nil
        return result
    }
}
