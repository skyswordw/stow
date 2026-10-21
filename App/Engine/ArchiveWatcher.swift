import Foundation

/// Watches one archive file for writes, renames and deletes from outside Stow.
/// Callbacks always land on the main actor.
@MainActor
final class ArchiveWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: Int32 = -1
    var onChange: (() -> Void)?

    func watch(_ url: URL) {
        stop()
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        descriptor = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .rename, .delete, .link, .revoke],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.onChange?() }
        }
        source.setCancelHandler {
            close(fd)
        }
        self.source = source
        source.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
        descriptor = -1
    }

    deinit {
        // Cancel releases the descriptor via setCancelHandler; do not close twice.
        source?.cancel()
    }
}
