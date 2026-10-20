import Foundation

/// Opening a file that's still arriving gives a truncated archive and a confusing error. Browsers
/// name unfinished downloads with a suffix; anything else still growing is waited for briefly.
enum DownloadCheck {
    static let partialSuffixes = ["download", "crdownload", "part", "partial", "opdownload", "filepart"]

    static func isPartial(_ url: URL) -> Bool {
        partialSuffixes.contains(url.pathExtension.lowercased())
    }

    /// Throws for an unfinished browser download; waits (up to `limit`) while the size keeps changing.
    static func waitUntilComplete(_ url: URL, limit: Duration = .seconds(30)) async throws(EngineError) {
        if isPartial(url) {
            throw EngineError(.failed, "“\(url.lastPathComponent)” is still downloading. Open it again once the download has finished.")
        }
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        guard let modified = values?.contentModificationDate, modified.timeIntervalSinceNow > -3 else { return }
        let deadline = ContinuousClock.now + limit
        var size = url.fileSize
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(700))
            if Task.isCancelled { throw EngineError(.cancelled) }
            let now = url.fileSize
            if now == size { return }
            size = now
        }
        throw EngineError(.failed, "“\(url.lastPathComponent)” is still being written. Open it again once it’s complete.")
    }
}

/// Disk images 7-Zip can't read get a plain explanation and a way out through Finder.
enum DiskImageCheck {
    static func isDiskImage(_ url: URL) -> Bool {
        ["dmg", "iso", "sparseimage", "sparsebundle", "cdr"].contains(url.pathExtension.lowercased())
    }

    /// Encrypted UDIF images start with "encrcdsa" (v2) or end with "cdsaencr" (v1).
    static func isEncrypted(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        if (try? handle.read(upToCount: 8)) == Data("encrcdsa".utf8) { return true }
        guard let end = try? handle.seekToEnd(), end >= 8 else { return false }
        try? handle.seek(toOffset: end - 8)
        return (try? handle.read(upToCount: 8)) == Data("cdsaencr".utf8)
    }

    static func explain(_ error: EngineError, for url: URL) -> EngineError {
        guard isDiskImage(url), error.failure == .notAnArchive || error.failure == .failed else { return error }
        if isEncrypted(url) {
            return EngineError(.failed, "This disk image is encrypted. Stow can’t look inside encrypted images yet — open it in Finder to enter its password.")
        }
        return EngineError(error.failure, "Stow can’t read this disk image’s format. Finder may still be able to open it.")
    }
}
