import AppKit

/// One bounded recovery attempt for a user-initiated open. The engine receives no new privileges.
@MainActor
final class SourceReadAccess {
    struct Denied: Error {
        let code: Int32
    }

    final class Grant {
        let url: URL
        let persistenceError: Error?
        private var stop: (() -> Void)?

        init(url: URL, persistenceError: Error?, stop: @escaping () -> Void) {
            self.url = url
            self.persistenceError = persistenceError
            self.stop = stop
        }

        func release() {
            stop?()
            stop = nil
        }
    }

    private let probe: @MainActor (URL) -> Int32?
    private let choose: @MainActor (URL) async throws -> URL?
    private let start: @MainActor (URL) -> Bool
    private let stop: @MainActor (URL) -> Void
    private let remember: @MainActor (URL) throws -> Void
    private let restore: @MainActor () -> Void

    init(probe: @escaping @MainActor (URL) -> Int32? = OtherAppFiles.readError,
         choose: @escaping @MainActor (URL) async throws -> URL? = SourceAccessPanel.choose,
         start: @escaping @MainActor (URL) -> Bool = { $0.startAccessingSecurityScopedResource() },
         stop: @escaping @MainActor (URL) -> Void = { $0.stopAccessingSecurityScopedResource() },
         remember: @escaping @MainActor (URL) throws -> Void = { try FolderAccess.shared.rememberSourceFolder($0) },
         restore: @escaping @MainActor () -> Void = { _ = FolderAccess.shared }) {
        self.probe = probe
        self.choose = choose
        self.start = start
        self.stop = stop
        self.remember = remember
        self.restore = restore
    }

    func acquire(_ file: URL) async throws -> Grant? {
        try Task.checkCancellation()
        // The store is lazy: restore its active scopes before the first source read after launch.
        restore()
        // Missing files and other I/O failures belong to the normal open error path.
        guard let code = probe(file), code == EACCES || code == EPERM else { return nil }
        guard let chosen = try await choose(file) else { throw CancellationError() }
        try Task.checkCancellation()
        guard Self.accepts(chosen, for: file) else {
            throw CocoaError(.fileReadNoPermission)
        }
        let scoped = start(chosen)
        var retained = false
        defer { if scoped && !retained { stop(chosen) } }
        // A panel result or a successful startAccessing call is not proof that open(2) succeeds.
        if let error = probe(file) {
            if error == EACCES || error == EPERM { throw Denied(code: error) }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(error),
                          userInfo: [NSFilePathErrorKey: file.path])
        }
        try Task.checkCancellation()
        var persistenceError: Error?
        if Self.sameLocation(chosen, file.deletingLastPathComponent()) {
            do { try remember(chosen) } catch { persistenceError = error }
        }
        retained = true
        return Grant(url: chosen, persistenceError: persistenceError) { [stop] in
            if scoped { stop(chosen) }
        }
    }

    /// Never turn an unreadable attachment into a request for the home folder or app container.
    static func accepts(_ selected: URL, for file: URL) -> Bool {
        selected.isFileURL && file.isFileURL &&
            (sameLocation(selected, file) || sameLocation(selected, file.deletingLastPathComponent()))
    }

    private static func sameLocation(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.path == rhs.standardizedFileURL.path
    }
}

/// Native picker, including its own validation before macOS issues a user-selection grant.
@MainActor
private final class SourceAccessPanel: NSObject, NSOpenSavePanelDelegate {
    let file: URL
    weak var panel: NSOpenPanel?
    private var fileOnly = false

    init(file: URL) { self.file = file }

    func panel(_ sender: Any, validate url: URL) throws {
        let expected = fileOnly ? file : file.deletingLastPathComponent()
        guard url.standardizedFileURL.path == expected.standardizedFileURL.path else {
            throw NSError(domain: "app.stow.source-access.selection", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: String(localized: "Select the original archive or the folder containing it.")])
        }
    }

    @objc private func changeScope(_ sender: NSButton) {
        fileOnly = sender.state == .on
        configureScope()
    }

    private func configureScope() {
        panel?.canChooseFiles = fileOnly
        panel?.canChooseDirectories = !fileOnly
        panel?.directoryURL = file.deletingLastPathComponent()
        panel?.message = fileOnly
            ? String(localized: "Allow read/write access to this archive only.\nOther files in this folder are not included.")
            : String(localized: "Allow read/write access to this folder and all its contents.\nStow will remember this folder for future opens.")
    }

    static func choose(_ file: URL) async throws -> URL? {
        try Task.checkCancellation()
        let delegate = SourceAccessPanel(file: file)
        let panel = NSOpenPanel()
        panel.delegate = delegate
        delegate.panel = panel
        delegate.configureScope()
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = file.deletingLastPathComponent()
        panel.prompt = String(localized: "Allow")
        panel.title = String(localized: "Allow Access to “\(file.lastPathComponent)”")
        panel.accessoryView = NSButton(checkboxWithTitle: String(localized: "Allow only this archive"),
                                       target: delegate, action: #selector(changeScope(_:)))
        panel.isAccessoryViewDisclosed = true
        NSApp.activate()
        return try await withTaskCancellationHandler {
            let response = await withCheckedContinuation { continuation in
                // Always use asynchronous presentation so cancellation can dismiss the picker.
                if let parent = NSApp.keyWindow, parent.attachedSheet == nil, !(parent is NSPanel) {
                    panel.beginSheetModal(for: parent) { continuation.resume(returning: $0) }
                } else {
                    panel.begin { continuation.resume(returning: $0) }
                }
            }
            withExtendedLifetime(delegate) {}
            try Task.checkCancellation()
            return response == .OK ? panel.url : nil
        } onCancel: {
            Task { @MainActor in panel.cancel(nil) }
        }
    }
}
