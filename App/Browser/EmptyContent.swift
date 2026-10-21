import SwiftUI

/// Nothing to list: the archive or the folder is empty. The full window and Glance say it the same way.
struct EmptyContentView: View {
    let model: BrowserModel
    /// Offered when the whole archive is empty; nil where no Open panel can come up (Glance).
    var openAnother: (() -> Void)?

    var body: some View {
        Group {
            if model.folder.isEmpty {
                ContentUnavailableView {
                    Label("“\(model.archive.name)” is empty", systemImage: "archivebox")
                } description: {
                    Text("There’s nothing inside to extract. It may have been packed before its files were added — ask the sender for a fresh copy.")
                } actions: {
                    if let openAnother {
                        Button("Open Another Archive…", action: openAnother)
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("“\((model.folder as NSString).lastPathComponent)” is empty", systemImage: "folder")
                } description: {
                    Text("Nothing was packed inside this folder.")
                } actions: {
                    Button("Enclosing Folder") { model.goUp() }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A search that found nothing, or can't yet: the same words in the full window and Glance.
struct NoSearchResultsView: View {
    let model: BrowserModel

    var body: some View {
        Group {
            if let progress = model.indexingProgress {
                ContentUnavailableView(progress, systemImage: "magnifyingglass",
                                       description: Text("You can keep browsing while Stow finishes reading the names."))
            } else {
                ContentUnavailableView {
                    Label("No files match “\(model.query)”", systemImage: "magnifyingglass")
                } description: {
                    Text("Stow looked in every folder of this archive. Check the spelling, or search for part of a name.")
                } actions: {
                    Button("Clear Search") { model.query = "" }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
