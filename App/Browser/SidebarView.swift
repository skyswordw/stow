import SwiftUI

struct SidebarView: View {
    @Bindable var model: BrowserModel

    var body: some View {
        List(selection: folderSelection) {
            Label("All Files", systemImage: "square.grid.2x2")
                .tag("")
            OutlineGroup(model.archive.folderTree(includingHelpers: model.showHelperItems), children: \.children) { node in
                Label(node.name, systemImage: "folder")
                    .tag(node.id)
            }
        }
        .listStyle(.sidebar)
        // Above the list rather than in a section header: a header row has a fixed height, so a long
        // name or a narrow sidebar clipped or truncated the card. Here it takes the height it needs.
        .safeAreaInset(edge: .top, spacing: 0) {
            ArchiveCard(archive: model.archive)
                .padding(.horizontal, Space.m)
                .padding(.bottom, Space.s)
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

/// The archive at a glance: what it is, how big, how well it packed, and whether it's safe.
struct ArchiveCard: View {
    let archive: Archive
    @State private var showCheckup = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            // Badge beside the name while the name has room for a few words; on a narrow sidebar
            // the name gets a line of its own. ViewThatFits decides from ideal sizes, so there is
            // no measure-then-relayout loop.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: Space.m) {
                    FormatBadge(format: archive.format)
                    titleAndCounts
                        .frame(minWidth: 120, idealWidth: 120, maxWidth: .infinity, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: Space.s) {
                    FormatBadge(format: archive.format)
                    titleAndCounts
                }
            }

            CompressionBar(packed: archive.packedSize, total: archive.totalSize)

            Button {
                showCheckup.toggle()
            } label: {
                CheckupBadge(archive: archive)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showCheckup, arrowEdge: .trailing) {
                CheckupView(findings: archive.checkup)
            }
        }
        .padding(Space.m)
        .background(.background.opacity(0.5), in: .rect(cornerRadius: Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card).strokeBorder(.primary.opacity(0.06))
        }
        .textCase(nil)
    }

    private var titleAndCounts: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(archive.name)
                .font(.headline)
                .lineLimit(3)
                .help(archive.name)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.primary)
            ViewThatFits(in: .horizontal) {
                Text("\(archive.files.count.formatted()) files · \(archive.totalSize.bytes)")
                    .fixedSize()
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(archive.files.count.formatted()) files")
                    Text(archive.totalSize.bytes)
                }
            }
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
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
                .padding([.top, .trailing], 0)
            }
            .accessibilityLabel("\(format.displayName) archive")
    }
}

struct CompressionBar: View {
    let packed: Int64
    let total: Int64

    private var fraction: Double { total > 0 ? Double(packed) / Double(total) : 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(.tint).frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 4)
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("\(packed.bytes) packed")
                        .fixedSize()
                    Spacer()
                    Text("\(Int(((1 - fraction) * 100).rounded()))% smaller")
                        .fixedSize()
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(packed.bytes) packed")
                    Text("\(Int(((1 - fraction) * 100).rounded()))% smaller")
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct CheckupBadge: View {
    let archive: Archive
    @State private var isHovering = false

    var body: some View {
        let cautions = archive.checkup.count { $0.severity == .caution }
        let caution = cautions > 0
        let handled = archive.checkup.count { $0.severity == .handled }
        let label = Text(caution ? String(localized: "Checkup: \(cautions) things to know")
                         : handled > 0 ? String(localized: "Checkup: safe, \(handled) handled") : String(localized: "Checkup: looks safe"))
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
            .font(.caption.weight(.medium))
            .foregroundStyle(.primary)
        let shield = Image(systemName: caution ? "exclamationmark.shield.fill" : "checkmark.shield.fill")
            .foregroundStyle(caution ? .yellow : .green)
        // The chevron goes first when the card is narrow, so the label keeps whole words.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                shield
                label.frame(minWidth: 110, idealWidth: 110, maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            HStack(spacing: 6) {
                shield
                label.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, Space.s)
        .padding(.vertical, 6)
        .background(.primary.opacity(isHovering ? 0.08 : 0.04), in: .rect(cornerRadius: Radius.chip))
        .contentShape(.rect)
        .onHover { isHovering = $0 }
    }
}

struct CheckupView: View {
    let findings: [CheckupFinding]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Checkup")
                    .font(.headline)
                Text("Stow inspects every archive before anything touches your disk.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(findings) { finding in
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Image(systemName: finding.severity.symbol)
                        .foregroundStyle(finding.severity.color)
                        .frame(width: 18)
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
        .padding(Space.l)
        .frame(width: 320)
    }
}
