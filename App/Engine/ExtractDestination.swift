import AppKit

/// Asks where to extract. The folder people pick is the only place Stow (and its engine, via a
/// staging folder next to it) may write.
enum ExtractDestination {
    static func choose(for archive: Archive) async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Extract"
        panel.message = "Choose where to extract “\(archive.name)”."
        panel.directoryURL = archive.source?.url.deletingLastPathComponent()
        let response = if let window = NSApp.keyWindow {
            await panel.beginSheetModal(for: window)
        } else {
            panel.runModal()
        }
        return response == .OK ? panel.url : nil
    }
}
