import AppKit
import SwiftUI

/// An icon-view tile's picture: the file's real Quick Look thumbnail once it's ready, the type's
/// icon until then (or for good, when there's nothing better). Sample archives keep their art.
struct LiveThumbnail: View {
    let entry: ArchiveEntry
    let model: BrowserModel
    var side: CGFloat = 96

    @State private var image: NSImage?

    var body: some View {
        let archive = model.archive
        Group {
            if archive.source == nil {
                EntryThumbnail(entry: entry, style: .tile)
            } else if let image = image ?? model.previews.cachedThumbnail(for: entry, in: archive, side: side) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .shadow(color: .black.opacity(0.12), radius: 1.5, y: 0.5)
                    .transition(.opacity.animation(Motion.current(Motion.preview)))
            } else {
                NativeIcon(type: entry.contentType)
                    .padding(4)
            }
        }
        // Only tiles on screen exist, so only they ask; scrolling away cancels the request.
        .task(id: "\(archive.id)\(entry.id)\(model.previewRevision)") {
            guard archive.source != nil, PreviewService.wantsThumbnail(entry) else { return }
            image = nil
            if let thumbnail = await model.previews.thumbnail(for: entry, in: archive, side: side) {
                image = thumbnail
            }
        }
    }
}

/// The entry's real content — picture, text, table, font, artwork or a video frame — for hover
/// previews, the inspector and the column view's preview column.
struct RichPreviewView: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    private var contrastStyle: ContrastStyle { .resolve(contrast) }
    let entry: ArchiveEntry
    let model: BrowserModel

    /// What was read, and for which entry — a reused view never shows the last entry's content.
    @State private var loaded: (id: String, preview: RichPreview)?

    init(entry: ArchiveEntry, model: BrowserModel, preview: RichPreview? = nil) {
        self.entry = entry
        self.model = model
        _loaded = State(initialValue: preview.map { ("\(model.archive.id)\(entry.id)\(model.previewRevision)", $0) })
    }

    var body: some View {
        let archive = model.archive
        let id = "\(archive.id)\(entry.id)\(model.previewRevision)"
        ZStack {
            if archive.source == nil {
                EntryThumbnail(entry: entry, style: .large)
            } else if let loaded, loaded.id == id {
                content(loaded.preview)
            } else {
                VStack(spacing: Space.s) {
                    NativeIcon(type: entry.contentType).frame(width: 64, height: 64)
                    ProgressView().controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: id) {
            guard archive.source != nil, loaded?.id != id else { return }
            let result = await model.previews.richPreview(for: entry, in: archive)
            guard !Task.isCancelled else { return }
            loaded = (id, result)
        }
    }

    @ViewBuilder
    private func content(_ preview: RichPreview) -> some View {
        switch preview {
        case .image(let image), .thumbnail(let image):
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .clipShape(.rect(cornerRadius: Radius.chip))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .text(let text, let markdown):
            page {
                Group {
                    if markdown {
                        Text(Self.markdown(text))
                            .font(.system(size: 11))
                            .lineSpacing(1.5)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        // Code and logs keep their lines: long ones run off the edge instead of wrapping.
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(text.split(separator: "\n", omittingEmptySubsequences: false).prefix(40).enumerated()),
                                    id: \.offset) { _, line in
                                Text(line.isEmpty ? " " : String(line).replacingOccurrences(of: "\t", with: "    "))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                        .font(.system(size: 10, design: .monospaced))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(Space.m)
            }
        case .table(let rows):
            page {
                Grid(alignment: .leading, horizontalSpacing: Space.m, verticalSpacing: 3) {
                    ForEach(rows.indices, id: \.self) { index in
                        GridRow {
                            ForEach(rows[index].indices, id: \.self) { column in
                                Text(rows[index][column])
                                    .fontWeight(index == 0 ? .semibold : .regular)
                                    .lineLimit(1)
                            }
                        }
                        if index == 0 { Divider() }
                    }
                }
                .font(.system(size: 10).monospacedDigit())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(Space.m)
            }
        case .font(let font, let name):
            page {
                VStack(spacing: Space.s) {
                    Text("Aa").font(Font(font))
                    Text(name).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Text("Pack my box with five dozen liquor jugs")
                        .font(Font(CTFontCreateCopyWithAttributes(font, 13, nil, nil)))
                        .lineLimit(1)
                }
                .padding(Space.m)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .audio(let artwork, let title, let artist, let duration):
            VStack(spacing: Space.s) {
                Group {
                    if let artwork {
                        Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fit)
                            .clipShape(.rect(cornerRadius: Radius.chip))
                    } else {
                        Image(systemName: "music.note")
                            .font(.system(size: 44, weight: .light))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: Radius.chip))
                    }
                }
                .frame(maxHeight: .infinity)
                VStack(spacing: 1) {
                    Text(title ?? entry.name).font(.callout.weight(.medium)).lineLimit(1)
                    Text([artist, duration.map(Self.clock)].compactMap(\.self).joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
        case .video(let frame, let duration):
            ZStack(alignment: .bottomTrailing) {
                if let frame {
                    Image(nsImage: frame).resizable().aspectRatio(contentMode: .fit)
                        .clipShape(.rect(cornerRadius: Radius.chip))
                } else {
                    NativeIcon(type: entry.contentType).frame(width: 72, height: 72)
                }
                if let duration {
                    Label(Self.clock(duration), systemImage: "play.fill")
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(reduceTransparency || UserDefaults.standard.bool(forKey: "StowReduceTransparency") ? 1 : 0.55), in: .capsule)
                        .foregroundStyle(.white)
                        .padding(6)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unavailable(let reason):
            VStack(spacing: Space.s) {
                NativeIcon(type: entry.contentType).frame(width: 72, height: 72)
                if !reason.isEmpty {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                if reason == String(localized: "Locked — needs the archive’s password") {
                    Button("Enter Password…", systemImage: "lock.fill") { model.unlockArchive(for: entry) }
                        .disabled(model.isUnlocking)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func page(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .foregroundStyle(.primary)
            .mask {
                // The page runs on past the card; fade the words out rather than cut a line in half.
                LinearGradient(stops: [.init(color: .black, location: 0.8), .init(color: .clear, location: 0.97)],
                               startPoint: .top, endPoint: .bottom)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(.rect(cornerRadius: Radius.chip))
            .overlay { RoundedRectangle(cornerRadius: Radius.chip).strokeBorder(.primary.opacity(contrastStyle.borderOpacity)) }
    }

    /// Enough Markdown for a glance: headings, bullets and inline styles, line by line.
    static func markdown(_ text: String) -> AttributedString {
        var result = AttributedString()
        for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).prefix(60).enumerated() {
            if index > 0 { result += AttributedString("\n") }
            var body = String(line)
            var heading = 0
            while body.hasPrefix("#") { body.removeFirst(); heading += 1 }
            if heading > 0 { body = body.trimmingCharacters(in: .whitespaces) }
            if body.hasPrefix("- ") || body.hasPrefix("* ") { body = "•  " + body.dropFirst(2) }
            var piece = (try? AttributedString(markdown: body, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                ?? AttributedString(body)
            if heading > 0 { piece.font = .system(size: heading == 1 ? 15 : 13, weight: .semibold) }
            result += piece
        }
        return result
    }

    static func clock(_ seconds: Double) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }
}

/// A list or column row's icon: the real thumbnail when one is already made, otherwise the
/// type's icon. (Sample archives keep their art.)
struct RowIcon: View {
    let entry: ArchiveEntry
    let model: BrowserModel

    var body: some View {
        let archive = model.archive
        if archive.source == nil {
            EntryThumbnail(entry: entry, style: .row)
        } else if let image = model.previews.cachedThumbnail(for: entry, in: archive, side: 96) {
            Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
        } else {
            NativeIcon(type: entry.contentType)
        }
    }
}
