import Foundation

/// Finder's Quick Compress and the Services menu, through the same creation engine as the Pack
/// sentence: the supplied defaults snapshot, recipient-specific names and helper-file policy.
struct EnginePacker: ArchivePacking {
    func pack(_ items: [URL], options: PackOptions, to archive: URL,
              onProgress: @escaping @Sendable (Double) -> Void) async throws(EngineError) {
        let request = await PackRequest.gather(items)
        guard !request.files.isEmpty else { throw EngineError(.failed, String(localized: "There’s nothing here to compress.")) }
        let report = Compatibility.report(for: request.files, options: options, password: "")
        let name = Self.archiveName(for: archive, format: options.format)
        let keepsMetadata = options.effectiveKeepsMacMetadata
        var create = CreateRequest(operationID: UUID().uuidString, archiveName: name, format: options.format,
                                   level: options.level, password: nil, volumeSize: nil,
                                   keepsMacMetadata: keepsMetadata, verify: options.verify,
                                   threads: options.effectiveThreads(global: PackPreferences.threads))
        create.encryptFilenames = options.format == .sevenZip && options.encryptFilenames
        _ = try await ArchiveCreation.run(report.items, totalBytes: report.totalBytes, attributes: keepsMetadata,
                                          request: create, named: name, in: archive.deletingLastPathComponent(),
                                          onProgress: onProgress)
    }

    /// Remove the complete format suffix, including compound extensions such as .tar.xz.
    static func archiveName(for archive: URL, format: PackFormat) -> String {
        let name = archive.lastPathComponent
        let suffix = "." + format.fileExtension
        return name.lowercased().hasSuffix(suffix) ? String(name.dropLast(suffix.count)) : name
    }
}
