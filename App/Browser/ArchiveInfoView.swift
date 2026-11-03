import SwiftUI

/// Archive facts: Details shows them while nothing is selected, and the title menu opens them during
/// any selection. The three figures people compare come first; routine facts and the archive's
/// ordinary notes wait behind More Archive Information, so a normal archive promotes nothing.
struct ArchiveInfoView: View {
    let model: BrowserModel
    static var opensForDemo = false
    /// Design review: More Archive Information starts open (`-StowScene details-more`).
    static var disclosesForDemo = false
    @State private var showsMore = ArchiveInfoView.disclosesForDemo
    @Environment(\.reducesMotion) private var reduceMotion

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
            VStack(alignment: .leading, spacing: Space.s) {
                // Each figure says whether it already counts the pending edits (in the accent, as
                // the files' own “New” tags are) or still describes the saved archive.
                PropertyList([
                    PropertyRow(String(localized: "Files in archive"), archive.files.count.formatted(),
                                detail: saved == nil ? nil : String(localized: "Including unsaved changes"), tone: .pending),
                    PropertyRow(String(localized: "Total file size"), archive.totalSize.bytes,
                                detail: saved == nil ? nil : String(localized: "Including unsaved changes"), tone: .pending),
                    PropertyRow(packedArchive.packedSizeIncludesContainer ? String(localized: "Archive file size")
                                : String(localized: "Packed file data"), packed.value,
                                detail: saved == nil ? nil : String(localized: "From the last saved archive")),
                ])
                // The password's status and its action are one control, right under the figures.
                ArchiveLockRow(model: model)
            }
            DisclosureGroup(isExpanded: $showsMore) {
                VStack(alignment: .leading, spacing: Space.m) {
                    let rows = Self.moreRows(isEncrypted: archive.isEncrypted, change: packed.change)
                    if !rows.isEmpty {
                        VStack(alignment: .leading, spacing: Space.xs) {
                            PropertyList(rows)
                            if packed.change != nil {
                                Text("Compared with the file contents before compression. Includes archive overhead when reported.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    if !archive.checkup.isEmpty {
                        ArchiveFindingRows(findings: archive.checkup)
                    }
                }
                .padding(.top, Space.s)
            } label: {
                Text("More Archive Information")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .animation(Motion.resolved(Motion.status, reduceMotion: reduceMotion), value: showsMore)
            .onReceive(NotificationCenter.default.publisher(for: DemoBurst.request)) { note in
                if note.object as? String == "archive-info" { showsMore.toggle() }
            }
        }
    }

    /// The disclosed facts. An encrypted archive's password row already says so above, so
    /// Encryption only appears here when it's None. The size change is a ratio worth looking up,
    /// not a warning, so it lives here rather than beside the packed figure.
    static func moreRows(isEncrypted: Bool, change: String?) -> [PropertyRow] {
        (isEncrypted ? [] : [PropertyRow(String(localized: "Encryption"), String(localized: "None"))])
            + (change.map { [PropertyRow(String(localized: "Size change"), $0)] } ?? [])
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

/// The findings that need attention, with the files in Browser and Glance whatever is selected. A
/// normal archive shows nothing here. One tinted card: the most important finding is the label,
/// and opening it gives that finding's consequence, then the rest. Native disclosure, so its
/// keyboard and accessibility behaviour stay the system's.
struct ArchiveNotices: View {
    enum Placement {
        /// Under the Browser's navigation capsule, aligned with it.
        case browser
        /// Under Glance's header, inside its inset.
        case glance
    }

    let findings: [CheckupFinding]
    var placement: Placement = .browser
    /// Design review: the card starts open (`-StowScene details-notices-open`).
    static var expandsForDemo = false
    @State private var isExpanded = ArchiveNotices.expandsForDemo
    @Environment(\.reducesMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let notices = findings.filter { $0.severity == .caution } + findings.filter { $0.severity == .handled }
        if let first = notices.first {
            let severity = first.severity
            let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            DisclosureGroup(isExpanded: $isExpanded) {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.m) {
                        // The label already names the first finding; here is what it means.
                        if !first.detail.isEmpty {
                            Text(first.detail)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                // Under the label's words, past its glyph.
                                .padding(.leading, 22)
                        }
                        if notices.count > 1 {
                            ArchiveFindingRows(findings: Array(notices.dropFirst()))
                        }
                    }
                    // Glyphs under the label's glyph, words under its words.
                    .padding(.leading, 12)
                    .padding(.top, Space.xs)
                    .padding(.bottom, 2)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: 160)
                .fixedSize(horizontal: false, vertical: true)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    FindingGlyph(severity: severity)
                    Text(first.title)
                        .fontWeight(.medium)
                        .lineLimit(isExpanded ? 3 : 1)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: isExpanded)
                        .help(first.title)
                    if notices.count > 1, !isExpanded {
                        Text("+\(notices.count - 1) more")
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
            .font(.callout)
            .padding(.horizontal, Space.m)
            .padding(.vertical, 7)
            // Dark mode needs less: yellow over a dark surface turns olive quickly.
            .background(severity.color.opacity(colorScheme == .dark ? 0.09 : 0.1), in: shape)
            .overlay {
                // Increase Contrast: the border every surface takes then. A yellow edge, however
                // strong, stays faint against the card's own yellow tint in light mode (#104).
                shape.strokeBorder(ContrastStyle.resolve(contrast).increased
                                   ? AnyShapeStyle(.primary.opacity(ContrastStyle(increased: true).borderOpacity))
                                   : AnyShapeStyle(severity.color.opacity(colorScheme == .dark ? 0.18 : 0.28)))
                    .allowsHitTesting(false)
            }
            .animation(Motion.resolved(Motion.status, reduceMotion: reduceMotion), value: isExpanded)
            .onReceive(NotificationCenter.default.publisher(for: DemoBurst.request)) { note in
                if note.object as? String == "notices" { isExpanded.toggle() }
            }
            .padding(.horizontal, placement == .browser ? Space.m : 0)
            .padding(.bottom, Space.s)
        }
    }
}

/// Findings as rows: a quiet glyph for the kind, the finding, and what it means. Ordinary notes
/// (fine, info) take the secondary colour, so an all-clear never reads as a badge.
struct ArchiveFindingRows: View {
    let findings: [CheckupFinding]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            ForEach(findings) { finding in
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    FindingGlyph(severity: finding.severity)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(finding.title).font(.callout.weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)
                        if !finding.detail.isEmpty {
                            Text(finding.detail)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A finding's kind as a glyph. A caution is the system's multicolour warning triangle, which
/// stays legible on the notice's own tint; a fine note is a plain outline, never a green badge.
struct FindingGlyph: View {
    let severity: CheckupFinding.Severity

    var body: some View {
        Group {
            switch severity {
            case .caution:
                Image(systemName: severity.symbol).symbolRenderingMode(.multicolor)
            case .fine:
                Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
            case .info, .handled:
                Image(systemName: severity.symbol).foregroundStyle(severity.color)
            }
        }
        .frame(width: 14)
        .accessibilityHidden(true)
    }
}
