import Foundation
import Synchronization

/// Makes a DMG the way Finder's "New Image from Folder" does (issue #23), with the system's hdiutil:
///
/// 1. The items are cloned into a staging folder on the destination's volume, laid out as they'll
///    appear on the disk. With one folder chosen, its contents sit at the top, the way Finder does it.
/// 2. Optional drag-to-install layout (#77) adds an `Applications → /Applications` symlink so Next
///    Steps can offer "drag here" installs the same way it does for developer DMGs.
/// 3. Default (no password): `hdiutil makehybrid -hfs` writes an HFS+ image without mounting,
///    then `convert` compresses by level. `create -srcfolder` mounts a scratch image, which the
///    App Sandbox doesn't allow — so unencrypted packing stays on the hybrid path.
/// 4. Optional APFS (#77): tries `hdiutil create -fs APFS -srcfolder`. When that fails (typical in
///    the App Sandbox), falls back to the HFS+ hybrid path so packing still succeeds.
/// 5. Optional AES-256 password (#77): uses `create -srcfolder -encryption AES-256 -stdinpass`
///    (password never on argv). `convert` after makehybrid does not apply encryption, so a password
///    always takes the create path; if the sandbox refuses it, packing fails with a clear message
///    instead of writing an unencrypted image.
/// 6. `hdiutil verify` checks it when asked (also via stdin when encrypted).
/// 7. It moves into place with the same no-clobber rename as every archive.
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
        let password = request.password
        let wantAPFS = request.diskImageFilesystem == .apfs

        onProgress(0.02)
        try await stage(items, in: volume, applicationsLink: request.diskImageApplicationsLink)
        if Task.isCancelled { throw EngineError(.cancelled) }
        onProgress(0.3)

        // Password-protected images need `create -srcfolder` (convert after makehybrid does not
        // apply AES). That attaches briefly, so the App Sandbox may refuse it — fail clearly
        // rather than shipping an unencrypted DMG. Unencrypted keeps the hybrid path (#23).
        let needsCreate = password != nil || wantAPFS
        var usedCreate = false
        if needsCreate {
            do {
                try await createFromFolder(volume, named: volumeName, into: image, level: request.level,
                                           filesystem: wantAPFS ? .apfs : .hfsPlus, password: password)
                usedCreate = true
            } catch let error as EngineError {
                if error.failure == .cancelled { throw error }
                try? FileManager.default.removeItem(at: image)
                if password != nil {
                    // Never fall back to an unencrypted image when the user asked for a password.
                    // Prefer hdiutil's own message when it said something useful.
                    let detail = error.message?.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let detail, !detail.isEmpty {
                        throw EngineError(.failed, detail)
                    }
                    throw EngineError(.failed, String(localized: "Couldn’t make an encrypted disk image here. Try again outside a sandboxed build, or pack without a password."))
                }
                // APFS without password: fall back to HFS+ hybrid so Pack still succeeds.
            }
        }
        if !usedCreate {
            try await run(["makehybrid", "-quiet", "-hfs", "-hfs-volume-name", volumeName,
                           "-default-volume-name", volumeName, "-o", raw.path, volume.path])
            onProgress(0.6)
            try await convert(raw, into: image, level: request.level)
        }
        onProgress(0.75)

        var verified = false
        if request.verify {
            onProgress(0.85)
            try await verify(image, password: password)
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

    /// `hdiutil create -srcfolder`. Attaches briefly; fails inside the App Sandbox.
    private static func createFromFolder(_ volume: URL, named volumeName: String, into image: URL,
                                         level: CompressionLevel, filesystem: DiskImageFilesystem,
                                         password: String?) async throws(EngineError) {
        var arguments = ["create", "-quiet", "-ov"]
        if password != nil {
            arguments += ["-encryption", "AES-256", "-stdinpass"]
        }
        let fs = filesystem == .apfs ? "APFS" : "HFS+"
        arguments += ["-volname", volumeName, "-srcfolder", volume.path, "-fs", fs]
        arguments += imageFormat(for: level)
        arguments += [image.path]
        // create -encryption prompts for the passphrase twice (confirm) even on a pipe.
        try await run(arguments, password: password, confirmPassword: password != nil)
    }

    private static func convert(_ raw: URL, into image: URL, level: CompressionLevel) async throws(EngineError) {
        var arguments = ["convert", "-quiet"]
        arguments += imageFormat(for: level)
        arguments += [raw.path, "-o", image.path]
        try await run(arguments)
    }

    private static func verify(_ image: URL, password: String?) async throws(EngineError) {
        var arguments = ["verify", "-quiet"]
        if password != nil {
            arguments += ["-stdinpass"]
        }
        arguments += [image.path]
        try await run(arguments, password: password)
    }

    /// Runs hdiutil; cancelling the task stops it. A password, when given, goes on stdin only.
    /// `confirmPassword` sends it twice — required by `hdiutil create -encryption`.
    private static func run(_ arguments: [String], password: String? = nil,
                            confirmPassword: Bool = false) async throws(EngineError) {
        let process = RunningTool(hdiutil, arguments, password: password, confirmPassword: confirmPassword)
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
    private let inputPipe: Pipe?
    private let collected = Mutex(Data())
    private let passwordData: Data?

    init(_ executable: URL, _ arguments: [String], password: String? = nil, confirmPassword: Bool = false) {
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe
        if let password {
            let pipe = Pipe()
            inputPipe = pipe
            // create -encryption reads the passphrase twice for confirmation.
            let line = password + "\n"
            passwordData = Data((confirmPassword ? line + line : line).utf8)
            process.standardInput = pipe
        } else {
            inputPipe = nil
            passwordData = nil
            process.standardInput = FileHandle.nullDevice
        }

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
                if let passwordData, let inputPipe {
                    // Write then close so hdiutil sees EOF after the password line.
                    try inputPipe.fileHandleForWriting.write(contentsOf: passwordData)
                    try inputPipe.fileHandleForWriting.close()
                }
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
