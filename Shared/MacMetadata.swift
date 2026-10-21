import Foundation

/// Extended attributes (Finder tags, comments, resource forks) and how they travel in a ZIP: as
/// AppleDouble `._name` files under `__MACOSX/`, the way Archive Utility and `ditto` write them.
nonisolated enum MacMetadata {
    /// Attributes the system adds on its own, or that only mean something on this Mac.
    static let ignoredAttributes: Set<String> = [
        "com.apple.provenance", "com.apple.macl", "com.apple.rootless", "com.apple.lastuseddate#PS",
    ]

    static let folderName = "__MACOSX"

    /// The attributes worth carrying, without following links.
    static func attributes(at path: String) -> [(name: String, value: [UInt8])] {
        let length = listxattr(path, nil, 0, XATTR_NOFOLLOW)
        guard length > 0 else { return [] }
        var buffer = [CChar](repeating: 0, count: length)
        guard listxattr(path, &buffer, length, XATTR_NOFOLLOW) == length else { return [] }
        let names = buffer.split(separator: 0).map { String(decoding: $0.map { UInt8(bitPattern: $0) }, as: UTF8.self) }
        return names.filter { !ignoredAttributes.contains($0) }.compactMap { name in
            let size = getxattr(path, name, nil, 0, 0, XATTR_NOFOLLOW)
            guard size >= 0 else { return nil }
            var value = [UInt8](repeating: 0, count: size)
            guard getxattr(path, name, &value, size, 0, XATTR_NOFOLLOW) == size else { return nil }
            return (name, value)
        }
    }

    /// Writes `__MACOSX/<path>/._<name>` inside `root` for every item there whose attributes are worth
    /// keeping. Links carry none.
    static func sequester(in root: URL) throws(EngineError) {
        let fileManager = FileManager.default
        guard let walker = fileManager.enumerator(atPath: root.path) else { return }
        var pending: [String] = []
        for case let path as String in walker {
            if path == folderName || path.hasPrefix(folderName + "/") {
                walker.skipDescendants()
                continue
            }
            let full = root.appending(path: path).path
            var info = stat()
            guard lstat(full, &info) == 0, info.st_mode & S_IFMT != S_IFLNK, !attributes(at: full).isEmpty else { continue }
            pending.append(path)
        }
        for path in pending {
            let parent = (path as NSString).deletingLastPathComponent
            let folder = root.appending(path: folderName).appending(path: parent, directoryHint: .isDirectory)
            let double = folder.appending(path: "._" + (path as NSString).lastPathComponent)
            do {
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            } catch {
                throw EngineError(.failed, error.localizedDescription)
            }
            guard pack(root.appending(path: path).path, into: double.path) else {
                throw EngineError(.failed, String(localized: "Couldn’t keep the Finder details of “\((path as NSString).lastPathComponent)”."))
            }
        }
    }

    /// `copyfile`'s AppleDouble packing, skipping the ignored attributes.
    private static func pack(_ source: String, into destination: String) -> Bool {
        let state = copyfile_state_alloc()
        defer { copyfile_state_free(state) }
        let callback: copyfile_callback_t = { what, stage, state, _, _, _ in
            guard what == COPYFILE_COPY_XATTR, stage == COPYFILE_START, let state else { return COPYFILE_CONTINUE }
            var name: UnsafePointer<CChar>?
            copyfile_state_get(state, UInt32(COPYFILE_STATE_XATTRNAME), &name)
            guard let name else { return COPYFILE_CONTINUE }
            return MacMetadata.ignoredAttributes.contains(String(cString: name)) ? COPYFILE_SKIP : COPYFILE_CONTINUE
        }
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CB), unsafeBitCast(callback, to: UnsafeRawPointer.self))
        return copyfile(source, destination, state, copyfile_flags_t(COPYFILE_PACK | COPYFILE_XATTR)) == 0
    }
}
