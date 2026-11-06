import AppKit
import SwiftUI

/// Details beside a draft's files (#302), in the Browser's panel and words: Archive Info while
/// nothing is selected, File Info or Folder Info for one item, Selection Info for several. It tells
/// only what's known before packing — the originals' sizes, kinds, dates and places — and says the
/// archive's own size waits for Pack, so nothing here is a guess about compression or a password.
struct DraftDetails: View {
    let draft: ArchiveDraft

    var body: some View {
        let selected = draft.files.filter { draft.selection.contains($0.path) }
        let heading = Self.heading(for: selected)
        VStack(alignment: .leading, spacing: 0) {
            Label {
                Text(heading)
            } icon: {
                Image(systemName: Self.headingSymbol(for: selected))
                    .accessibilityHidden(true)
            }
            .font(.headline)
            .foregroundStyle(.secondary)
            .labelStyle(DetailsHeadingLabelStyle())
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, Space.l)
            .padding(.top, Space.l)
            .padding(.bottom, Space.m)
            ScrollView {
                Group {
                    switch selected.count {
                    case 0: DraftArchiveInfo(draft: draft)
                    case 1: DraftItemDetail(file: selected[0], draft: draft)
                    default: DraftSelectionDetail(files: selected, draft: draft)
                    }
                }
                .padding(.horizontal, Space.l)
                .padding(.bottom, Space.l)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
        }
        .frame(minWidth: 0, idealWidth: DetailsPane.idealWidth, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .detailsPanel()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(heading)
    }

    static func heading(for files: [PackFile]) -> String {
        switch files.count {
        case 0: String(localized: "Archive Info")
        case 1: files[0].isFolder ? String(localized: "Folder Info") : String(localized: "File Info")
        default: String(localized: "Selection Info")
        }
    }

    static func headingSymbol(for files: [PackFile]) -> String {
        switch files.count {
        case 0: "archivebox"
        case 1: files[0].isFolder ? "folder" : "doc"
        default: "square.on.square"
        }
    }

    /// What a planned item holds: itself, or a folder and everything inside it.
    static func contents(of file: PackFile, in files: [PackFile]) -> (items: Int, bytes: Int64) {
        guard file.isFolder else { return (1, file.size) }
        let prefix = file.path + "/"
        let inside = files.filter { $0.path.hasPrefix(prefix) }
        return (inside.count, inside.reduce(Int64(0)) { $0 + ($1.isFolder ? 0 : $1.size) })
    }

    /// Where an item will sit in the archive: "Harbor Handoff.zip › Site Photos".
    static func location(of file: PackFile, archiveName: String) -> String {
        let folders = file.path.split(separator: "/").dropLast().map(String.init)
        return ([archiveName] + folders).joined(separator: " › ")
    }
}

extension ArchiveDraft {
    /// The file the draft will become, as Pack suggests it: its name and the format's extension.
    var fileName: String {
        let name = name.trimmingCharacters(in: .whitespaces)
        return (name.isEmpty ? String(localized: "Untitled Archive") : name) + "." + format.fileExtension
    }
}

/// Nothing selected: the archive as it will be. Archive Info's three figures, in the same order,
/// with the one that needs Pack saying so.
private struct DraftArchiveInfo: View {
    let draft: ArchiveDraft

    var body: some View {
        let files = draft.files.filter { !$0.isFolder }
        let bytes = files.reduce(Int64(0)) { $0 + $1.size }
        VStack(alignment: .leading, spacing: Space.l) {
            HStack(alignment: .top, spacing: Space.m) {
                FormatBadge(format: draft.format.badgeFormat)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: draft.fileName)
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .help(draft.fileName)
                    Text("\(draft.format.displayName) archive")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: Space.s) {
                PropertyList([
                    PropertyRow(String(localized: "Files to pack"), files.count.formatted()),
                    PropertyRow(String(localized: "Total file size"), bytes.bytes,
                                detail: String(localized: "Before compression")),
                    PropertyRow(String(localized: "Archive file size"), String(localized: "Known after packing")),
                ])
                Text("Nothing is written until you pack. The files you add stay where they are.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// One item: a preview of the original, what it is, and where it comes from and goes.
private struct DraftItemDetail: View {
    let file: PackFile
    let draft: ArchiveDraft

    var body: some View {
        let facts = DraftFacts.of(file)
        let contents = DraftDetails.contents(of: file, in: draft.files)
        let name = file.path.split(separator: "/").last.map(String.init) ?? file.path
        VStack(alignment: .leading, spacing: Space.l) {
            DraftPreview(file: file)
                .frame(maxWidth: .infinity)
            ItemIdentity(name: name, kind: facts.kind.capitalizedFirst)
            PropertyList(
                (file.isFolder ? [PropertyRow(String(localized: "Items inside"), contents.items.formatted())] : [])
                + [PropertyRow(String(localized: "Size"), contents.bytes.bytes,
                               detail: String(localized: "Before compression"))]
                + (facts.modified.map { [PropertyRow(String(localized: "Modified"), $0.formatted(date: .abbreviated, time: .shortened))] } ?? [])
                + [PropertyRow(String(localized: "Location in archive"),
                               DraftDetails.location(of: file, archiveName: draft.fileName), layout: .stacked)]
                + (file.source.map { [PropertyRow(String(localized: "Original location"),
                                                  SavedItemRow<EmptyView>.displayPath($0.deletingLastPathComponent()),
                                                  layout: .stacked)] } ?? [])
            )
        }
    }
}

/// Several items: their icons fanned as the Browser fans its thumbnails, how many, and how much.
private struct DraftSelectionDetail: View {
    let files: [PackFile]
    let draft: ArchiveDraft

    var body: some View {
        // A folder and something inside it count once.
        let paths = Set(files.map(\.path))
        let outer = files.filter { file in
            !paths.contains { file.path.hasPrefix($0 + "/") }
        }
        let bytes = outer.reduce(Int64(0)) { $0 + DraftDetails.contents(of: $1, in: draft.files).bytes }
        VStack(alignment: .leading, spacing: Space.l) {
            ZStack {
                ForEach(Array(files.prefix(3).enumerated().reversed()), id: \.element.path) { index, file in
                    DraftIcon(file: file)
                        .frame(width: 72, height: 72)
                        .rotationEffect(.degrees(Double(index) * 5 - 5))
                        .offset(x: CGFloat(index) * 14 - 14)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .accessibilityHidden(true)

            Text("\(files.count) items selected")
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
                .liveNumber()

            VStack(alignment: .leading, spacing: Space.xs) {
                PropertyList([
                    PropertyRow(String(localized: "Combined file size"), bytes.bytes,
                                detail: String(localized: "Before compression")),
                ])
                if files.contains(where: \.isFolder) {
                    Text("Items inside selected folders are counted once.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// The original's Quick Look thumbnail, as tall as it is (a photo its own shape, a page its own),
/// or its Finder icon for folders and anything Quick Look can't draw.
private struct DraftPreview: View {
    let file: PackFile
    @State private var thumbnail: NSImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 200)
                    .clipShape(.rect(cornerRadius: Radius.chip))
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
            } else {
                DraftIcon(file: file)
                    .frame(width: 96, height: 96)
            }
        }
        .accessibilityHidden(true)
        .task(id: file.source) {
            thumbnail = nil
            guard let url = file.source, !file.isFolder, !file.isLink else { return }
            let result = await PreviewService.quickLookThumbnail(of: url, side: 240)
            guard !Task.isCancelled else { return }
            thumbnail = result
        }
    }
}

extension PackFormat {
    /// The parcel-label badge Archive Info draws for this format.
    var badgeFormat: ArchiveFormat {
        switch self {
        case .zip: .zip
        case .sevenZip: .sevenZip
        case .tar: .tar
        case .tarGz: .tarGz
        case .tarBz2: .bzip2
        case .tarXz: .tarXz
        case .tarZst: .tarZst
        case .dmg: .dmg
        }
    }
}
