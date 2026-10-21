import AppleArchive
import Foundation
import System

/// Carries an extracted folder from the engine to Stow through a pipe, as an uncompressed Apple
/// Archive: types, relative paths, link targets, contents, permissions and modification dates.
/// Ownership and extended attributes are left behind on purpose.
nonisolated enum TreeStream {
    private static let fields = "TYP,PAT,LNK,DAT,MOD,MTM"

    /// Writes the contents of `folder` to `descriptor`. Doesn't close it.
    static func write(_ folder: URL, to descriptor: Int32) throws(EngineError) {
        guard let keys = ArchiveHeader.FieldKeySet(fields),
              let bytes = ArchiveByteStream.fileStream(fd: FileDescriptor(rawValue: descriptor), automaticClose: false),
              let encoder = ArchiveStream.encodeStream(writingTo: bytes) else {
            throw EngineError(.failed, String(localized: "Couldn’t start handing the files over."))
        }
        do {
            try encoder.writeDirectoryContents(archiveFrom: FilePath(folder.path), keySet: keys)
            try encoder.close()
            try bytes.close()
        } catch {
            try? encoder.close()
            try? bytes.close()
            throw EngineError(.failed, String(localized: "Couldn’t hand the files over: \(error.localizedDescription)"))
        }
    }

    /// Recreates what `write` sent inside `folder`, which must exist. Apple Archive refuses entries
    /// that would land outside it; `PathContainment.audit` checks the result again afterwards.
    static func read(from descriptor: Int32, into folder: URL, flags: ArchiveFlags = []) throws(EngineError) {
        guard let bytes = ArchiveByteStream.fileStream(fd: FileDescriptor(rawValue: descriptor), automaticClose: false),
              let decoder = ArchiveStream.decodeStream(readingFrom: bytes),
              let extractor = ArchiveStream.extractStream(extractingTo: FilePath(folder.path), flags: flags) else {
            throw EngineError(.failed, String(localized: "Couldn’t start receiving the files."))
        }
        do {
            _ = try ArchiveStream.process(readingFrom: decoder, writingTo: extractor)
            try extractor.close()
            try decoder.close()
            try bytes.close()
        } catch {
            try? extractor.close()
            try? decoder.close()
            try? bytes.close()
            throw EngineError(.failed, String(localized: "Couldn’t receive the files: \(error.localizedDescription)"))
        }
    }

    // MARK: - Files to pack

    /// One file, folder or link to pack, and the path it gets in the archive.
    struct Item: Hashable, Sendable {
        var source: URL
        var path: String
    }

    /// Writes `items` to `descriptor`, entry by entry, under their archive paths — renamed and
    /// filtered on the way, without ever opening the folders around them (the sandbox only grants the
    /// items themselves). `attributes` adds extended attributes. Reports bytes of file data written.
    /// Doesn't close the descriptor.
    static func write(_ items: [Item], to descriptor: Int32, attributes: Bool,
                      onBytes: (Int64) -> Void = { _ in }) throws(EngineError) {
        guard let bytes = ArchiveByteStream.fileStream(fd: FileDescriptor(rawValue: descriptor), automaticClose: false),
              let encoder = ArchiveStream.encodeStream(writingTo: bytes) else {
            throw EngineError(.failed, String(localized: "Couldn’t start handing the files over."))
        }
        do {
            for item in items {
                if Task.isCancelled { throw EngineError(.cancelled) }
                try write(item, to: encoder, attributes: attributes, onBytes: onBytes)
            }
            try encoder.close()
            try bytes.close()
        } catch {
            encoder.cancel()
            try? encoder.close()
            try? bytes.close()
            if let error = error as? EngineError { throw error }
            throw EngineError(.failed, String(localized: "Couldn’t hand the files over: \(error.localizedDescription)"))
        }
    }

    private static let chunkSize = 1 << 20

    private static func write(_ item: Item, to encoder: ArchiveStream, attributes: Bool,
                              onBytes: (Int64) -> Void) throws {
        let path = item.source.path
        let name = item.source.lastPathComponent
        var info = stat()
        guard lstat(path, &info) == 0 else {
            throw EngineError(.failed, String(localized: "Couldn’t read “\(name)”: \(String(cString: strerror(errno)))."))
        }
        let header = ArchiveHeader()
        let kind = info.st_mode & S_IFMT
        switch kind {
        case S_IFDIR: header.append(.uint(key: .init("TYP"), value: UInt64(UInt8(ascii: "D"))))
        case S_IFLNK: header.append(.uint(key: .init("TYP"), value: UInt64(UInt8(ascii: "L"))))
        case S_IFREG: header.append(.uint(key: .init("TYP"), value: UInt64(UInt8(ascii: "F"))))
        default: return // sockets, devices, FIFOs: nothing to pack
        }
        header.append(.string(key: .init("PAT"), value: item.path))
        if kind == S_IFLNK {
            let target = try FileManager.default.destinationOfSymbolicLink(atPath: path)
            header.append(.string(key: .init("LNK"), value: target))
        }
        header.append(.uint(key: .init("MOD"), value: UInt64(info.st_mode & 0o7777)))
        header.append(.timespec(key: .init("MTM"), value: info.st_mtimespec))

        var file: FileHandle?
        var size: Int64 = 0
        if kind == S_IFREG {
            do {
                file = try FileHandle(forReadingFrom: item.source)
            } catch {
                throw EngineError(.failed, String(localized: "Couldn’t read “\(name)”: \(error.localizedDescription)"))
            }
            var opened = stat()
            fstat(file!.fileDescriptor, &opened)
            size = Int64(opened.st_size)
            header.append(.blob(key: .init("DAT"), size: UInt64(size)))
        }
        defer { try? file?.close() }

        var extended: [UInt8]?
        if attributes, kind != S_IFLNK {
            let found = MacMetadata.attributes(at: path)
            if !found.isEmpty {
                let blob = ArchiveHeader.EntryXATBlob()
                for attribute in found { blob.append(.init(key: attribute.name, data: ContiguousArray(attribute.value))) }
                extended = blob.withAAEncodedData { Array($0) }
                header.append(.blob(key: .init("XAT"), size: UInt64(extended!.count)))
            }
        }

        try encoder.writeHeader(header)
        if let file {
            var remaining = size
            while remaining > 0 {
                if Task.isCancelled { throw EngineError(.cancelled) }
                let chunk = try file.read(upToCount: Int(min(Int64(chunkSize), remaining))) ?? Data()
                guard !chunk.isEmpty else {
                    throw EngineError(.failed, String(localized: "“\(name)” changed while it was being packed."))
                }
                try chunk.withUnsafeBytes { try encoder.writeBlob(key: .init("DAT"), from: $0) }
                remaining -= Int64(chunk.count)
                onBytes(Int64(chunk.count))
            }
        }
        if let extended {
            try extended.withUnsafeBytes { try encoder.writeBlob(key: .init("XAT"), from: $0) }
        }
    }
}
