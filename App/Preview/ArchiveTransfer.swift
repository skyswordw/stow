import AppKit
import UniformTypeIdentifiers

/// A process-local capability for a drag. It never accepts a source URL supplied by another app.
/// Finder still receives ordinary file promises; Stow windows resolve this token as one batch.
final class ArchiveTransfer {
    nonisolated static let typeIdentifier = "app.stow.archive-selection"
    nonisolated static let contentType = UTType(exportedAs: typeIdentifier, conformingTo: .data)
    static var pending: [String: ArchiveTransfer] = [:]
    let source: BrowserModel
    let level: BrowserModel.Level
    let archive: Archive
    let entries: [ArchiveEntry]
    let identity: FileIdentity?

    init(source: BrowserModel, entries: [ArchiveEntry]) {
        self.source = source
        level = source.level
        archive = source.archive
        self.entries = entries
        identity = source.level.edits.identity
    }

    static func register(source: BrowserModel, entries: [ArchiveEntry]) -> String {
        let token = UUID().uuidString
        pending[token] = ArchiveTransfer(source: source, entries: entries)
        return token
    }

    static func finish(_ token: String?, cancelled: Bool) {
        guard let token else { return }
        if cancelled { pending[token] = nil }
        else {
            // AppKit ends a successful drag before an item provider's asynchronous callback.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(30))
                pending[token] = nil
            }
        }
    }

    var sourceIsCurrent: Bool {
        !source.isClosed && source.level === level && level.archive.id == archive.id
            && !level.edits.isSaving && !level.edits.changedOnDisk
    }

    func copy(to target: BrowserModel, level destination: BrowserModel.Level, folder: String,
              onProgress: @escaping @Sendable (Double) -> Void) async throws {
        guard source !== target, destination.edits.requireEditable() else { throw EngineError(.cancelled) }
        let destinationID = destination.archive.id
        func check() throws {
            try Task.checkCancellation()
            guard sourceIsCurrent, !target.isClosed, target.level === destination,
                  destination.archive.id == destinationID, !destination.edits.isSaving else {
                throw EngineError(.failed, String(localized: "The archive changed during the drag. Try dragging the items again."))
            }
            if let identity, let url = archive.source?.url,
               (try? FileIdentity(of: url)) != identity { throw EngineError(.changedOnDisk) }
        }
        try check()
        let parent = FileManager.default.temporaryDirectory.appending(path: "ArchiveTransfer-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        var retained = false
        defer { if !retained { try? FileManager.default.removeItem(at: parent) } }
        let scoped = archive.source?.url.startAccessingSecurityScopedResource() ?? false
        defer { if scoped { archive.source?.url.stopAccessingSecurityScopedResource() } }
        let (staged, password) = try await source.passwords.retrying(archive.name, for: .extract,
                                                             known: level.password, vaultURL: archive.source?.url) { password in
            try check()
            var input = self.archive
            if self.level.edits.isEdited {
                // Export pending edits without changing the original, its Undo stack or its URL.
                let copy = parent.appending(path: self.archive.name)
                let listing = try await self.level.edits.copyForTransfer(to: copy, password: password)
                input = Archive(listing: listing, url: copy, name: self.archive.name)
            }
            input.source?.password = password
            try check()
            return try await Extraction.stage(input, selection: self.entries, near: parent,
                                               skipSystemFiles: Preferences.current.skipSystemFiles,
                                               onProgress: onProgress)
        }
        defer { staged.discard() }
        try check()
        if let password {
            level.password = password
            level.archive.source?.password = password
            level.savedArchive.source?.password = password
        }
        let delivered = parent.appending(path: "Delivered", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: delivered, withIntermediateDirectories: false)
        let items = staged.items(allFolder: .automatic, folderName: archive.name)
        guard !items.isEmpty else { throw EngineError(.failed, String(localized: "Nothing was extracted.")) }
        let result = try await Placement.place(items, in: delivered, resolve: Placement.keepBoth)
        if let sourceURL = archive.source?.url { Quarantine.propagate(from: sourceURL, to: result.added) }
        try check()
        let previous = destination.edits.operations
        destination.edits.add(result.placed, into: folder)
        guard destination.edits.operations != previous else { throw EngineError(.cancelled) }
        destination.edits.retainTransferDirectory(parent)
        retained = true
        target.archive.record(Checkup.findings(for: staged.report) + Checkup.findings(for: staged.restoredMetadata))
    }
}

/// Add Stow's private batch token alongside each standard file promise.
nonisolated final class ArchiveDragPromise: NSFilePromiseProvider {
    nonisolated(unsafe) var transferToken: String?

    nonisolated override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        super.writableTypes(for: pasteboard) + [NSPasteboard.PasteboardType(ArchiveTransfer.typeIdentifier)]
    }

    nonisolated override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        if type.rawValue == ArchiveTransfer.typeIdentifier { return transferToken.map { Data($0.utf8) } }
        return super.pasteboardPropertyList(forType: type)
    }
}
