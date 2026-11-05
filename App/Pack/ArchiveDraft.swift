import AppKit
import Observation

/// An unsaved plan of real source files. No archive is written until the shared packer succeeds.
@Observable
final class ArchiveDraft: Identifiable {
    let id = UUID()
    var name = String(localized: "Untitled Archive")
    var format = PackFormat.zip
    private(set) var files: [PackFile] = []
    var selection: Set<String> = []
    private(set) var isImporting = false
    private(set) var isSaving = false
    private(set) var isChoosingSources = false
    var quitAfterSave = false
    private var importTask: Task<[PackFile], Error>?
    var problem: String?
    var configuration: Configuration?
    var packRequest: PackRequest?
    let undoManager = UndoManager()
    private var generation = 0
    private var isClosed = false
    private var scopes: [URL] = []

    struct Configuration {
        var options: PackOptions
        var name: String
        var overrides: [String: String]
    }

    var isEdited: Bool {
        !files.isEmpty || name != String(localized: "Untitled Archive") || format != .zip
    }
    var canSave: Bool { !files.isEmpty && !isImporting && !isChoosingSources && !isSaving && !isClosed && packRequest == nil }

    init() { undoManager.groupsByEvent = false }

    func chooseSources() {
        guard !isImporting, !isChoosingSources, !isSaving, !isClosed else { return }
        isChoosingSources = true
        Task {
            let urls = await PackDestination.chooseSources()
            isChoosingSources = false
            await add(urls)
        }
    }

    func receivePromises(_ providers: [NSItemProvider]) {
        guard !isImporting, !isChoosingSources, !isSaving, !isClosed else { return }
        isChoosingSources = true
        Task {
            let urls = await OtherAppFiles.receive(providers)
            isChoosingSources = false
            await add(urls)
        }
    }

    /// Return true only when the caller may close; Save presents configuration and keeps the draft.
    func allowDiscardOrSave(quitting: Bool = false) -> Bool {
        guard !isSaving, !isChoosingSources, packRequest == nil else { return false }
        guard isEdited else { return true }
        let alert = NSAlert()
        alert.messageText = String(localized: "Save this new archive?")
        alert.informativeText = String(localized: "Your source files are unchanged. The unsaved archive draft will be discarded if you don’t save.")
        alert.addButton(withTitle: String(localized: "Save…"))
        alert.addButton(withTitle: String(localized: "Discard"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            quitAfterSave = quitting
            prepareSave()
            return false
        case .alertSecondButtonReturn: return true
        default: return false
        }
    }

    static func focused(in window: NSWindow?) -> ArchiveDraft? {
        guard let window else { return nil }
        if let draft = (window.delegate as? CreationWindowDelegate)?.draft { return draft }
        return focused(in: window.sheetParent ?? window.parent)
    }

    /// A failed or cancelled import is atomic; previous draft rows stay intact.
    func add(_ urls: [URL]) async {
        guard !isImporting, !isSaving, !isClosed else { return }
        let existing = Set(files.compactMap(\.source).map(\.standardizedFileURL))
        var seen = existing
        let urls = urls.filter { seen.insert($0.standardizedFileURL).inserted }
        guard !urls.isEmpty else { return }
        isImporting = true
        problem = nil
        let token = generation
        let acquired = urls.filter { $0.startAccessingSecurityScopedResource() }
        var kept = false
        defer {
            if !kept { acquired.forEach { $0.stopAccessingSecurityScopedResource() } }
            if token == generation { isImporting = false }
        }
        do {
            let task = Task { try await Self.scan(urls) }
            importTask = task
            let incoming = try await task.value
            try Task.checkCancellation()
            guard token == generation, !isClosed else { return }
            var taken = Set(files.compactMap { $0.path.split(separator: "/").first.map { String($0).lowercased() } })
            var mapped: [String: String] = [:]
            var additions: [PackFile] = []
            for var file in incoming {
                let components = file.path.split(separator: "/", maxSplits: 1)
                guard let first = components.first else { continue }
                let root = String(first)
                if mapped[root] == nil {
                    var candidate = root
                    var index = 1
                    while !taken.insert(candidate.lowercased()).inserted {
                        index += 1
                        candidate = Compatibility.numbered(root, index)
                    }
                    mapped[root] = candidate
                }
                file.path = mapped[root]! + (components.count == 2 ? "/" + components[1] : "")
                additions.append(file)
            }
            replaceFiles(files + additions, action: String(localized: "Add Files"))
            scopes += acquired
            kept = true
        } catch is CancellationError {
        } catch {
            guard token == generation, !isClosed else { return }
            problem = error.localizedDescription
        }
    }

    func removeSelection() {
        guard !isImporting, !isSaving else { return }
        let removed = selection
        guard !removed.isEmpty else { return }
        replaceFiles(files.filter { file in
            !removed.contains { file.path == $0 || file.path.hasPrefix($0 + "/") }
        }, action: String(localized: "Remove"))
    }

    private func replaceFiles(_ replacement: [PackFile], action: String) {
        let previous = files
        let grouping = !undoManager.isUndoing && !undoManager.isRedoing
        if grouping { undoManager.beginUndoGrouping() }
        undoManager.registerUndo(withTarget: self) { draft in
            MainActor.assumeIsolated { draft.replaceFiles(previous, action: action) }
        }
        undoManager.setActionName(action)
        if grouping { undoManager.endUndoGrouping() }
        files = replacement
        selection.formIntersection(Set(files.map(\.path)))
    }

    /// Refresh sizes and refuse missing sources before presenting options. Never silently omit them.
    func prepareSave() {
        guard canSave else { return }
        do {
            var refreshed: [PackFile] = []
            for var file in files {
                guard var url = file.source else { throw CocoaError(.fileReadNoSuchFile) }
                url.removeAllCachedResourceValues()
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
                guard file.isLink == (values.isSymbolicLink == true),
                      file.isFolder == (values.isDirectory == true && values.isSymbolicLink != true) else {
                    throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: url.path])
                }
                file.size = Int64(values.fileSize ?? 0)
                refreshed.append(file)
            }
            let roots = refreshed.filter { !$0.path.contains("/") }
            let origins = roots.compactMap(\.source)
            var request = PackRequest(files: refreshed, roots: roots.map(\.path),
                                      directory: GatherDestination.suggestion(for: origins, remembered: GatherDestination.remembered()))
            request.origins = origins
            request.suggestedNameOverride = name
            request.initialFormat = format
            packRequest = request
            problem = nil
        } catch { problem = error.localizedDescription }
    }

    func beganSaving() { isSaving = true }
    func finishedSaving(_ result: Result<[URL], Error>) {
        isSaving = false
        switch result {
        case .success:
            files = []
            selection = []
            name = String(localized: "Untitled Archive")
            format = .zip
            configuration = nil
            undoManager.removeAllActions()
        case .failure(let error):
            if EngineError(error).failure != .cancelled { problem = error.localizedDescription }
        }
    }

    func close() {
        guard !isSaving else { return }
        isClosed = true
        importTask?.cancel()
        generation += 1
        isImporting = false
        scopes.forEach { $0.stopAccessingSecurityScopedResource() }
        scopes = []
        undoManager.removeAllActions()
    }

    isolated deinit { scopes.forEach { $0.stopAccessingSecurityScopedResource() } }

    @concurrent
    private static func scan(_ urls: [URL]) async throws -> [PackFile] {
        try scanFiles(urls)
    }

    nonisolated private static func scanFiles(_ urls: [URL]) throws -> [PackFile] {
        let manager = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
        var result: [PackFile] = []
        var taken = Set<String>()
        func append(_ url: URL, path: String) throws -> Bool {
            try Task.checkCancellation()
            let value = try url.resourceValues(forKeys: keys)
            let link = value.isSymbolicLink == true
            if !link, !manager.isReadableFile(atPath: url.path) {
                throw CocoaError(.fileReadNoPermission, userInfo: [NSFilePathErrorKey: url.path])
            }
            let folder = !link && value.isDirectory == true
            result.append(PackFile(path: path, size: Int64(value.fileSize ?? 0), isFolder: folder,
                                   isLink: link, source: url))
            return folder
        }
        for url in urls {
            var name = url.lastPathComponent
            var index = 1
            while !taken.insert(name.lowercased()).inserted {
                index += 1
                name = Compatibility.numbered(url.lastPathComponent, index)
            }
            guard try append(url, path: name) else { continue }
            var failure: Error?
            guard let enumerator = manager.enumerator(at: url, includingPropertiesForKeys: Array(keys), errorHandler: { _, error in
                failure = error
                return false
            }) else { throw CocoaError(.fileReadUnknown, userInfo: [NSFilePathErrorKey: url.path]) }
            let prefix = url.standardizedFileURL.path + "/"
            for case let child as URL in enumerator {
                guard child.standardizedFileURL.path.hasPrefix(prefix) else { throw CocoaError(.fileReadCorruptFile) }
                let relative = String(child.standardizedFileURL.path.dropFirst(prefix.count))
                _ = try append(child, path: name + "/" + relative)
                if result.last?.isLink == true { enumerator.skipDescendants() }
            }
            if let failure { throw failure }
        }
        return result
    }
}
