import AppKit

/// The Services menu (Finder › Services, or any app that hands over files). macOS gives Stow
/// access to the files on the pasteboard; writing next to them still goes through FolderAccess.
/// Declared in project.yml (NSServices); each NSMessage below is one of these selectors.
final class ServicesProvider: NSObject {
    /// Runs once the app is ready (a request can be what launched Stow).
    private let enqueue: (@escaping (AppState) -> Void) -> Void

    init(enqueue: @escaping (@escaping (AppState) -> Void) -> Void) {
        self.enqueue = enqueue
    }

    @objc func extractHere(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        run(.extractHere, pasteboard, error)
    }

    @objc func extractTo(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        run(.extractTo, pasteboard, error)
    }

    @objc func quickCompress(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        run(.quickCompress, pasteboard, error)
    }

    @objc func compress(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        run(.compress, pasteboard, error)
    }

    @objc func sendToStow(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let urls = files(on: pasteboard, error) else { return }
        enqueue { $0.system.send(urls) }
    }

    private func run(_ action: HandoffAction, _ pasteboard: NSPasteboard, _ error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let urls = files(on: pasteboard, error) else { return }
        enqueue { $0.system.perform(action, on: urls) }
    }

    private func files(on pasteboard: NSPasteboard, _ error: AutoreleasingUnsafeMutablePointer<NSString?>) -> [URL]? {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else {
            error.pointee = String(localized: "Stow didn’t receive any files.") as NSString
            return nil
        }
        return urls
    }
}
