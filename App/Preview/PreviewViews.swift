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
    /// The inspector's way: take the height the content needs, up to `fittedMaxHeight`, instead of
    /// filling a frame the caller sets — a few lines of text stay a few lines tall, a photo keeps its
    /// shape. Hover previews and the column view's preview keep their fixed frames.
    let fitsContent: Bool

    /// What was read, and for which entry — a reused view never shows the last entry's content.
    @State private var loaded: (id: String, preview: RichPreview)?
    /// For `fitsContent`: the width on offer, and the height a page of text or a table needs.
    @State private var width: CGFloat = 0
    @State private var pageContentHeight: CGFloat = 0

    static let fittedMaxHeight: CGFloat = 260
    private static let fittedMinHeight: CGFloat = 44
    private static let fittedPlaceholderHeight: CGFloat = 120

    init(entry: ArchiveEntry, model: BrowserModel, preview: RichPreview? = nil, fitsContent: Bool = false) {
        self.entry = entry
        self.model = model
        self.fitsContent = fitsContent
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
                .previewFrame(fitting: fitsContent, height: Self.fittedPlaceholderHeight)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
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
                .previewFrame(fitting: fitsContent, height: fittedHeight(for: image.size))
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
                .frame(maxWidth: .infinity, maxHeight: fitsContent ? nil : .infinity, alignment: .topLeading)
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
                .frame(maxWidth: .infinity, maxHeight: fitsContent ? nil : .infinity, alignment: .topLeading)
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
                .frame(maxWidth: .infinity, maxHeight: fitsContent ? nil : .infinity)
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
            .frame(height: fitsContent ? 180 : nil)
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
            .previewFrame(fitting: fitsContent, height: frame.map { fittedHeight(for: $0.size) } ?? Self.fittedPlaceholderHeight)
        case .unavailable(let reason):
            let isLocked = reason == String(localized: "Locked — needs the archive’s password")
            VStack(spacing: Space.s) {
                NativeIcon(type: entry.contentType).frame(width: 72, height: 72)
                    .overlay(alignment: .bottomTrailing) {
                        // The same lock as the toolbar and archive card, so the three read as one thing.
                        if isLocked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 22, height: 22)
                                .background(.regularMaterial, in: .circle)
                                .overlay { Circle().strokeBorder(.primary.opacity(contrastStyle.faintBorderOpacity)) }
                                .offset(x: 4, y: 4)
                                .accessibilityHidden(true)
                        }
                    }
                if !reason.isEmpty {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                if isLocked {
                    // A spinner in place while this file's password is checked. Both titles and the
                    // glyph stay in the layout (hidden), so the button keeps one size in both states.
                    let title = model.isUnlocking ? String(localized: "Unlocking…") : String(localized: "Enter Password…")
                    Button {
                        model.unlockArchive(for: entry)
                    } label: {
                        Label {
                            ZStack {
                                Text("Enter Password…").hidden()
                                Text("Unlocking…").hidden()
                                Text(title)
                            }
                        } icon: {
                            ZStack {
                                Image(systemName: "lock.fill").hidden()
                                if model.isUnlocking {
                                    ProgressView().controlSize(.mini)
                                } else {
                                    Image(systemName: "lock.fill")
                                }
                            }
                        }
                    }
                    .accessibilityLabel(title)
                    .disabled(model.isUnlocking)
                    .padding(.top, Space.xs)
                }
            }
            .padding(.vertical, fitsContent ? Space.m : 0)
            .previewFrame(fitting: fitsContent)
        }
    }

    private func page(@ViewBuilder _ content: () -> some View) -> some View {
        // The card takes exactly the space it's offered. Long text hangs below it and is cut off,
        // instead of stretching the card past its frame and spilling over the views around it.
        // Fitting content, the card is as tall as the page up to `fittedMaxHeight`.
        let overflows = !fitsContent || pageContentHeight > Self.fittedMaxHeight
        return Color.clear
            .frame(height: fitsContent ? min(max(pageContentHeight, Self.fittedMinHeight), Self.fittedMaxHeight) : nil)
            .overlay(alignment: .top) {
                content()
                    .foregroundStyle(.primary)
                    // Measured at its own height, so the card's height never feeds back into it.
                    .fixedSize(horizontal: false, vertical: fitsContent)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pageContentHeight = $0 }
            }
            .clipped()
            .mask {
                if overflows {
                    // The page runs on past the card; fade the words out rather than cut a line in half.
                    LinearGradient(stops: [.init(color: .black, location: 0.8), .init(color: .clear, location: 0.97)],
                                   startPoint: .top, endPoint: .bottom)
                } else {
                    Color.black
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(.rect(cornerRadius: Radius.chip))
            .overlay { RoundedRectangle(cornerRadius: Radius.chip).strokeBorder(.primary.opacity(contrastStyle.borderOpacity)) }
    }

    /// A picture's height at the width on offer, kept between a sliver and `fittedMaxHeight`.
    private func fittedHeight(for size: CGSize) -> CGFloat {
        guard width > 0, size.width > 0, size.height > 0 else { return Self.fittedPlaceholderHeight }
        return min(max(width * size.height / size.width, 80), Self.fittedMaxHeight)
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

private extension View {
    /// A preview's frame: all the room it's offered, or — fitting its content — the full width at
    /// `height` (its own height when nil).
    @ViewBuilder
    func previewFrame(fitting: Bool, height: CGFloat? = nil) -> some View {
        if fitting {
            frame(maxWidth: .infinity).frame(height: height)
        } else {
            frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
        } else if Self.showsThumbnail(entry), let image = model.previews.cachedThumbnail(for: entry, in: archive, side: 96) {
            // A page is white on the white list; the shadow follows its edge (or a picture's
            // outline) so it never fades into the row.
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .clipShape(.rect(cornerRadius: 2))
                .shadow(color: .black.opacity(0.3), radius: 0.5, y: 0.25)
                .padding(1)
        } else {
            NativeIcon(type: entry.contentType)
        }
    }

    /// As the sample's rows: text, data and fonts keep their type's icon, since a page of text
    /// 18 pt tall reads as a blank page. A tile has the room for theirs.
    static func showsThumbnail(_ entry: ArchiveEntry) -> Bool {
        switch entry.kind {
        case .text, .data, .font: false
        default: true
        }
    }
}
