import SwiftUI

struct InspectorView: View {
    let model: BrowserModel

    var body: some View {
        let selected = model.selectedEntries
        ScrollView {
            Group {
                if let hit = model.selectedNestedHit {
                    NestedDetail(hit: hit, model: model)
                } else {
                switch selected.count {
                case 0: ArchiveSummary(archive: model.archive)
                case 1: EntryDetail(entry: selected[0], model: model)
                default: MultiDetail(entries: selected, model: model)
                }
                }
            }
            .padding(Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A search result inside an inner archive: what and where, and the way there.
private struct NestedDetail: View {
    let hit: NestedHit
    let model: BrowserModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            EntryThumbnail(entry: hit.inner, style: .large)
                .frame(maxWidth: .infinity, minHeight: 120)
            Text(hit.inner.name)
                .font(.title3.weight(.semibold))
                .lineLimit(3)
            MetadataGrid(rows: [
                (String(localized: "Size"), hit.inner.size.bytes),
                (String(localized: "Modified"), hit.inner.modified.formatted(date: .abbreviated, time: .shortened)),
                (String(localized: "Inside"), hit.container.path),
                (String(localized: "Where"), hit.inner.parent.isEmpty ? String(localized: "Top level") : hit.inner.parent),
            ])
            Button(String(localized: "Show in “\(hit.container.name)”"), systemImage: "arrow.down.right.and.arrow.up.left") {
                model.showNested(hit)
            }
            .controlSize(.large)
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
                    .font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
                    .textSelection(.enabled)
                if let state = model.editSession.state(for: entry.path) { Text(state).font(.caption).foregroundStyle(.secondary) }
                Text(entry.kindDescription)
                    .foregroundStyle(.secondary)
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

            let steps = NextStep.suggestions(for: [entry], dropTargets: model.archive.dropTargets).dropLast()
            if !steps.isEmpty, model.activity == nil {
                HStack(spacing: Space.s) {
                    ForEach(Array(steps)) { step in
                        Button(step.title, systemImage: step.symbol) { model.run(step, on: [entry]) }
                    }
                }
                .controlSize(.large)
            }
        }
    }

    /// Listings without a date give the distant past; that's no date, not 1 January of year 1.
    private var hasDate: Bool { entry.modified > Date(timeIntervalSince1970: 0) }

    private var packedDescription: String {
        // Added and replaced files aren't packed until Save.
        if let state = model.editSession.state(for: entry.path),
           state == String(localized: "New") || state == String(localized: "Replaced") {
            return String(localized: "When you save")
        }
        guard entry.size > 0 else { return entry.packedSize.bytes }
        let saved = 1 - Double(entry.packedSize) / Double(entry.size)
        return saved < 0.02 ? String(localized: "\(entry.packedSize.bytes) · already compressed")
            : String(localized: "\(entry.packedSize.bytes) · \(Int((saved * 100).rounded()))% smaller")
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
                    .font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
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
                    Text(archive.name).font(.headline).accessibilityAddTraits(.isHeader)
                    Text("\(archive.format.displayName) archive").foregroundStyle(.secondary)
                }
            }

            MetadataGrid(rows: [
                (String(localized: "Files"), archive.files.count.formatted()),
                (String(localized: "Unpacked"), archive.totalSize.bytes),
                (String(localized: "Packed"), archive.packedSize.bytes),
                (String(localized: "Encryption"), archive.isEncrypted ? "AES-256" : String(localized: "None")),
            ])

            VStack(alignment: .leading, spacing: Space.m) {
                SectionLabel(String(localized: "Checkup"))
                ForEach(archive.checkup) { finding in
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
            .accessibilityAddTraits(.isHeader)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}
