import SwiftUI
import UniformTypeIdentifiers

/// File › Open Recent: the same list as the welcome window, with Clear Menu.
struct OpenRecentMenu: View {
    let entries: [RecentArchives.Entry]
    let open: (RecentArchives.Entry) -> Void
    let clear: () -> Void

    var body: some View {
        Menu("Open Recent") {
            ForEach(entries) { entry in
                Button { open(entry) } label: {
                    Label { Text(verbatim: Self.title(for: entry, among: entries)) } icon: { Image(nsImage: Self.icon(for: entry)) }
                }
            }
            if !entries.isEmpty { Divider() }
            Button("Clear Menu", action: clear)
                .disabled(entries.isEmpty)
        }
    }

    /// Like Finder's own Open Recent: two archives with one name say which folder each is in.
    static func title(for entry: RecentArchives.Entry, among entries: [RecentArchives.Entry]) -> String {
        let twins = entries.filter { $0.name == entry.name }.count > 1
        return twins ? "\(entry.name) — \(entry.folder.lastPathComponent)" : entry.name
    }

    /// The type's icon, so the menu needs no access to the file itself.
    private static func icon(for entry: RecentArchives.Entry) -> NSImage {
        let type = UTType(filenameExtension: entry.url.pathExtension) ?? .archive
        // A copy: the workspace hands out shared images, and resizing one would resize it everywhere.
        let image = NSWorkspace.shared.icon(for: type).copy() as? NSImage ?? NSImage()
        image.size = CGSize(width: 16, height: 16)
        return image
    }
}
