import SwiftUI

/// Archive facts remain available from Details and the archive title menu during any selection.
struct ArchiveInfoView: View {
    let model: BrowserModel
    static var opensForDemo = false

    var body: some View {
        let archive = model.archive
        let saved = model.editSession.isEdited ? model.level.savedArchive : nil
        let packedArchive = saved ?? archive
        let packed = Self.packedFigures(packedArchive)
        VStack(alignment: .leading, spacing: Space.l) {
            HStack(alignment: .top, spacing: Space.m) {
                FormatBadge(format: archive.format)
                VStack(alignment: .leading, spacing: 2) {
                    Text(archive.name)
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .help(archive.name)
                    Text("\(archive.format.displayName) archive")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            PropertyList([
                PropertyRow(String(localized: "Files in archive"), archive.files.count.formatted(),
                            detail: saved == nil ? nil : String(localized: "Including unsaved changes")),
                PropertyRow(String(localized: "Total file size"), archive.totalSize.bytes,
                            detail: saved == nil ? nil : String(localized: "Including unsaved changes")),
                PropertyRow(packedArchive.packedSizeIncludesContainer ? String(localized: "Archive file size")
                            : String(localized: "Packed file data"), packed.value,
                            detail: saved == nil ? nil : String(localized: "From the last saved archive")),
            ])
            // Password state has one actionable home here instead of three repeated encryption rows.
            ArchiveLockRow(model: model)
            DisclosureGroup("More Archive Information") {
                VStack(alignment: .leading, spacing: Space.m) {
                    PropertyList([
                        PropertyRow(String(localized: "Encryption"), archive.isEncrypted
                                    ? String(localized: "Encrypted") : String(localized: "None")),
                    ])
                    if let change = packed.change {
                        Text(change).font(.callout)
                        Text("Compared with the file contents before compression. Includes archive overhead when reported.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if !archive.checkup.isEmpty {
                        ArchiveFindingRows(findings: archive.checkup)
                    }
                }
            }
        }
    }

    static func packedFigures(_ archive: Archive) -> (value: String, change: String?) {
        guard let packed = archive.packedSize else { return (String(localized: "Not reported by the archive"), nil) }
        let total = archive.totalSize
        guard total > 0 else { return (packed.bytes, nil) }
        let fraction = Double(packed) / Double(total)
        let change = fraction > 1
            ? String(localized: "\(Int(((fraction - 1) * 100).rounded()))% larger")
            : String(localized: "\(Int(((1 - fraction) * 100).rounded()))% smaller")
        return (packed.bytes, change)
    }
}

/// Relevant findings stay visible while Details shows a selection, including in Glance.
/// A normal archive has no notice. Native disclosure keeps every explanation reachable.
struct ArchiveNotices: View {
    let findings: [CheckupFinding]

    var body: some View {
        let notices = findings.filter { $0.severity == .caution } + findings.filter { $0.severity == .handled }
        if let first = notices.first {
            DisclosureGroup {
                ScrollView {
                    ArchiveFindingRows(findings: notices)
                }
                .frame(maxHeight: 160)
            } label: {
                Label {
                    Text(notices.count == 1 ? first.title : String(localized: "\(first.title) — \(notices.count - 1) more"))
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
            }
            .font(.callout)
        }
    }
}

private struct ArchiveFindingRows: View {
    let findings: [CheckupFinding]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            ForEach(findings) { finding in
                VStack(alignment: .leading, spacing: 2) {
                    Text(finding.title).font(.callout.weight(.medium))
                    if !finding.detail.isEmpty {
                        Text(finding.detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FormatBadge: View {
    let format: ArchiveFormat
    /// Archive Info's is 40 pt tall; Glance's header uses a smaller one. Everything scales with it.
    var height: CGFloat = 40

    var body: some View {
        let scale = height / 40
        Text(format.badge)
            .font(.system(size: 10 * scale, weight: .bold, design: .rounded))
            .tracking(0.4 * scale)
            .foregroundStyle(.white)
            .frame(width: 34 * scale, height: height)
            .background(Color.accentColor.gradient, in: .rect(cornerRadius: 7 * scale))
            .overlay(alignment: .topTrailing) {
                // folded corner, like a parcel label
                let fold = 9 * scale
                Path { path in
                    path.move(to: .zero)
                    path.addLine(to: CGPoint(x: fold, y: fold))
                    path.addLine(to: CGPoint(x: fold, y: 0))
                    path.closeSubpath()
                }
                .fill(.white.opacity(0.35))
                .frame(width: fold, height: fold)
            }
            .accessibilityLabel("\(format.displayName) archive")
    }
}
