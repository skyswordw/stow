import SwiftUI

/// What the open archive is: its format, how big, how well it packed, whether it's encrypted, and
/// what Checkup found. The one home for these facts, reached two ways: the inspector shows it while
/// nothing is selected, and the toolbar's Checkup button shows it when the inspector is closed or
/// busy with a selection. Nothing else in the Browser repeats these figures.
struct ArchiveInfoView: View {
    let model: BrowserModel

    var body: some View {
        let archive = model.archive
        // Staged items have no packed size until Save, so the packed figure stays the saved archive's.
        let saved = model.editSession.isEdited ? model.level.savedArchive : nil
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
                MetadataGrid(rows: [
                    (String(localized: "Files"), archive.files.count.formatted()),
                    (String(localized: "Unpacked"), archive.totalSize.bytes),
                    (String(localized: "Packed"), Self.packedDescription(saved ?? archive)),
                    (String(localized: "Encryption"), archive.isEncrypted ? String(localized: "Encrypted") : String(localized: "None")),
                ])
                if saved != nil {
                    Text("As last saved. This updates when you save your changes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // Encrypted archives offer the password right beside the fact that they need one.
                ArchiveLockRow(model: model)
            }

            CheckupFindings(findings: archive.checkup)
        }
    }

    /// "170 bytes · 23% smaller"; a listing that doesn't say how big files are packed says so
    /// instead of reading "100% smaller".
    static func packedDescription(_ archive: Archive) -> String {
        guard let packed = archive.packedSize else { return String(localized: "Unavailable") }
        let total = archive.totalSize
        guard total > 0 else { return packed.bytes }
        let fraction = Double(packed) / Double(total)
        let change = fraction > 1
            ? String(localized: "\(Int(((fraction - 1) * 100).rounded()))% larger")
            : String(localized: "\(Int(((1 - fraction) * 100).rounded()))% smaller")
        return [packed.bytes, change].joined(separator: " · ")
    }
}

/// Checkup's findings in plain words, under its own heading.
private struct CheckupFindings: View {
    let findings: [CheckupFinding]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                SectionLabel(String(localized: "Checkup"))
                Text("Stow inspects every archive before anything touches your disk.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if findings.isEmpty {
                row(symbol: CheckupFinding.Severity.fine.symbol, color: CheckupFinding.Severity.fine.color,
                    title: String(localized: "Nothing to report"), detail: nil)
            }
            ForEach(findings) { finding in
                row(symbol: finding.severity.symbol, color: finding.severity.color,
                    title: finding.title, detail: finding.detail)
            }
        }
    }

    private func row(symbol: String, color: Color, title: String, detail: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Image(systemName: symbol)
                .accessibilityHidden(true)
                .foregroundStyle(color)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium))
                if let detail {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Checkup in one glance: the shield the toolbar shows and the sentence it speaks.
struct CheckupStatus: Equatable {
    let cautions: Int
    let handled: Int

    init(_ findings: [CheckupFinding]) {
        cautions = findings.count { $0.severity == .caution }
        handled = findings.count { $0.severity == .handled }
    }

    var symbol: String { cautions > 0 ? "exclamationmark.shield.fill" : "checkmark.shield.fill" }
    var color: Color { cautions > 0 ? .yellow : .green }

    var summary: String {
        cautions > 0 ? String(localized: "Checkup: \(cautions) things to know")
            : handled > 0 ? String(localized: "Checkup: safe, \(handled) handled")
            : String(localized: "Checkup: looks safe")
    }
}

/// The toolbar's Checkup: always in reach, whichever panes are open. The shield's shape and colour
/// say how it went; the popover is the same Archive Info the empty inspector shows.
struct CheckupToolbarButton: View {
    let model: BrowserModel
    /// Shared with the title's menu, whose Archive Info opens the same popover.
    @Binding var isPresented: Bool
    /// Design review: the popover opens by itself (`-StowScene checkup-format`).
    static var opensForDemo = false

    var body: some View {
        let status = CheckupStatus(model.archive.checkup)
        Button {
            isPresented.toggle()
        } label: {
            Label {
                Text("Checkup")
            } icon: {
                Image(systemName: status.symbol)
                    .foregroundStyle(status.color)
            }
            .labelStyle(.titleAndIcon)
        }
        .help(status.summary)
        .accessibilityLabel(String(localized: "Checkup"))
        .accessibilityValue(status.summary)
        .accessibilityHint(String(localized: "Shows what Checkup found and the archive’s details"))
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            ArchiveInfoView(model: model)
                .padding(Space.l)
                .frame(width: 320)
        }
        .task {
            guard Self.opensForDemo else { return }
            try? await Task.sleep(for: .milliseconds(500))
            isPresented = true
        }
    }
}

struct FormatBadge: View {
    let format: ArchiveFormat

    var body: some View {
        Text(format.badge)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .tracking(0.4)
            .foregroundStyle(.white)
            .frame(width: 34, height: 40)
            .background(Color.accentColor.gradient, in: .rect(cornerRadius: 7))
            .overlay(alignment: .topTrailing) {
                // folded corner, like a parcel label
                Path { path in
                    path.move(to: .zero)
                    path.addLine(to: CGPoint(x: 9, y: 9))
                    path.addLine(to: CGPoint(x: 9, y: 0))
                    path.closeSubpath()
                }
                .fill(.white.opacity(0.35))
                .frame(width: 9, height: 9)
            }
            .accessibilityLabel("\(format.displayName) archive")
    }
}
