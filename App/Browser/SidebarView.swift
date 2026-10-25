import SwiftUI

/// The optional folder list: the archive's top level, then its folders. Navigation only — the
/// archive's facts and Checkup live in Archive Info, and search sits in the toolbar, so closing this
/// column hides nothing else (#160).
struct SidebarView: View {
    @Bindable var model: BrowserModel
    /// Open folders. The way to where you are opens by itself, so the list always shows its place.
    @State private var expanded: Set<String> = []

    var body: some View {
        List(selection: folderSelection) {
            // The top level is named after the archive (the inner one, inside a nested archive).
            Label(model.archive.name, systemImage: "archivebox")
                .help(model.archive.name)
                .tag("")
            ForEach(model.archive.folderTree(includingHelpers: model.showHelperItems)) { node in
                FolderRow(node: node, expanded: $expanded)
            }
        }
        .listStyle(.sidebar)
        .onChange(of: model.archive.id) { expanded = [] }
        .onChange(of: model.folder, initial: true) { _, folder in
            var path = (folder as NSString).deletingLastPathComponent
            while !path.isEmpty {
                expanded.insert(path)
                path = (path as NSString).deletingLastPathComponent
            }
        }
    }

    private var folderSelection: Binding<String?> {
        Binding {
            model.isSearching ? nil : model.folder
        } set: { newValue in
            guard let newValue, newValue != model.folder || model.isSearching else { return }
            model.navigate(to: newValue)
        }
    }
}

/// One folder, and its folders when it's open.
private struct FolderRow: View {
    let node: FolderNode
    @Binding var expanded: Set<String>

    var body: some View {
        if let children = node.children {
            DisclosureGroup(isExpanded: Binding {
                expanded.contains(node.id)
            } set: { open in
                if open { expanded.insert(node.id) } else { expanded.remove(node.id) }
            }) {
                ForEach(children) { FolderRow(node: $0, expanded: $expanded) }
            } label: {
                Label(node.name, systemImage: "folder")
            }
            .tag(node.id)
        } else {
            Label(node.name, systemImage: "folder")
                .tag(node.id)
        }
    }
}

extension View {
    /// The folder list's column width. The extra `frame(minWidth:)` matters: SwiftUI measures a
    /// column's minimum size with a zero proposal, not the minimum declared here. Anything in the
    /// column that wraps when measured that narrow grows tall, and a minimum that tall can fight the
    /// window until AppKit throws "more Update Constraints in Window passes than there are views".
    /// The list holds single-line rows only, which keeps that measurement small.
    func sidebarColumnWidth() -> some View {
        frame(minWidth: SidebarView.minWidth)
            .navigationSplitViewColumnWidth(min: SidebarView.minWidth, ideal: 200, max: 300)
    }
}

extension SidebarView {
    static let minWidth: CGFloat = 170
}
