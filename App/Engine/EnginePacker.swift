import Foundation

/// Finder's Quick Compress and the Services menu, through the same creation engine as the Pack
/// sentence: the given options (by default ZIP for Windows PCs, which opens everywhere), the
/// audience's remembered level, Windows-safe names and Mac helper files left out.
struct EnginePacker: ArchivePacking {
    func pack(_ items: [URL], options: PackOptions, to archive: URL,
              onProgress: @escaping @Sendable (Double) -> Void) async throws(EngineError) {
        let request = await PackRequest.gather(items)
        guard !request.files.isEmpty else { throw EngineError(.failed, String(localized: "There’s nothing here to compress.")) }
        var options = options
        options.level = PackPreferences.level(for: options.audience)
        let report = Compatibility.report(for: request.files, options: options, password: "")
        let name = archive.deletingPathExtension().lastPathComponent
        let keepsMetadata = options.effectiveKeepsMacMetadata
        var create = CreateRequest(operationID: UUID().uuidString, archiveName: name, format: options.format,
                                   level: options.level, password: nil, volumeSize: nil,
                                   keepsMacMetadata: keepsMetadata, verify: PackPreferences.verify,
                                   threads: options.effectiveThreads())
        create.encryptFilenames = options.format == .sevenZip && options.encryptFilenames
        _ = try await ArchiveCreation.run(report.items, totalBytes: report.totalBytes, attributes: keepsMetadata,
                                          request: create, named: name, in: archive.deletingLastPathComponent(),
                                          onProgress: onProgress)
    }
}
