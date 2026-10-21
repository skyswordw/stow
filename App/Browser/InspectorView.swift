import SwiftUI

struct InspectorView: View {
    let model: BrowserModel

    var body: some View {
        let selected = model.selectedEntries
        ScrollView {
            Group {
                switch selected.count {
                case 0: ArchiveSummary(archive: model.archive)
                case 1: EntryDetail(entry: selected[0], model: model)
                default: MultiDetail(entries: selected, model: model)
                }
            }
            .padding(Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct EntryDetail: View {
    let entry: ArchiveEntry
    let model: BrowserModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Group {
                if model.archive.source != nil, entry.kind.isPreviewable {
                    RichPreviewView(entry: entry, model: model)
                        .frame(height: 200)
                } else {
                    EntryThumbnail(entry: entry, style: .large)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 140)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.title3.weight(.semibold))
                    .textSelection(.enabled)
                Text(entry.kindDescription)
                    .foregroundStyle(.secondary)
            }

            MetadataGrid(rows: [
                ("Size", entry.size.bytes),
                ("Packed", packedDescription),
                ("Modified", entry.modified.formatted(date: .abbreviated, time: .shortened)),
                ("Where", entry.parent.isEmpty ? "Top level" : entry.parent),
            ])
        }
    }

    private var packedDescription: String {
        guard entry.size > 0 else { return entry.packedSize.bytes }
        let saved = 1 - Double(entry.packedSize) / Double(entry.size)
        return saved < 0.02 ? "\(entry.packedSize.bytes) · already compressed"
            : "\(entry.packedSize.bytes) · \(Int((saved * 100).rounded()))% smaller"
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
                        .frame(width: 150, height: 112)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(.rect(cornerRadius: Radius.card))
                        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                        .rotationEffect(.degrees(Double(index) * 5 - 5))
                        .offset(x: CGFloat(index) * 10 - 10)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 160)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(entries.count) items")
                    .font(.title3.weight(.semibold))
                    .liveNumber()
                Text(entries.reduce(Int64(0)) { $0 + $1.size }.bytes)
                    .foregroundStyle(.secondary)
                    .liveNumber()
            }
        }
    }
}

private struct ArchiveSummary: View {
    let archive: Archive

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            HStack(spacing: Space.m) {
                FormatBadge(format: archive.format)
                VStack(alignment: .leading, spacing: 2) {
                    Text(archive.name).font(.headline)
                    Text("\(archive.format.displayName) archive").foregroundStyle(.secondary)
                }
            }

            MetadataGrid(rows: [
                ("Files", archive.files.count.formatted()),
                ("Unpacked", archive.totalSize.bytes),
                ("Packed", archive.packedSize.bytes),
                ("Encryption", archive.isEncrypted ? "AES-256" : "None"),
            ])

            VStack(alignment: .leading, spacing: Space.m) {
                SectionLabel("Checkup")
                ForEach(archive.checkup) { finding in
                    HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                        Image(systemName: finding.severity.symbol)
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
                }
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
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}
