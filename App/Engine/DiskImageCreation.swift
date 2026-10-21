import Foundation
import Synchronization

/// Makes a DMG the way Finder's "New Image from Folder" does (issue #23), with the system's hdiutil:
///
/// 1. The items are cloned into a staging folder on the destination's volume, laid out as they'll
///    appear on the disk. With one folder chosen, its contents sit at the top, the way Finder does it.
/// 2. `hdiutil makehybrid -hfs` writes an HFS+ image of that folder without mounting anything.
///    `hdiutil create -srcfolder` mounts a scratch image, which the sandbox doesn't allow.
/// 3. `hdiutil convert` compresses it (the level picks the method), and `hdiutil verify` checks it
///    when asked.
/// 4. It moves into place with the same no-clobber rename as every archive.
enum DiskImageCreation {
    static let hdiutil = URL(filePath: "/usr/bin/hdiutil")

    /// hdiutil's image format (and options) for a compression level.
    static func imageFormat(for level: CompressionLevel) -> [String] {
        switch level {
        case .store: ["-format", "UDRO"]
        case .fastest, .fast: ["-format", "UDZO", "-imagekey", "zlib-level=1"]
        case .balanced: ["-format", "UDZO"]
        case .maximum: ["-format", "ULFO"]
        case .smallest: ["-format", "ULMO"]
        }
    }

    /// The disk's name: the archive's, without the characters HFS+ can't show (":").
    static func volumeName(for archiveName: String) -> String {
        let cleaned = archiveName.replacingOccurrences(of: ":", with: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Disk Image" : String(cleaned.prefix(200))
    }

    /// Where each item goes on the disk. With one folder chosen, its contents sit at the top;
    /// otherwise the items keep their own names.
    nonisolated static func layout(_ items: [TreeStream.Item]) -> [(item: TreeStream.Item, path: String)] {
        let roots = Set(items.map { $0.path.split(separator: "/", maxSplits: 1).first.map(String.init) ?? $0.path })
        guard roots.count == 1, let root = roots.first, items.contains(where: { $0.path.hasPrefix(root + "/") }) else {
            return items.map { ($0, $0.path) }
        }
        return items.compactMap { item in
            item.path == root ? nil : (item, String(item.path.dropFirst(root.count + 1)))
        }
    }

    static func run(_ items: [TreeStream.Item], request: CreateRequest, named name: String, in destination: URL,
                    conflict: ArchiveCreation.Conflict,
                    onProgress: @escaping @Sendable (Double) -> Void) async throws(EngineError) -> ArchiveCreation.Result {
        let staging: URL
        do {
            staging = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                  appropriateFor: destination, create: true)
        } catch {
            throw EngineError(.failed, error.localizedDescription)
        }
        defer { try? FileManager.default.removeItem(at: staging) }
        let volume = staging.appending(path: "Volume", directoryHint: .isDirectory)
        let raw = staging.appending(path: "raw.dmg")
        let image = staging.appending(path: "image.dmg")
        let volumeName = volumeName(for: request.archiveName)

        onProgress(0.02)
        try await stage(items, in: volume)
        if Task.isCancelled { throw EngineError(.cancelled) }
        onProgress(0.3)
        try await run(["makehybrid", "-quiet", "-hfs", "-hfs-volume-name", volumeName,
                       "-default-volume-name", volumeName, "-o", raw.path, volume.path])
        onProgress(0.6)
        try await run(["convert", "-quiet", raw.path] + imageFormat(for: request.level) + ["-o", image.path])
        var verified = false
        if request.verify {
            onProgress(0.85)
            try await run(["verify", "-quiet", image.path])
            verified = true
        }
        let size = (try? image.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        let placed = try ArchiveCreation.place([(image, ".dmg")], named: name, format: .dmg, in: destination,
                                               conflict: conflict)
        onProgress(1)
        return ArchiveCreation.Result(placed: placed,
                                      report: CreateReport(files: placed.map(\.lastPathComponent), size: size, verified: verified))
    }

    /// Clones (APFS) or copies each item into `folder` at its place on the disk. Links stay links,
    /// folders keep their permissions, files their attributes.
    @concurrent
    nonisolated static func stage(_ items: [TreeStream.Item], in folder: URL) async throws(EngineError) {
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            for (item, path) in layout(items) {
                if Task.isCancelled { throw EngineError(.cancelled) }
                let target = folder.appending(path: path)
                try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                let values = try item.source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if values.isSymbolicLink == true {
                    let destination = try manager.destinationOfSymbolicLink(atPath: item.source.path)
                    try manager.createSymbolicLink(atPath: target.path, withDestinationPath: destination)
                } else if values.isDirectory == true {
                    try manager.createDirectory(at: target, withIntermediateDirectories: true)
                    if let mode = try manager.attributesOfItem(atPath: item.source.path)[.posixPermissions] {
                        try manager.setAttributes([.posixPermissions: mode], ofItemAtPath: target.path)
                    }
                } else {
                    try manager.copyItem(at: item.source, to: target)
                }
            }
        } catch let error as EngineError {
            throw error
        } catch {
            throw EngineError(.failed, error.localizedDescription)
        }
    }

    /// Runs hdiutil; cancelling the task stops it.
    private static func run(_ arguments: [String]) async throws(EngineError) {
        let process = RunningTool(hdiutil, arguments)
        let status: Int32
        do {
            status = try await withTaskCancellationHandler {
                try await process.run()
            } onCancel: {
                process.terminate()
            }
        } catch {
            throw EngineError(.failed, error.localizedDescription)
        }
        if Task.isCancelled { throw EngineError(.cancelled) }
        guard status == 0 else {
            let message = process.errors.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = message.isEmpty ? "hdiutil \(arguments[0]) exited with \(status)" : "hdiutil \(arguments[0]): \(message)"
            throw EngineError(.failed, String(localized: "Couldn’t make the disk image") + " (" + detail + ")")
        }
    }
}

/// One run of a command-line tool, safe to stop from a cancellation handler.
private nonisolated final class RunningTool: @unchecked Sendable {
    private let process = Process()
    private let errorPipe = Pipe()
    private let collected = Mutex(Data())

    init(_ executable: URL, _ arguments: [String]) {
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
            } else {
                self?.collected.withLock { $0.append(chunk) }
            }
        }
    }

    func run() async throws -> Int32 {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, any Error>) in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }

    func terminate() {
        if process.isRunning { process.terminate() }
    }

    var errors: String {
        String(decoding: collected.withLock { $0 }, as: UTF8.self)
    }
}
