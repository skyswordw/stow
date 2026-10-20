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
            throw EngineError(.failed, "Couldn’t start handing the files over.")
        }
        do {
            try encoder.writeDirectoryContents(archiveFrom: FilePath(folder.path), keySet: keys)
            try encoder.close()
            try bytes.close()
        } catch {
            try? encoder.close()
            try? bytes.close()
            throw EngineError(.failed, "Couldn’t hand the files over: \(error.localizedDescription)")
        }
    }

    /// Recreates what `write` sent inside `folder`, which must exist. Apple Archive refuses entries
    /// that would land outside it; `PathContainment.audit` checks the result again afterwards.
    static func read(from descriptor: Int32, into folder: URL) throws(EngineError) {
        guard let bytes = ArchiveByteStream.fileStream(fd: FileDescriptor(rawValue: descriptor), automaticClose: false),
              let decoder = ArchiveStream.decodeStream(readingFrom: bytes),
              let extractor = ArchiveStream.extractStream(extractingTo: FilePath(folder.path)) else {
            throw EngineError(.failed, "Couldn’t start receiving the files.")
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
            throw EngineError(.failed, "Couldn’t receive the files: \(error.localizedDescription)")
        }
    }
}
