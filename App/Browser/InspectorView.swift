import SwiftUI

/// The optional pane beside the files: a preview and the facts for what's selected, or Archive Info
/// when nothing is. It shows and tells; doing is the Actions bar's job, so no action buttons repeat
/// here (#160, #161).
struct InspectorView: View {
    let model: BrowserModel
    /// The header's ×, the same as the header row's Preview toggle.
    let close: () -> Void

    var body: some View {
        // Search results inside other archives count too, so the inspector matches what's highlighted.
        let selected = model.selectedEntries + model.selection.compactMap { model.nestedHits[$0]?.entry }
        VStack(spacing: 0) {
            HStack {
                Text(selected.isEmpty ? String(localized: "Archive Info") : String(localized: "Preview"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(String(localized: "Hide the preview"), systemImage: "xmark", action: close)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.accessoryBar)
                    .accessibilityLabel(String(localized: "Hide the preview"))
                    .help(String(localized: "Hide the preview"))
            }
            .padding(.leading, Space.l)
            .padding(.trailing, Space.s)
            .frame(height: BrowserHeader.height)
            details(selected)
        }
    }

    private func details(_ selected: [ArchiveEntry]) -> some View {
        ScrollView {
            Group {
                if let hit = model.selectedNestedHit {
                    NestedDetail(hit: hit)
                } else {
                    switch selected.count {
                    case 0: ArchiveInfoView(model: model)
                    case 1: EntryDetail(entry: selected[0], model: model)
                    default: MultiDetail(entries: selected, model: model)
                    }
                }
            }
            .padding(.horizontal, Space.l)
            .padding(.top, Space.xs)
            .padding(.bottom, Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A search result inside an inner archive: what it is and where. Actions has the way there.
private struct NestedDetail: View {
    let hit: NestedHit

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            EntryThumbnail(entry: hit.inner, style: .large)
                .frame(maxWidth: .infinity)
            Text(hit.inner.name)
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
                .lineLimit(3)
            MetadataGrid(rows: [
                (String(localized: "Size"), hit.inner.size.bytes),
                (String(localized: "Modified"), hit.inner.modified.formatted(date: .abbreviated, time: .shortened)),
                (String(localized: "Inside"), hit.container.path),
                (String(localized: "Where"), hit.inner.parent.isEmpty ? String(localized: "Top level") : hit.inner.parent),
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

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
                    .textSelection(.enabled)
                // One subtitle: the kind, then an edit tag the way the grid shows it ("Text · New").
                HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                    Text(kindTitle)
                        .foregroundStyle(.secondary)
                    if let state = model.editSession.state(for: entry.path) {
                        Text(verbatim: "·").foregroundStyle(.secondary).accessibilityHidden(true)
                        Text(state)
                            .foregroundStyle(state == String(localized: "New") ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    }
                }
                .accessibilityElement(children: .combine)
            }

            MetadataGrid(rows: [
                (String(localized: "Size"), entry.size.bytes),
                (String(localized: "Packed"), packedDescription),
            ] + (hasDate ? [(String(localized: "Modified"), entry.modified.formatted(date: .abbreviated, time: .shortened))] : []) + [
                (String(localized: "Where"), entry.parent.isEmpty ? String(localized: "Top level") : entry.parent),
            ])

            if entry.kind == .app, model.archive.source != nil {
                SignatureSection(entry: entry, model: model)
            }
        }
    }

    /// The list's kind with a capital first letter, as a subtitle ("text" → "Text").
    private var kindTitle: String {
        let kind = entry.kindDescription
        return kind.prefix(1).localizedUppercase + kind.dropFirst()
    }

    /// Listings without a date give the distant past; that's no date, not 1 January of year 1.
    private var hasDate: Bool { entry.modified > Date(timeIntervalSince1970: 0) }

    private var packedDescription: String {
        // Added and replaced files aren't packed until Save.
        if let state = model.editSession.state(for: entry.path),
           state == String(localized: "New") || state == String(localized: "Replaced") {
            return String(localized: "When you save")
        }
        guard let packed = entry.packedSize else { return String(localized: "Unavailable") }
        guard entry.size > 0 else { return packed.bytes }
        let saved = 1 - Double(packed) / Double(entry.size)
        return saved < 0.02 ? String(localized: "\(packed.bytes) · already compressed")
            : String(localized: "\(packed.bytes) · \(Int((saved * 100).rounded()))% smaller")
    }
}

/// Who signed an app and whether Apple notarized it — checked on request or when installing.
private struct SignatureSection: View {
    let entry: ArchiveEntry
    let model: BrowserModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionLabel(String(localized: "Signature"))
            if let verdict = model.signatures[entry.path] {
                let finding = verdict.finding
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Image(systemName: finding.severity.symbol)
                        .accessibilityHidden(true)
                        .foregroundStyle(finding.severity.color)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(finding.title).font(.callout.weight(.medium))
                        Text(finding.detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else if model.checkingSignature == entry.path {
                HStack(spacing: Space.s) {
                    ProgressView().controlSize(.small)
                    Text("Checking…").font(.callout).foregroundStyle(.secondary)
                }
            } else {
                Button("Check Signature", systemImage: "checkmark.seal") { model.checkSignature(entry) }
                Text("Also checked before installing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

            VStack(alignment: .leading, spacing: 2) {
                Text("\(entries.count) items")
                    .font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
                    .liveNumber()
                Text(entries.reduce(Int64(0)) { $0 + $1.size }.bytes)
                    .foregroundStyle(.secondary)
                    .liveNumber()
            }
        }
    }
}

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
