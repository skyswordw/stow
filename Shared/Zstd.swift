import Foundation
import Synchronization
#if canImport(libzstd) && !STOW_NO_ZSTD
import libzstd
#endif

/// Writes Zstandard streams for .tar.zst. The bundled 7zz reads zstd but can't write it, so the TAR
/// that 7zz makes is compressed here with the reference library (BSD, linked into the app and the
/// engine). Reading and testing stay with 7zz.
nonisolated enum Zstd {
    /// Whether this build can write zstd (Quick Look's copy of the engine can't, and doesn't need to).
    static var isAvailable: Bool {
        #if canImport(libzstd) && !STOW_NO_ZSTD
        true
        #else
        false
        #endif
    }

    /// zstd levels for Stow's named levels. zstd has no "stored" mode; its fastest level stands in.
    /// Balanced is zstd's own default (3); Smallest stops at 19, past which memory use climbs sharply.
    static func level(for level: CompressionLevel) -> Int32 {
        switch level {
        case .store, .fastest: 1
        case .fast: 2
        case .balanced: 3
        case .maximum: 12
        case .smallest: 19
        }
    }

    /// The files a compression writes: `archive` itself, or "<archive>.001", ".002", … of at most
    /// `volumeSize` bytes each — the names 7-Zip gives volumes, so placing and opening treat them alike.
    static func volumeURL(_ archive: URL, index: Int, split: Bool) -> URL {
        split ? archive.deletingLastPathComponent()
            .appending(path: archive.lastPathComponent + "." + String(format: "%03d", index + 1)) : archive
    }

    /// Compresses `source` into `archive` (split every `volumeSize` bytes if set), with a checksum
    /// in the frame so `7zz t` can verify it. Runs off the cooperative pool; cancelling stops it
    /// between chunks and removes what it wrote.
    static func compress(_ source: URL, into archive: URL, level: Int32, volumeSize: Int64? = nil,
                         progress: @escaping @Sendable (Double) -> Void) async throws(EngineError) {
        let flag = CancelFlag()
        let outcome: Result<Void, EngineError> = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try compressNow(source, into: archive, level: level, volumeSize: volumeSize,
                                        cancelled: { flag.isSet }, progress: progress)
                        continuation.resume(returning: .success(()))
                    } catch {
                        continuation.resume(returning: .failure(EngineError(error)))
                    }
                }
            }
        } onCancel: {
            flag.set()
        }
        try outcome.get()
    }

    private nonisolated final class CancelFlag: Sendable {
        private let value = Atomic<Bool>(false)
        var isSet: Bool { value.load(ordering: .relaxed) }
        func set() { value.store(true, ordering: .relaxed) }
    }

    static func compressNow(_ source: URL, into archive: URL, level: Int32, volumeSize: Int64?,
                            cancelled: () -> Bool = { false },
                            progress: (Double) -> Void = { _ in }) throws(EngineError) {
        #if canImport(libzstd) && !STOW_NO_ZSTD
        guard let input = FileHandle(forReadingAtPath: source.path) else {
            throw EngineError(.failed, String(localized: "Couldn’t read the TAR to compress."))
        }
        defer { try? input.close() }
        let total = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        let writer = VolumeWriter(archive: archive, volumeSize: volumeSize)
        var finished = false
        defer { if !finished { writer.removeAll() } }

        guard let context = ZSTD_createCCtx() else { throw EngineError(.failed, "ZSTD_createCCtx") }
        defer { ZSTD_freeCCtx(context) }
        try check(ZSTD_CCtx_setParameter(context, ZSTD_c_compressionLevel, level))
        try check(ZSTD_CCtx_setParameter(context, ZSTD_c_checksumFlag, 1))
        if total > 0 { try check(ZSTD_CCtx_setPledgedSrcSize(context, UInt64(total))) }

        let inSize = ZSTD_CStreamInSize(), outSize = ZSTD_CStreamOutSize()
        let out = UnsafeMutableRawBufferPointer.allocate(byteCount: outSize, alignment: 1)
        defer { out.deallocate() }
        var read: Int64 = 0
        while true {
            if cancelled() { throw EngineError(.cancelled) }
            let chunk: Data
            do {
                chunk = try input.read(upToCount: inSize) ?? Data()
            } catch {
                throw EngineError(error)
            }
            let last = chunk.isEmpty
            read += Int64(chunk.count)
            // No throwing closures over the bytes: they'd rethrow as `any Error`.
            let failure: EngineError? = chunk.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> EngineError? in
                var inBuffer = ZSTD_inBuffer(src: bytes.baseAddress, size: bytes.count, pos: 0)
                while true {
                    var outView = ZSTD_outBuffer(dst: out.baseAddress, size: out.count, pos: 0)
                    let remaining = ZSTD_compressStream2(context, &outView, &inBuffer, last ? ZSTD_e_end : ZSTD_e_continue)
                    if let error = zstdError(remaining) { return error }
                    do {
                        try writer.write(UnsafeRawBufferPointer(rebasing: out[..<outView.pos]))
                    } catch {
                        return EngineError(error) // closures infer `any Error` here
                    }
                    // Mid-stream: until the chunk is consumed. At the end: until the frame is flushed.
                    if last ? remaining == 0 : inBuffer.pos == inBuffer.size { return nil }
                }
            }
            if let failure { throw failure }
            if total > 0 { progress(min(1, Double(read) / Double(total))) }
            if last { break }
        }
        try writer.close()
        finished = true
        progress(1)
        #else
        throw EngineError(.failed, String(localized: "This copy of Stow can’t create TAR.ZST archives."))
        #endif
    }

    #if canImport(libzstd) && !STOW_NO_ZSTD
    private static func check(_ result: Int) throws(EngineError) {
        if let error = zstdError(result) { throw error }
    }

    private static func zstdError(_ result: Int) -> EngineError? {
        guard ZSTD_isError(result) != 0 else { return nil }
        return EngineError(.failed, String(localized: "Couldn’t create the archive: \(String(cString: ZSTD_getErrorName(result)))"))
    }
    #endif

    /// Writes bytes to one file, or rolls over to the next volume every `volumeSize` bytes.
    private nonisolated final class VolumeWriter {
        let archive: URL
        let volumeSize: Int64?
        private var handle: FileHandle?
        private var index = -1
        private var written: Int64 = 0
        private(set) var files: [URL] = []

        init(archive: URL, volumeSize: Int64?) {
            self.archive = archive
            self.volumeSize = volumeSize.flatMap { $0 > 0 ? $0 : nil }
        }

        func write(_ bytes: UnsafeRawBufferPointer) throws(EngineError) {
            var offset = 0
            while offset < bytes.count {
                if handle == nil || (volumeSize.map { written >= $0 } ?? false) { try next() }
                let room = volumeSize.map { Int($0 - written) } ?? (bytes.count - offset)
                let count = min(room, bytes.count - offset)
                do {
                    try handle?.write(contentsOf: Data(UnsafeRawBufferPointer(rebasing: bytes[offset..<offset + count])))
                } catch {
                    throw EngineError(error)
                }
                written += Int64(count)
                offset += count
            }
        }

        private func next() throws(EngineError) {
            try? handle?.close()
            index += 1
            written = 0
            let url = Zstd.volumeURL(archive, index: index, split: volumeSize != nil)
            guard FileManager.default.createFile(atPath: url.path, contents: nil),
                  let handle = FileHandle(forWritingAtPath: url.path) else {
                throw EngineError(.failed, String(localized: "Couldn’t write “\(url.lastPathComponent)”."))
            }
            self.handle = handle
            files.append(url)
        }

        func close() throws(EngineError) {
            if handle == nil { try next() } // an empty input still makes one (empty-frame) file
            do { try handle?.close() } catch { throw EngineError(error) }
            handle = nil
        }

        func removeAll() {
            try? handle?.close()
            for file in files { try? FileManager.default.removeItem(at: file) }
        }
    }
}
