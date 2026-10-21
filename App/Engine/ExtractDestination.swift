import AppKit

/// Asks where to extract. The folder people pick is the only place Stow (and its engine, via a
/// staging folder next to it) may write.
enum ExtractDestination {
    static func choose(for archive: Archive) async -> URL? {
        // Design review and verification runs pick the folder up front (`-StowExtractFolder <path>`).
        if let path = UserDefaults.standard.string(forKey: "StowExtractFolder") { return URL(filePath: path, directoryHint: .isDirectory) }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Extract")
        panel.message = String(localized: "Choose where to extract “\(archive.name)”.")
        panel.directoryURL = archive.source.flatMap { OtherAppFiles.startFolder(near: $0.url) }
        let response = if let window = NSApp.keyWindow {
            await panel.beginSheetModal(for: window)
        } else {
            panel.runModal()
        }
        return response == .OK ? panel.url : nil
    }

    /// One folder for a batch of archives.
    static func choose(count: Int, near first: URL?) async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Extract")
        panel.message = String(localized: "Choose where to extract \(count == 1 ? String(localized: "the archive") : String(localized: "\(count) archives")). Each gets its own folder.")
        panel.directoryURL = first.flatMap(OtherAppFiles.startFolder(near:))
        let response = if let window = NSApp.keyWindow {
            await panel.beginSheetModal(for: window)
        } else {
            panel.runModal()
        }
        return response == .OK ? panel.url : nil
    }
}
