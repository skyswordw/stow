import Foundation
import Darwin

/// Stow writes byte-split archives (`name.zip.001`, `name.7z.001`). Reassemble only
/// explicitly readable siblings; never pass a directory capability into the engine.
nonisolated enum SplitArchive {
    static func baseName(_ name: String) -> String? {
        let suffix = (name as NSString).pathExtension
        guard suffix.count >= 3, suffix.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
              Int(suffix) != nil else { return nil }
        let base = (name as NSString).deletingPathExtension
        guard ["zip", "7z"].contains((base as NSString).pathExtension.lowercased()) else { return nil }
        return base
    }

    static func parts(for first: URL) throws -> [URL] {
        guard let base = baseName(first.lastPathComponent), Int(first.pathExtension) == 1 else {
            throw EngineError(.missingVolume)
        }
        let folder = first.deletingLastPathComponent()
        let siblings = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        let parts = siblings.filter { baseName($0.lastPathComponent) == base }
            .sorted { (Int($0.pathExtension) ?? 0) < (Int($1.pathExtension) ?? 0) }
        guard !parts.isEmpty else { throw EngineError(.missingVolume) }
        for (index, part) in parts.enumerated() {
            guard Int(part.pathExtension) == index + 1,
                  part.lastPathComponent == base + "." + String(format: "%0*d", first.pathExtension.count, index + 1) else {
                throw EngineError(.missingVolume)
            }
        }
        return parts
    }

    /// Bounded-memory assembly off the main actor. Unlink immediately: cancellation, errors,
    /// connection loss and process exit cannot leave a named copy of an encrypted archive.
    @concurrent
    static func open(_ parts: [URL]) async throws(EngineError) -> FileHandle {
        let temporary = FileManager.default.temporaryDirectory.appending(path: "stow-volumes-\(UUID().uuidString)")
        let fd = Darwin.open(temporary.path, O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw EngineError(.failed, String(cString: strerror(errno))) }
        let readFD = Darwin.open(temporary.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        unlink(temporary.path)
        guard readFD >= 0 else {
            close(fd)
            throw EngineError(.failed, String(cString: strerror(errno)))
        }
        let reader = FileHandle(fileDescriptor: readFD, closeOnDealloc: true)
        let output = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        do {
            for part in parts {
                try Task.checkCancellation()
                let source = Darwin.open(part.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
                guard source >= 0 else { throw EngineError(.missingVolume) }
                let input = FileHandle(fileDescriptor: source, closeOnDealloc: true)
                defer { try? input.close() }
                var info = stat()
                guard fstat(source, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size > 0 else {
                    throw EngineError(.missingVolume)
                }
                while let bytes = try input.read(upToCount: 1024 * 1024), !bytes.isEmpty {
                    try Task.checkCancellation()
                    try output.write(contentsOf: bytes)
                }
            }
            try Task.checkCancellation()
            try output.close()
            return reader
        } catch {
            try? output.close()
            try? reader.close()
            throw error is CancellationError ? EngineError(.cancelled) : EngineError(error)
        }
    }

    static func recover(_ error: EngineError, name: String) -> EngineError {
        guard baseName(name) != nil else { return error }
        if error.failure == .notAnArchive { return EngineError(.missingVolume) }
        if error.failure == .failed {
            let text = error.message.lowercased()
            if ["unexpected end", "headers error", "data error", "crc failed", "cannot find volume", "missing volume", "7-zip couldn’t finish"].contains(where: text.contains) {
                return EngineError(.missingVolume)
            }
        }
        return error
    }
}
