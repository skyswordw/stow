import Foundation
import Observation

/// Files in iCloud Drive (and other cloud folders run by a File Provider) can be placeholders: the
/// name and size are on this Mac, the contents aren't. Opening one asks for the download, shows
/// it, and opens the archive once it's here. Cancel stops the waiting (the system may still
/// finish the download in the background, which costs nothing to keep).
enum CloudPlaceholder {
    enum State: Equatable { case local, placeholder }

    /// What Stow asks the system about a file. `live` in the app; tests pass their own.
    struct Probe {
        var state: @MainActor (URL) -> State
        var startDownload: @MainActor (URL) throws -> Void
        /// 0…1 when the system says how far along it is.
        var fraction: @MainActor (URL) -> Double?
        /// The system's reason when a download failed (offline, not signed in, out of space).
        var failure: @MainActor (URL) -> String?
    }

    /// `st_flags` bit macOS sets on a file whose contents live with a File Provider (SF_DATALESS).
    static let datalessFlag: UInt32 = 0x4000_0000

    static func state(of url: URL) -> State {
        let keys: Set<URLResourceKey> = [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        if let values = try? url.resourceValues(forKeys: keys), values.isUbiquitousItem == true,
           let status = values.ubiquitousItemDownloadingStatus, status == .notDownloaded {
            return .placeholder
        }
        var info = stat()
        if lstat(url.path, &info) == 0, info.st_flags & datalessFlag != 0 { return .placeholder }
        return .local
    }

    static let live = Probe(
        state: { state(of: $0) },
        startDownload: { url in
            do {
                try FileManager.default.startDownloadingUbiquitousItem(at: url)
            } catch {
                // Not an iCloud item (another File Provider): reading any byte brings the file down.
                // That read blocks until it's here, so it runs on its own thread.
                Thread.detachNewThread {
                    if let handle = try? FileHandle(forReadingFrom: url) {
                        _ = try? handle.read(upToCount: 1)
                        try? handle.close()
                    }
                }
            }
        },
        fraction: { url in DownloadPercent.shared.fraction(for: url) },
        failure: { url in
            let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingErrorKey])
            return values?.ubiquitousItemDownloadingError?.localizedDescription
        }
    )

    /// Returns at once for a file that's on this Mac. Otherwise starts the download, reports
    /// progress (nil while the system doesn't say how far along it is; the first report also
    /// means "show it"), and returns when the file is here. Throws `.cancelled` when the task
    /// is cancelled or `isCancelled` says so.
    static func waitForDownload(_ url: URL, probe: Probe = live, interval: Duration = .milliseconds(250),
                                isCancelled: () -> Bool = { false },
                                progress: (Double?) -> Void) async throws(EngineError) {
        guard probe.state(url) == .placeholder else { return }
        do {
            try probe.startDownload(url)
        } catch {
            throw EngineError(.failed, String(localized: "“\(url.lastPathComponent)” couldn’t be downloaded: \(error.localizedDescription)"))
        }
        progress(nil)
        while true {
            try? await Task.sleep(for: interval)
            if Task.isCancelled || isCancelled() { throw EngineError(.cancelled) }
            if let reason = probe.failure(url) {
                throw EngineError(.failed, String(localized: "“\(url.lastPathComponent)” couldn’t be downloaded: \(reason)"))
            }
            if probe.state(url) == .local { return }
            progress(probe.fraction(url).map { min(1, max(0, $0)) })
        }
    }
}

/// The download on screen: which file, how far, and the way to stop waiting.
@Observable
final class CloudDownload: Identifiable {
    let id = UUID()
    let name: String
    let isICloud: Bool
    var fraction: Double?
    private(set) var isCancelled = false

    init(name: String, isICloud: Bool, fraction: Double? = nil) {
        self.name = name
        self.isICloud = isICloud
        self.fraction = fraction
    }

    convenience init(url: URL) {
        self.init(name: url.lastPathComponent, isICloud: Self.isInICloudDrive(url))
    }

    /// iCloud Drive keeps its files under ~/Library/Mobile Documents.
    static func isInICloudDrive(_ url: URL) -> Bool {
        url.standardizedFileURL.path.contains("/Library/Mobile Documents/")
    }

    var title: String {
        isICloud ? String(localized: "Downloading “\(name)” from iCloud") : String(localized: "Downloading “\(name)”")
    }

    var message: String {
        String(localized: "It isn’t on this Mac yet. Stow opens it as soon as the download finishes.")
    }

    func cancel() { isCancelled = true }
}

/// How far iCloud says a download is, from Spotlight's metadata for that one file. Nil when the
/// system doesn't say (other cloud services, or no metadata yet): the bar then just moves.
final class DownloadPercent {
    static let shared = DownloadPercent()
    private var query: NSMetadataQuery?
    private var watched: URL?

    func fraction(for url: URL) -> Double? {
        if watched != url { watch(url) }
        guard let query, query.resultCount > 0,
              let item = query.result(at: 0) as? NSMetadataItem,
              let percent = item.value(forAttribute: NSMetadataUbiquitousItemPercentDownloadedKey) as? Double else {
            return nil
        }
        return percent / 100
    }

    func stop() {
        query?.stop()
        query = nil
        watched = nil
    }

    private func watch(_ url: URL) {
        query?.stop()
        let query = NSMetadataQuery()
        query.searchItems = [url]
        query.predicate = NSPredicate(value: true)
        query.start()
        self.query = query
        watched = url
    }
}
