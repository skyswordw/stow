import Foundation
import Synchronization

/// Makes a DMG the way Finder's "New Image from Folder" does (issue #23 / #77), with the system's tools:
///
/// 1. The items are cloned into a staging folder on the destination's volume, laid out as they'll
///    appear on the disk. With one folder chosen, its contents sit at the top, the way Finder does it.
/// 2. Optional drag-to-install layout (#77) adds an `Applications → /Applications` symlink so Next
///    Steps can offer "drag here" installs the same way it does for developer DMGs.
/// 3. Default: `hdiutil makehybrid -hfs` writes an HFS+ image without mounting, then `convert`
///    compresses by level. `create -srcfolder` mounts a scratch image, which the App Sandbox
///    doesn't allow — so unencrypted packing stays on the hybrid path.
/// 4. Optional APFS (#77): tries `hdiutil create -fs APFS -srcfolder`. When that fails (typical in
///    the App Sandbox), falls back to the HFS+ hybrid path so packing still succeeds.
/// 5. `hdiutil verify` checks it when asked.
/// 6. It moves into place with the same no-clobber rename as every archive.
///
/// AES password packing is deferred: on macOS 27 both `hdiutil create -encryption` ("Device not
/// configured") and `diskutil image create from --encrypt` (MediaKit / EPERM) fail inside the App
/// Sandbox. Shipping a password control that always fails would be worse than leaving it off until
/// there is a sandbox-safe path.
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

    /// True when staging already has something named Applications (file, folder, or link).
    nonisolated static func applicationsNameTaken(in stagedPaths: [String]) -> Bool {
        stagedPaths.contains { ($0 as NSString).lastPathComponent == "Applications" && !$0.contains("/") }
            || stagedPaths.contains("Applications")
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
        let wantAPFS = request.diskImageFilesystem == .apfs

        onProgress(0.02)
        try await stage(items, in: volume, applicationsLink: request.diskImageApplicationsLink)
        if Task.isCancelled { throw EngineError(.cancelled) }
        onProgress(0.3)

        // APFS → hdiutil create -srcfolder, with hybrid fallback.
        // Unencrypted HFS+ stays on makehybrid (#23).
        var usedCreate = false
        if wantAPFS {
            do {
                try await createAPFS(volume, named: volumeName, into: image, level: request.level)
                usedCreate = true
            } catch let error as EngineError {
                if error.failure == .cancelled { throw error }
                try? FileManager.default.removeItem(at: image)
                // Fall back to HFS+ hybrid so Pack still succeeds.
            }
        }
        if !usedCreate {
            try await run(hdiutil, ["makehybrid", "-quiet", "-hfs", "-hfs-volume-name", volumeName,
                           "-default-volume-name", volumeName, "-o", raw.path, volume.path])
            onProgress(0.6)
            try await convert(raw, into: image, level: request.level)
        }
        onProgress(0.75)

        var verified = false
        if request.verify {
            onProgress(0.85)
            try await verify(image)
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
    /// folders keep their permissions, files their attributes. Optional Applications shortcut last.
    @concurrent
    nonisolated static func stage(_ items: [TreeStream.Item], in folder: URL,
                                  applicationsLink: Bool = false) async throws(EngineError) {
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            let placed = layout(items)
            for (item, path) in placed {
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
            if applicationsLink, !applicationsNameTaken(in: placed.map(\.path)) {
                let link = folder.appending(path: "Applications")
                try manager.createSymbolicLink(atPath: link.path, withDestinationPath: "/Applications")
            }
        } catch let error as EngineError {
            throw error
        } catch {
            throw EngineError(.failed, error.localizedDescription)
        }
    }

    /// Unencrypted APFS via `hdiutil create -srcfolder`. Attaches briefly; fails in the App Sandbox.
    private static func createAPFS(_ volume: URL, named volumeName: String, into image: URL,
                                   level: CompressionLevel) async throws(EngineError) {
        var arguments = ["create", "-quiet", "-ov", "-volname", volumeName,
                         "-srcfolder", volume.path, "-fs", "APFS"]
        arguments += imageFormat(for: level)
        arguments += [image.path]
        try await run(hdiutil, arguments)
    }

    private static func convert(_ raw: URL, into image: URL, level: CompressionLevel) async throws(EngineError) {
        var arguments = ["convert", "-quiet"]
        arguments += imageFormat(for: level)
        arguments += [raw.path, "-o", image.path]
        try await run(hdiutil, arguments)
    }

    private static func verify(_ image: URL) async throws(EngineError) {
        try await run(hdiutil, ["verify", "-quiet", image.path])
    }

    /// Runs hdiutil. Cancelling the task stops it.
    private static func run(_ executable: URL, _ arguments: [String]) async throws(EngineError) {
        let process = RunningTool(executable, arguments)
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
            let tool = executable.lastPathComponent
            let message = process.errors.trimmingCharacters(in: .whitespacesAndNewlines)
            let verb = arguments.first ?? tool
            let detail = message.isEmpty ? "\(tool) \(verb) exited with \(status)" : "\(tool) \(verb): \(message)"
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
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe
        process.standardInput = FileHandle.nullDevice
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
