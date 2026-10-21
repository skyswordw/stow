import AppKit
import AVFoundation
import CoreText
import ImageIO
import QuickLookThumbnailing

/// What a hover or inspector preview shows, read from the entry's real bytes.
enum RichPreview: @unchecked Sendable {
    case image(NSImage)
    case text(String, markdown: Bool)
    case table([[String]])
    case font(CTFont, name: String)
    case audio(artwork: NSImage?, title: String?, artist: String?, duration: Double?)
    case video(frame: NSImage?, duration: Double?)
    case thumbnail(NSImage)
    case unavailable(String)
}

/// Thumbnails and previews of a window's archive. Files come from its `PreviewCache`; nothing is
/// extracted until a view on screen asks, and requests arriving together share one engine trip.
final class PreviewService {
    /// Larger files only preview on request (Space, Open): thumbnails shouldn't fill the disk.
    static let thumbnailLimit: Int64 = 48 << 20
    static let hoverLimit: Int64 = 160 << 20

    let cache: PreviewCache
    /// The password that opened the archive, if it needed one. Set by the browser.
    var password: (Archive) -> String? = { _ in nil }

    private let thumbnails = NSCache<NSString, NSImage>()
    private var failed = Set<String>()
    private var batch: [ArchiveEntry] = []
    private var batchTask: Task<[String: URL], Never>?
    private var batchArchive: Archive.ID?

    init(cache: PreviewCache = PreviewCache()) {
        self.cache = cache
        thumbnails.countLimit = 2_000
    }

    /// Whether a tile should try for a real thumbnail rather than the type's icon.
    static func wantsThumbnail(_ entry: ArchiveEntry) -> Bool {
        guard !entry.isFolder, entry.size > 0, entry.size <= thumbnailLimit else { return false }
        switch entry.kind {
        case .image, .vector, .document, .video, .audio, .font, .text, .data: return true
        default: return false
        }
    }

    // MARK: - Thumbnails

    func cachedThumbnail(for entry: ArchiveEntry, in archive: Archive, side: CGFloat) -> NSImage? {
        thumbnailKey(entry, archive, side).flatMap { thumbnails.object(forKey: $0 as NSString) }
    }

    /// A Quick Look thumbnail at `side` points, or nil if the file has none. Call from a view's
    /// task: a cancelled request (scrolled away) stops before anything is extracted.
    func thumbnail(for entry: ArchiveEntry, in archive: Archive, side: CGFloat) async -> NSImage? {
        guard archive.source != nil, Self.wantsThumbnail(entry),
              let key = thumbnailKey(entry, archive, side) else { return nil }
        if let image = thumbnails.object(forKey: key as NSString) { return image }
        guard !failed.contains(key) else { return nil }
        // Let a fast scroll pass by before extracting anything.
        try? await Task.sleep(for: .milliseconds(60))
        guard !Task.isCancelled else { return nil }

        let url: URL?
        if let hit = cache.cachedFile(for: entry, in: archive) {
            url = hit
        } else {
            url = await batchedFile(for: entry, in: archive)
        }
        guard let url, !Task.isCancelled else { return nil }
        let image = await Self.quickLookThumbnail(of: url, side: side)
        if let image {
            thumbnails.setObject(image, forKey: key as NSString)
        } else {
            failed.insert(key)
        }
        return image
    }

    private func thumbnailKey(_ entry: ArchiveEntry, _ archive: Archive, _ side: CGFloat) -> String? {
        cache.key(for: entry, in: archive).map { "\($0)\n\(Int(side))" }
    }

    /// Requests from tiles appearing in the same moment ride in one extraction.
    private func batchedFile(for entry: ArchiveEntry, in archive: Archive) async -> URL? {
        if batchTask == nil || batchArchive != archive.id {
            batch = []
            batchArchive = archive.id
            let password = password(archive)
            batchTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(25))
                guard let self else { return [:] }
                let entries = batch
                batch = []
                batchTask = nil
                return (try? await cache.files(for: entries, in: archive, password: password)) ?? [:]
            }
        }
        batch.append(entry)
        return await batchTask?.value[entry.path]
    }

    @concurrent
    static func quickLookThumbnail(of url: URL, side: CGFloat, scale: CGFloat = 2) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: side, height: side),
                                                   scale: scale, representationTypes: .thumbnail)
        return try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
    }

    // MARK: - Files on request

    /// The entry on disk, extracting it if needed (Space, Open, nested archives).
    func file(for entry: ArchiveEntry, in archive: Archive,
              onProgress: (@Sendable (Double) -> Void)? = nil) async throws(EngineError) -> URL {
        try await cache.file(for: entry, in: archive, password: password(archive), onProgress: onProgress)
    }

    // MARK: - Rich previews

    func richPreview(for entry: ArchiveEntry, in archive: Archive) async -> RichPreview {
        guard archive.source != nil else { return .unavailable(String(localized: "Sample content")) }
        guard entry.size <= Self.hoverLimit else { return .unavailable(String(localized: "Too large to preview here — press Space")) }
        guard entry.size > 0 else { return .unavailable(String(localized: "Empty file")) }
        let url: URL
        do {
            url = try await file(for: entry, in: archive)
        } catch {
            return .unavailable(error.failure == .passwordRequired || error.failure == .wrongPassword
                                ? String(localized: "Locked — needs the archive’s password") : error.message)
        }
        guard !Task.isCancelled else { return .unavailable("") }
        return await Self.read(url, kind: entry.kind)
    }

    @concurrent
    static func read(_ url: URL, kind: EntryKind) async -> RichPreview {
        let ext = url.pathExtension.lowercased()
        switch kind {
        case .image:
            if let image = downsampled(url, maxPixels: 900) { return .image(image) }
        case .text where ext != "rtf", .data where ext != "plist":
            if ext == "csv" || ext == "tsv", let rows = table(url, tabs: ext == "tsv") { return .table(rows) }
            if let text = textPrefix(url) { return .text(text, markdown: ext == "md" || ext == "markdown") }
        case .font:
            if let font = font(url) { return font }
        case .audio:
            return await audio(url)
        case .video:
            return await video(url)
        default:
            break
        }
        if let image = await quickLookThumbnail(of: url, side: 420) { return .thumbnail(image) }
        return .unavailable(String(localized: "No preview for this kind of file"))
    }

    nonisolated private static func downsampled(_ url: URL, maxPixels: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: CGSize(width: CGFloat(image.width) / 2, height: CGFloat(image.height) / 2))
    }

    /// The first few kilobytes, as text — enough to fill a preview card.
    nonisolated static func textPrefix(_ url: URL, bytes: Int = 12_000) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: bytes), !data.isEmpty else { return nil }
        if data.prefix(2) == Data([0xFF, 0xFE]) || data.prefix(2) == Data([0xFE, 0xFF]) {
            return String(data: data, encoding: .utf16)
        }
        // Bytes 0–8 almost never appear in text: this is binary.
        if data.prefix(1024).contains(where: { $0 < 9 }) { return nil }
        // A cut in the middle of a UTF-8 sequence: drop the partial character.
        for trim in 0...3 {
            if let text = String(data: data.dropLast(trim), encoding: .utf8) { return text }
        }
        return String(data: data, encoding: .windowsCP1252)
    }

    nonisolated static func table(_ url: URL, tabs: Bool) -> [[String]]? {
        guard let text = textPrefix(url, bytes: 8_000) else { return nil }
        let lines = text.split(whereSeparator: \.isNewline).prefix(14)
        let separator: Character = tabs ? "\t" : (lines.first?.filter { $0 == ";" }.count ?? 0) > (lines.first?.filter { $0 == "," }.count ?? 0) ? ";" : ","
        let rows = lines.map { line -> [String] in
            var cells: [String] = [], cell = "", quoted = false
            for character in line {
                if character == "\"" { quoted.toggle() } else if character == separator, !quoted {
                    cells.append(cell); cell = ""
                } else { cell.append(character) }
            }
            cells.append(cell)
            return Array(cells.prefix(6)).map { $0.trimmingCharacters(in: .whitespaces) }
        }
        return rows.isEmpty ? nil : rows
    }

    nonisolated private static func font(_ url: URL) -> RichPreview? {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let descriptor = descriptors.first else { return nil }
        let font = CTFontCreateWithFontDescriptor(descriptor, 48, nil)
        return .font(font, name: CTFontCopyFullName(font) as String)
    }

    nonisolated private static func audio(_ url: URL) async -> RichPreview {
        let asset = AVURLAsset(url: url)
        let metadata = (try? await asset.load(.commonMetadata)) ?? []
        func string(_ key: AVMetadataKey) async -> String? {
            guard let item = metadata.first(where: { $0.commonKey == key }) else { return nil }
            return try? await item.load(.stringValue)
        }
        var artwork: NSImage?
        if let item = metadata.first(where: { $0.commonKey == .commonKeyArtwork }),
           let data = try? await item.load(.dataValue) {
            artwork = NSImage(data: data)
        }
        let duration = try? await asset.load(.duration).seconds
        return .audio(artwork: artwork, title: await string(.commonKeyTitle), artist: await string(.commonKeyArtist),
                      duration: duration.flatMap { $0.isFinite ? $0 : nil })
    }

    nonisolated private static func video(_ url: URL) async -> RichPreview {
        let asset = AVURLAsset(url: url)
        let duration = (try? await asset.load(.duration))?.seconds
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 900, height: 900)
        let time = CMTime(seconds: min(1, (duration ?? 0) / 3), preferredTimescale: 600)
        var frame: NSImage?
        if let image = try? await generator.image(at: time).image {
            frame = NSImage(cgImage: image, size: CGSize(width: CGFloat(image.width) / 2, height: CGFloat(image.height) / 2))
        }
        if frame == nil, let thumbnail = await quickLookThumbnail(of: url, side: 420) { frame = thumbnail }
        return .video(frame: frame, duration: duration.flatMap { $0.isFinite ? $0 : nil })
    }
}
