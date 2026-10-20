import SwiftUI
import UniformTypeIdentifiers

/// The empty window is the drop target: it says what dropping will do.
struct WelcomeView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: Space.xl) {
            dropZone
            recents
        }
        .padding(Space.xxl)
        .frame(minWidth: 560, minHeight: 480)
    }

    private var dropZone: some View {
        VStack(spacing: Space.l) {
            Image(systemName: isTargeted ? "shippingbox.and.arrow.backward.fill" : "shippingbox")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(isTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .contentTransition(.symbolEffect(.replace))
                .frame(height: 64)

            VStack(spacing: Space.xs) {
                Text(isTargeted ? "Let go to open" : "Drop to open or pack")
                    .font(.title2.weight(.semibold))
                    .contentTransition(.opacity)
                Text("Archives open here. Anything else gets packed.")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                ForEach(["ZIP", "7Z", "RAR", "TAR", "GZ", "XZ", "DMG", "ISO"], id: \.self) { format in
                    Text(format)
                        .font(.caption2.weight(.semibold))
                        .tracking(0.3)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.primary.opacity(0.05), in: .rect(cornerRadius: 5))
                }
                Text("+ 25 more")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)

            HStack(spacing: Space.s) {
                Button("Open Archive…") { app.isChoosingArchive = true }
                Button("Try the Sample") { app.openArchive(named: SampleArchive.make().name) }
                    .buttonStyle(.glassProminent)
            }
            .controlSize(.large)
            .padding(.top, Space.s)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: Radius.panel + 4)
                .fill(isTargeted ? AnyShapeStyle(.tint.opacity(0.08)) : AnyShapeStyle(.clear))
                .strokeBorder(isTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator),
                              style: StrokeStyle(lineWidth: isTargeted ? 2 : 1.5, dash: isTargeted ? [] : [7, 6]))
        }
        .scaleEffect(isTargeted && !reduceMotion ? 1.015 : 1)
        .animation(Motion.resolved(Motion.target, reduceMotion: reduceMotion), value: isTargeted)
        .dropDestination(for: URL.self) { urls, _ in
            handleDrop(urls)
        } isTargeted: { isTargeted = $0 }
    }

    private var recents: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionLabel("Recent")
            HStack(spacing: Space.m) {
                ForEach(Self.recentNames, id: \.self) { name in
                    Button { app.openArchive(named: name) } label: {
                        HStack(spacing: Space.s) {
                            FormatBadge(format: ArchiveFormat.infer(fromName: name) ?? .zip)
                                .scaleEffect(0.7)
                                .frame(width: 26, height: 30)
                            Text(name)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .padding(.horizontal, Space.s)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                    }
                    .buttonStyle(RecentButtonStyle())
                }
            }
        }
    }

    private func handleDrop(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty else { return false }
        if urls.count == 1, ArchiveFormat.infer(fromName: urls[0].lastPathComponent) != nil {
            app.open(urls[0])
        } else {
            app.pack(urls)
        }
        return true
    }

    private static let recentNames = ["Harbor Rebrand Handoff.zip", "Field Recordings.7z", "server-logs.tar.xz"]
}

private struct RecentButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(.primary.opacity(configuration.isPressed ? 0.1 : isHovering ? 0.05 : 0),
                        in: .rect(cornerRadius: Radius.chip))
            .onHover { isHovering = $0 }
    }
}

extension URL {
    var fileSize: Int64 {
        Int64((try? resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
}
