import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The system's own document icon for a type — exactly what Finder shows.
struct NativeIcon: View {
    let type: UTType

    var body: some View {
        Image(decorative: Self.bitmap(for: type), scale: 2)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
    }

    /// Drawn once per type at 128 pt: a multi-resolution icon redrawn for every tile that scrolls
    /// into a 100,000-item grid is a dropped frame.
    static var bitmaps: [String: CGImage] = [:] // demo scenes seed the sample app's icon

    static func bitmap(for type: UTType) -> CGImage {
        if let hit = bitmaps[type.identifier] { return hit }
        let icon = NSWorkspace.shared.icon(for: type)
        var rect = CGRect(x: 0, y: 0, width: 256, height: 256)
        let image = icon.cgImage(forProposedRect: &rect, context: nil, hints: nil)
            ?? NSImage(size: CGSize(width: 1, height: 1)).cgImage(forProposedRect: nil, context: nil, hints: nil)!
        bitmaps[type.identifier] = image
        return image
    }
}

/// How the sample archive's entries are drawn: from the real files in Resources/Sample (see
/// `SampleContent`). Anything without one — or a search result inside a real inner archive — shows
/// the type's icon, never made-up art.
struct EntryThumbnail: View {
    @Environment(\.colorSchemeContrast) private var contrast
    private var contrastStyle: ContrastStyle { .resolve(contrast) }
    enum Style { case row, tile, large }

    let entry: ArchiveEntry
    let style: Style

    var body: some View {
        switch (style, entry.kind) {
        case (.row, .font), (.row, .text), (.row, .data):
            NativeIcon(type: entry.contentType)
        case (_, .font):
            if let font = SampleContent.font(for: entry, size: style == .tile ? 34 : 64) {
                fontSpecimen(font)
            } else {
                icon
            }
        case (_, .text), (_, .data):
            if let text = SampleContent.text(for: entry) {
                textPage(text)
            } else {
                icon
            }
        default:
            if let image = SampleContent.image(for: entry, pixels: style == .row ? 64 : style == .tile ? 360 : 900) {
                picture(image)
            } else {
                icon
            }
        }
    }

    @ViewBuilder private var icon: some View {
        switch style {
        case .row: NativeIcon(type: entry.contentType)
        case .tile: NativeIcon(type: entry.contentType).padding(4)
        case .large: NativeIcon(type: entry.contentType).frame(width: 112, height: 112).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private func picture(_ image: NSImage) -> some View {
        let art = Image(nsImage: image).resizable().interpolation(.high)
        switch (style, entry.kind) {
        case (.row, .image):
            art.aspectRatio(contentMode: .fit).clipShape(.rect(cornerRadius: 2)).padding(1)
        case (.row, _):
            art.aspectRatio(contentMode: .fit)
        case (.tile, .app):
            art.aspectRatio(contentMode: .fit).padding(4)
        case (.large, .app):
            art.aspectRatio(contentMode: .fit).frame(width: 112, height: 112).frame(maxWidth: .infinity, maxHeight: .infinity)
        case (_, .image) where image.size.width >= image.size.height:
            // Photos fill a 4:3 frame, like a contact sheet; screens and other tall art fit whole.
            Color.clear
                .aspectRatio(4 / 3, contentMode: .fit)
                .overlay { art.aspectRatio(contentMode: .fill) }
                .clipShape(.rect(cornerRadius: radius))
                .overlay { RoundedRectangle(cornerRadius: radius).strokeBorder(.primary.opacity(0.08)) }
        case (_, .image), (.tile, .document), (.tile, .video):
            art.aspectRatio(contentMode: .fit)
                .clipShape(.rect(cornerRadius: style == .tile ? 4 : Radius.chip))
                .overlay { RoundedRectangle(cornerRadius: style == .tile ? 4 : Radius.chip).strokeBorder(.primary.opacity(0.1)) }
                .shadow(color: .black.opacity(0.12), radius: 1.5, y: 0.5)
        case (_, .vector):
            // Logos are drawn for a white page, in either appearance.
            Color.white
                .aspectRatio(4 / 3, contentMode: .fit)
                .overlay { art.aspectRatio(contentMode: .fit).padding(style == .tile ? 6 : 28) }
                .clipShape(.rect(cornerRadius: radius))
                .overlay { RoundedRectangle(cornerRadius: radius).strokeBorder(.primary.opacity(contrastStyle.borderOpacity)) }
        case (.large, .video):
            card { art.aspectRatio(contentMode: .fill) }
                .overlay(alignment: .bottomTrailing) {
                    Label(RichPreviewView.clock(6), systemImage: "play.fill")
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.55), in: .capsule)
                        .foregroundStyle(.white)
                        .padding(6)
                }
        default:
            card { art.aspectRatio(contentMode: .fill) }
        }
    }

    private var radius: CGFloat { style == .tile ? Radius.chip : Radius.card }

    @ViewBuilder private func fontSpecimen(_ font: CTFont) -> some View {
        let specimen = VStack(spacing: Space.xs) {
            Text("Aa").font(Font(font))
            if style == .large {
                Text("Pack my box with five dozen jugs")
                    .font(Font(CTFontCreateCopyWithAttributes(font, 13, nil, nil)))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Space.s)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        if style == .large {
            card { specimen }
        } else {
            specimen
                .aspectRatio(4 / 3, contentMode: .fit)
                .clipShape(.rect(cornerRadius: Radius.chip))
                .overlay { RoundedRectangle(cornerRadius: Radius.chip).strokeBorder(.primary.opacity(contrastStyle.borderOpacity)) }
        }
    }

    /// The file's own words on a page. A tile shows the whole page shrunk, like a Finder thumbnail.
    @ViewBuilder private func textPage(_ text: String) -> some View {
        let page = TextPage(text: text, markdown: (entry.name as NSString).pathExtension.lowercased() == "md")
        if style == .large {
            card { page }
        } else {
            Color(nsColor: .textBackgroundColor)
                .aspectRatio(0.78, contentMode: .fit)
                .overlay {
                    GeometryReader { proxy in
                        page.frame(width: 300, height: 385).scaleEffect(proxy.size.width / 300, anchor: .topLeading)
                    }
                }
                .clipShape(.rect(cornerRadius: 3))
                .overlay { RoundedRectangle(cornerRadius: 3).strokeBorder(.primary.opacity(0.12)) }
                .shadow(color: .black.opacity(0.12), radius: 1.5, y: 0.5)
        }
    }

    private func card(@ViewBuilder _ content: () -> some View) -> some View {
        Color.clear
            .aspectRatio(4 / 3, contentMode: .fit)
            .overlay { content() }
            .clipShape(.rect(cornerRadius: Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card).strokeBorder(.primary.opacity(contrastStyle.borderOpacity))
            }
    }
}

/// A text file's first lines, set the way the hover preview sets them.
private struct TextPage: View {
    let text: String
    let markdown: Bool

    var body: some View {
        Group {
            if markdown {
                Text(RichPreviewView.markdown(text)).font(.system(size: 11)).lineSpacing(1.5)
            } else {
                Text(text.split(separator: "\n", omittingEmptySubsequences: false).prefix(40).joined(separator: "\n"))
                    .font(.system(size: 10, design: .monospaced))
                    .lineSpacing(2)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(Space.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(.primary)
        .mask {
            LinearGradient(stops: [.init(color: .black, location: 0.8), .init(color: .clear, location: 0.97)],
                           startPoint: .top, endPoint: .bottom)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}
