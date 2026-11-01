import SwiftUI

/// Details (#160): always beside the files. A preview, what the selection is and its properties,
/// or Archive Info when nothing is selected. It shows and tells; doing is Actions' job, so no
/// action buttons repeat here (#161). An inset panel, so it reads as its own surface beside the
/// files rather than a strip of the window.
struct DetailsPane: View {
    let model: BrowserModel

    var body: some View {
        // Search results inside other archives count too, so Details matches what's highlighted.
        let selected = model.selectedEntries + model.selection.compactMap { model.nestedHits[$0]?.entry }
        VStack(alignment: .leading, spacing: 0) {
            Label {
                Text(Self.heading(for: selected))
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
                    if let hit = model.selectedNestedHit {
                        NestedDetail(hit: hit, location: model.location(of: hit))
                    } else {
                        switch selected.count {
                        case 0: ArchiveInfoView(model: model)
                        case 1: EntryDetail(entry: selected[0], model: model)
                        default: MultiDetail(entries: selected, model: model)
                        }
                    }
                }
                .padding(.horizontal, Space.l)
                .padding(.bottom, Space.l)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
        }
        // Its own ideal width, so a long location or a wide picture wraps or scales inside Details
        // instead of asking the column for more room.
        .frame(minWidth: 0, idealWidth: Self.idealWidth, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .detailsPanel()
        .accessibilityLabel(Self.heading(for: selected))
    }
}

extension DetailsPane {
    static let idealWidth: CGFloat = 290

    static func heading(for entries: [ArchiveEntry]) -> String {
        switch entries.count {
        case 0: String(localized: "Archive Info")
        case 1: entries[0].kind == .folder ? String(localized: "Folder Info") : String(localized: "File Info")
        default: String(localized: "Selection Info")
        }
    }

    /// The heading's glyph names its subject as the words do: the archive, a file, a folder, or a
    /// selection of several.
    static func headingSymbol(for entries: [ArchiveEntry]) -> String {
        switch entries.count {
        case 0: "archivebox"
        case 1: entries[0].kind == .folder ? "folder" : "doc"
        default: "square.on.square"
        }
    }

    /// Recursive search may select a folder/archive and an item inside it. Count each selected
    /// outer item once, rather than adding its already-included descendants again.
    static func combinedSize(of entries: [ArchiveEntry]) -> Int64 {
        let paths = Set(entries.map(\.path))
        var seen = Set<String>()
        return entries.reduce(Int64(0)) { total, entry in
            guard seen.insert(entry.path).inserted else { return total }
            var parent = entry.parent
            while !parent.isEmpty {
                if paths.contains(parent) { return total }
                parent = ArchiveEntry.parent(of: parent)
            }
            return total + entry.size
        }
    }
}

/// The heading's glyph sits on the text's baseline at a fixed width, so the words don't shift as the
/// subject changes from archive to file to folder.
private struct DetailsHeadingLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            configuration.icon
                .imageScale(.small)
                .frame(width: 16)
            configuration.title
        }
    }
}

private extension View {
    /// Details' surface: a rounded panel inset from the window's edges, concentric with its corner.
    func detailsPanel() -> some View {
        modifier(DetailsPanelSurface())
    }
}

private struct DetailsPanelSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.panel + 4, style: .continuous)
        let dark = colorScheme == .dark
        let increased = ContrastStyle.resolve(contrast).increased
        content
            // A solid surface for reading, lifted off the window, with the light rim the floating glass
            // has: brighter along the top, as if lit from above.
            .background(dark ? AnyShapeStyle(Color.white.opacity(0.055)) : AnyShapeStyle(Color(nsColor: .controlBackgroundColor)), in: shape)
            .overlay {
                shape.strokeBorder(increased ? AnyShapeStyle(Color.primary.opacity(0.45))
                                   : AnyShapeStyle(LinearGradient(colors: [.white.opacity(dark ? 0.16 : 0.9), .primary.opacity(dark ? 0.06 : 0.08)],
                                                                  startPoint: .top, endPoint: .bottom)),
                                   lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .clipShape(shape)
            .shadow(color: .black.opacity(dark ? 0.3 : 0.07), radius: dark ? 10 : 8, y: 2)
            .padding(.horizontal, Space.s)
            .padding(.bottom, Space.s)
    }
}

/// A search result inside an inner archive: what it is and where. Actions has the way there.
private struct NestedDetail: View {
    let hit: NestedHit
    let location: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            EntryThumbnail(entry: hit.inner, style: .large)
                .frame(maxWidth: .infinity)
            ItemIdentity(name: hit.inner.name, kind: hit.inner.kindDescription.capitalizedFirst)
            PropertyList([
                PropertyRow(String(localized: "Size"), hit.inner.size.bytes),
            ] + (hit.inner.modified > Date(timeIntervalSince1970: 0) ? [
                PropertyRow(String(localized: "Modified"), hit.inner.modified.formatted(date: .abbreviated, time: .shortened)),
            ] : []) + [
                PropertyRow(String(localized: "Location in archive"), location, layout: .stacked),
            ])
        }
    }
}

private struct EntryDetail: View {
    let entry: ArchiveEntry
    let model: BrowserModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            // As tall as what it shows: a few lines of text take a few lines, a photo its own shape,
            // not a fixed poster with empty space around it.
            Group {
                if model.archive.source != nil, entry.kind.isPreviewable {
                    RichPreviewView(entry: entry, model: model, fitsContent: true)
                } else {
                    EntryThumbnail(entry: entry, style: .large)
                }
            }
            .frame(maxWidth: .infinity)

            ItemIdentity(name: entry.name, kind: entry.kindDescription.capitalizedFirst,
                         state: model.editSession.state(for: entry.path))

            let compressed = DetailsPane.compressedFigures(size: entry.size, packed: entry.packedSize,
                                                           staged: model.editSession.state(for: entry.path))
            PropertyList([
                PropertyRow(String(localized: "Size"), entry.size.bytes),
                PropertyRow(String(localized: "Packed file data"), compressed.value, detail: compressed.saved),
            ] + (hasDate ? [PropertyRow(String(localized: "Modified"), entry.modified.formatted(date: .abbreviated, time: .shortened))] : []) + [
                PropertyRow(String(localized: "Location in archive"), model.location(ofFolder: entry.parent), layout: .stacked),
            ])

            if entry.kind == .app, model.archive.source != nil || model.signatures[entry.path] != nil {
                SignatureSection(entry: entry, model: model)
            }
        }
    }

    /// Listings without a date give the distant past; that's no date, not 1 January of year 1.
    private var hasDate: Bool { entry.modified > Date(timeIntervalSince1970: 0) }
}

extension DetailsPane {
    /// The packed size, and how much it saved ("40% smaller") when that's worth saying: equal sizes
    /// don't say how the file was stored before, so Details doesn't guess. Added and replaced files
    /// aren't packed until Save.
    static func compressedFigures(size: Int64, packed: Int64?, staged: String?) -> (value: String, saved: String?) {
        if staged == String(localized: "New") || staged == String(localized: "Replaced") {
            return (String(localized: "Available after saving"), nil)
        }
        guard let packed else { return (String(localized: "Not reported by the archive"), nil) }
        guard size > 0 else { return (packed.bytes, nil) }
        let saved = 1 - Double(packed) / Double(size)
        return (packed.bytes, saved < 0.02 ? nil : String(localized: "\(Int((saved * 100).rounded()))% smaller"))
    }
}

/// The selection's name and kind, under its preview; an edit tag the way the grid shows it
/// ("Text · New").
private struct ItemIdentity: View {
    let name: String
    let kind: String
    var state: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                Text(kind)
                    .foregroundStyle(.secondary)
                if let state {
                    Text(verbatim: "·").foregroundStyle(.secondary).accessibilityHidden(true)
                    Text(state)
                        .foregroundStyle(state == String(localized: "New") ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// Who signed an app and whether Apple notarized it — checked on request or when installing.
private struct SignatureSection: View {
    let entry: ArchiveEntry
    let model: BrowserModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionLabel(String(localized: "Developer Verification"))
            if let verdict = model.signatures[entry.path] {
                // Who made it first, then what was verified about them, then the evidence.
                PropertyList([PropertyRow(String(localized: "Developer"), verdict.developerName)])
                ArchiveFindingRows(findings: [verdict.finding])
            } else if model.checkingSignature == entry.path {
                HStack(spacing: Space.s) {
                    ProgressView().controlSize(.small)
                    Text("Checking…").font(.callout).foregroundStyle(.secondary)
                }
            } else {
                Button("Verify Developer", systemImage: "checkmark.seal") { model.checkSignature(entry) }
                Text("Checks the app’s signature and Apple notarization. Also checked before installing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

}

private struct MultiDetail: View {
    let entries: [ArchiveEntry]
    let model: BrowserModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            ZStack {
                ForEach(Array(entries.prefix(3).enumerated().reversed()), id: \.element.id) { index, entry in
                    Group {
                        if model.archive.source == nil {
                            EntryThumbnail(entry: entry, style: entry.kind == .image ? .tile : .large)
                        } else {
                            LiveThumbnail(entry: entry, model: model, side: 150).padding(Space.s)
                        }
                    }
                        .frame(width: 128, height: 96)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(.rect(cornerRadius: Radius.card))
                        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                        .rotationEffect(.degrees(Double(index) * 5 - 5))
                        .offset(x: CGFloat(index) * 10 - 10)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 136)
            .accessibilityHidden(true)

            Text("\(entries.count) items selected")
                .font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
                .liveNumber()

            VStack(alignment: .leading, spacing: Space.xs) {
                PropertyList([
                    PropertyRow(String(localized: "Combined file size"), DetailsPane.combinedSize(of: entries).bytes),
                ])
                // Only worth saying when something selected can hold other items.
                if entries.contains(where: \.isNavigable) {
                    Text("Items inside selected folders or archives are counted once.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// One of Details' properties: a name, its value, and an optional quieter note under the value
/// ("40% smaller").
struct PropertyRow: Identifiable {
    enum Tone { case note, pending }
    enum Layout {
        /// Name and value on one line, the value on the trailing edge.
        case inline
        /// The name above, the value under it at full width: paths, which read from the start.
        case stacked
    }

    let label: String
    let value: String
    var detail: String?
    /// Pending notes (“Including unsaved changes”) take the accent, as staged files' tags do.
    var tone: Tone = .note
    var layout: Layout = .inline
    var id: String { label }

    init(_ label: String, _ value: String, detail: String? = nil, tone: Tone = .note, layout: Layout = .inline) {
        self.label = label
        self.value = value
        self.detail = detail
        self.tone = tone
        self.layout = layout
    }
}

/// Details' properties: the name on the leading edge, the value on the trailing edge, a hairline
/// between rows. Values wrap rather than truncate, and can be selected and copied.
struct PropertyList: View {
    let rows: [PropertyRow]
    init(_ rows: [PropertyRow]) { self.rows = rows }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider() }
                Group {
                    switch row.layout {
                    case .inline:
                        HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                            Text(row.label)
                                .foregroundStyle(.secondary)
                                .fixedSize()
                            Spacer(minLength: 0)
                            VStack(alignment: .trailing, spacing: 1) {
                                value(row, alignment: .trailing)
                                detail(row)
                            }
                        }
                    case .stacked:
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.label)
                                .foregroundStyle(.secondary)
                            value(row, alignment: .leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            detail(row)
                        }
                    }
                }
                .padding(.vertical, 7)
                .accessibilityElement(children: .combine)
            }
        }
        .font(.callout)
    }

    private func value(_ row: PropertyRow, alignment: TextAlignment) -> some View {
        Text(row.value)
            .multilineTextAlignment(alignment)
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .help(row.value)
    }

    @ViewBuilder
    private func detail(_ row: PropertyRow) -> some View {
        if let detail = row.detail {
            Text(detail)
                .font(.caption)
                .foregroundStyle(row.tone == .pending ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .monospacedDigit()
        }
    }
}

/// The column view's preview facts: names right-aligned against their values.
struct MetadataGrid: View {
    let rows: [(String, String)]

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Space.m, verticalSpacing: 6) {
            ForEach(rows, id: \.0) { row in
                GridRow {
                    Text(row.0)
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    Text(row.1)
                        .monospacedDigit()
                        .textSelection(.enabled)
                }
            }
        }
        .font(.callout)
    }
}

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .accessibilityAddTraits(.isHeader)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

extension String {
    /// The list's kind with a capital first letter, as a subtitle ("text" → "Text").
    var capitalizedFirst: String { prefix(1).localizedUppercase + dropFirst() }
}
