import AppKit
import CoreText
import ImageIO

/// The real files behind the sample archive, bundled from Resources/Sample (sources and licenses in
/// its CREDITS.md). The sample is only a listing, so these give its photos, documents, fonts and
/// logos something real to show — the same content in the screenshots, the video and Try the Sample.
enum SampleContent {
    /// The bundled file for a sample entry, or nil. Entries match on size and date as well as being
    /// in the sample, so a real archive's "Photos/Lighthouse.jpg" never shows sample art, and a
    /// sample entry renamed in the editing demo keeps its own.
    static func url(for entry: ArchiveEntry) -> URL? {
        guard !entry.isFolder, let path = files[key(entry)] ?? undated(entry) else { return nil }
        return folder?.appending(path: path)
    }

    /// The editing demo rebuilds the sample from its edit plan, which keeps sizes but not dates.
    private static func undated(_ entry: ArchiveEntry) -> String? {
        guard entry.modified == .distantPast else { return nil }
        let type = (entry.name as NSString).pathExtension.lowercased()
        guard let match = bySize[entry.size], (match.path as NSString).pathExtension.lowercased() == type else { return nil }
        return match.file
    }

    /// The bundled file, only when it's the same kind of file as the entry (Quick Look shows it as is).
    static func previewFile(for entry: ArchiveEntry) -> URL? {
        guard let url = url(for: entry),
              url.pathExtension.lowercased() == (entry.name as NSString).pathExtension.lowercased() else { return nil }
        return url
    }

    /// A picture of the entry at most `pixels` on its long side: the photo or screen itself, an
    /// SVG's artwork, a PDF's first page, a video's poster frame, or the sample app's icon.
    static func image(for entry: ArchiveEntry, pixels: Int) -> NSImage? {
        if entry.kind == .app, keys.contains(key(entry)) { return NSImage(named: "DemoAppIcon") }
        guard let url = url(for: entry) else { return nil }
        let cacheKey = "\(url.path)\n\(pixels)"
        if let hit = images[cacheKey] { return hit }
        let image: NSImage? = switch url.pathExtension.lowercased() {
        case "svg": NSImage(contentsOf: url)
        case "pdf": firstPage(url, pixels: pixels)
        default: downsampled(url, pixels: pixels)
        }
        images[cacheKey] = .some(image)
        return image
    }

    /// The first few kilobytes of a text, Markdown or JSON file.
    static func text(for entry: ArchiveEntry) -> String? {
        guard entry.kind == .text || entry.kind == .data, let url = url(for: entry) else { return nil }
        return PreviewService.textPrefix(url, bytes: 4_000)
    }

    /// The font itself, at `size` points.
    static func font(for entry: ArchiveEntry, size: CGFloat) -> CTFont? {
        guard entry.kind == .font, let url = url(for: entry) else { return nil }
        // Read once: views ask on every update, and a font file is parsed each time it's read.
        if fonts[url.path] == nil {
            fonts[url.path] = .some((CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])?.first)
        }
        guard let descriptor = fonts[url.path] ?? nil else { return nil }
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }

    // MARK: - Index

    private static let folder = Bundle.main.resourceURL?.appending(path: "Sample/Harbor Rebrand Handoff", directoryHint: .isDirectory)

    /// Where an entry's file sits when it isn't at the entry's own path.
    private static let renamed = ["Video/Logo Reveal.mov": "Video/Logo Reveal.jpg"]

    private static func key(_ entry: ArchiveEntry) -> String { "\(entry.size) \(entry.modified.timeIntervalSince1970)" }

    private static let keys = Set((SampleArchive.make().files + SampleArchive.oldExplorations).map { key($0) })

    private static let files: [String: String] = {
        guard let folder else { return [:] }
        var files: [String: String] = [:]
        for entry in SampleArchive.make().files { files[key(entry)] = renamed[entry.path] ?? entry.path }
        for entry in SampleArchive.oldExplorations { files[key(entry)] = "Earlier Rounds/Old Explorations/" + entry.path }
        return files.filter { FileManager.default.fileExists(atPath: folder.appending(path: $0.value).path) }
    }()

    private static let bySize = Dictionary((SampleArchive.make().files + SampleArchive.oldExplorations).compactMap { entry in
        files[key(entry)].map { (entry.size, (path: entry.path, file: $0)) }
    }, uniquingKeysWith: { first, _ in first })

    private static var images: [String: NSImage?] = [:]
    private static var fonts: [String: CTFontDescriptor?] = [:]

    private static func downsampled(_ url: URL, pixels: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: pixels,
                       kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return NSImage(cgImage: image, size: CGSize(width: CGFloat(image.width) / 2, height: CGFloat(image.height) / 2))
    }

    /// Drawn with Core Graphics: PDFKit doesn't belong in the middle of a view update.
    private static func firstPage(_ url: URL, pixels: Int) -> NSImage? {
        guard let page = CGPDFDocument(url as CFURL)?.page(at: 1) else { return nil }
        let box = page.getBoxRect(.mediaBox)
        let scale = CGFloat(pixels) / max(box.width, box.height)
        let width = Int(box.width * scale), height = Int(box.height * scale)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else { return nil }
        context.setFillColor(.white)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -box.minX, y: -box.minY)
        context.drawPDFPage(page)
        guard let image = context.makeImage() else { return nil }
        return NSImage(cgImage: image, size: CGSize(width: CGFloat(width) / 2, height: CGFloat(height) / 2))
    }
}
