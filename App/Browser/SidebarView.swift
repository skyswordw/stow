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
            // Staged items have no packed size until Save, so the packed figures stay the saved archive's.
            ArchiveCard(archive: model.archive, packedFrom: model.editSession.isEdited ? model.level.savedArchive : nil)
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
    @Environment(\.colorSchemeContrast) private var contrast
    private var contrastStyle: ContrastStyle { .resolve(contrast) }
    let archive: Archive
    /// Whose packed size and ratio to show, when not `archive`'s (the saved archive while edits are staged).
    var packedFrom: Archive?
    @State private var showCheckup = false
    /// Design review: the Checkup popover opens by itself (`-StowScene checkup-format`).
    static var opensCheckupForDemo = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .top, spacing: Space.m) {
                FormatBadge(format: archive.format)
                VStack(alignment: .leading, spacing: 2) {
                    Text(archive.name)
                        .font(.headline).accessibilityAddTraits(.isHeader)
                        .lineLimit(3)
                        .help(archive.name)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(.primary)
                    ViewThatFits(in: .horizontal) {
                        Text("\(archive.files.count) files · \(archive.totalSize.bytes)")
                            .fixedSize()
                        VStack(alignment: .leading, spacing: 0) {
                            Text("\(archive.files.count) files")
                            Text(archive.totalSize.bytes)
                        }
                    }
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            let figures = packedFrom ?? archive
            // A listing that doesn't say how big files are packed would read "100% smaller"; say nothing instead.
            if let packed = figures.packedSize {
                CompressionBar(packed: packed, total: figures.totalSize)
                    .help(packedFrom == nil ? "" : String(localized: "As last saved. This updates when you save your changes."))
            }

            Button {
                showCheckup.toggle()
            } label: {
                CheckupBadge(archive: archive)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Checkup"))
            .help("Checkup")
            .popover(isPresented: $showCheckup, arrowEdge: .trailing) {
                CheckupView(findings: archive.checkup)
            }
            .task {
                guard Self.opensCheckupForDemo else { return }
                try? await Task.sleep(for: .milliseconds(500))
                showCheckup = true
            }
        }
        .padding(Space.m)
        .background(Color(nsColor: .windowBackgroundColor), in: .rect(cornerRadius: Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card).strokeBorder(.primary.opacity(contrastStyle.faintBorderOpacity))
        }
        .textCase(nil)
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
    private var sizeChange: String {
        if fraction > 1 {
            String(localized: "\(Int(((fraction - 1) * 100).rounded()))% larger")
        } else {
            String(localized: "\(Int(((1 - fraction) * 100).rounded()))% smaller")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(.tint).frame(width: proxy.size.width * min(max(fraction, 0), 1))
                }
            }
            .frame(height: 4)
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("\(packed.bytes) packed")
                        .fixedSize()
                    Spacer()
                    Text(sizeChange)
                        .fixedSize()
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(packed.bytes) packed")
                    Text(sizeChange)
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
    @Environment(\.colorSchemeContrast) private var contrast
    private var contrastStyle: ContrastStyle { .resolve(contrast) }
    let archive: Archive
    @State private var isHovering = false

    var body: some View {
        let cautions = archive.checkup.count { $0.severity == .caution }
        let caution = cautions > 0
        let handled = archive.checkup.count { $0.severity == .handled }
        HStack(spacing: 6) {
            Image(systemName: caution ? "exclamationmark.shield.fill" : "checkmark.shield.fill")
                .foregroundStyle(caution ? .yellow : .green)
            Text(caution ? String(localized: "Checkup: \(cautions) things to know")
                 : handled > 0 ? String(localized: "Checkup: safe, \(handled) handled") : String(localized: "Checkup: looks safe"))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .accessibilityHidden(true)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(contrastStyle.metadata)
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
                    .font(.headline).accessibilityAddTraits(.isHeader)
                Text("Stow inspects every archive before anything touches your disk.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(findings) { finding in
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Image(systemName: finding.severity.symbol)
                        .accessibilityHidden(true)
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

extension View {
    /// The browser's sidebar column width. The extra `frame(minWidth:)` matters: SwiftUI measures a
    /// column's minimum size with a zero proposal, not the minimum width declared here. Measured that
    /// narrow, the archive card wraps its captions a few characters per line and grows ~700 pt tall,
    /// and a minimum that tall can fight the window until AppKit throws "more Update Constraints in
    /// Window passes than there are views" — whether it does depends on the digits in the sizes.
    func sidebarColumnWidth() -> some View {
        frame(minWidth: SidebarView.minWidth)
            .navigationSplitViewColumnWidth(min: SidebarView.minWidth, ideal: 248, max: 320)
    }
}

extension SidebarView {
    static let minWidth: CGFloat = 220
}
