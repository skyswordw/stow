import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The system's own document icon for a type — exactly what Finder shows.
struct NativeIcon: View {
    let type: UTType

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(for: type))
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
    }
}

/// Stand-in for an image's real thumbnail until extraction-to-memory is wired up.
/// Deterministic per file name, from curated palettes so it never looks random.
struct PhotoArt: View {
    let seed: String

    var body: some View {
        var rng = SeededRandom(seed: seed)
        let palette = Self.palettes[Int(rng.next() % UInt64(Self.palettes.count))]
        let points: [SIMD2<Float>] = (0..<9).map { index in
            let x = Float(index % 3) / 2, y = Float(index / 3) / 2
            let interior = index == 4
            return interior ? SIMD2(0.3 + rng.unit() * 0.4, 0.3 + rng.unit() * 0.4) : SIMD2(x, y)
        }
        let colors = (0..<9).map { palette[($0 + Int(rng.next() % 3)) % palette.count] }
        return MeshGradient(width: 3, height: 3, points: points, colors: colors)
    }

    private static let palettes: [[Color]] = [
        [Color(hex: 0xF6C89F), Color(hex: 0xE58E73), Color(hex: 0x7A6C9E), Color(hex: 0x2F3F6B)], // dawn
        [Color(hex: 0xBFE3E0), Color(hex: 0x5EA9B8), Color(hex: 0x2B6F8F), Color(hex: 0x1C3A55)], // sea
        [Color(hex: 0x1B2340), Color(hex: 0x37406B), Color(hex: 0xE6B85C), Color(hex: 0x0E1324)], // night
        [Color(hex: 0xEFE3CF), Color(hex: 0xD8B98C), Color(hex: 0xA77B52), Color(hex: 0x5B4632)], // rope
        [Color(hex: 0xD9E7D0), Color(hex: 0x8DB38B), Color(hex: 0x4E7D63), Color(hex: 0x23443A)], // coast
    ]
}

/// Type specimen for fonts — shows the face instead of a generic icon.
struct FontSpecimen: View {
    let name: String
    var compact = false

    var body: some View {
        let lower = name.lowercased()
        let design: Font.Design = lower.contains("serif") && !lower.contains("sans") ? .serif : .default
        let weight: Font.Weight = lower.contains("bold") ? .bold : .regular
        VStack(spacing: Space.xs) {
            Text("Aa")
                .font(.system(size: compact ? 34 : 64, weight: weight, design: design))
                .italic(lower.contains("italic"))
            if !compact {
                Text("Pack my box with five dozen jugs")
                .font(.system(.caption, design: design, weight: weight))
                .italic(lower.contains("italic"))
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

/// A page with ruled lines — previews for text, data and documents.
struct PageArt: View {
    let seed: String
    var monospaced = false

    var body: some View {
        var rng = SeededRandom(seed: seed)
        let widths = (0..<11).map { _ in 0.45 + Double(rng.unit()) * 0.55 }
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 7) {
                Capsule().frame(width: proxy.size.width * 0.42, height: 7).opacity(0.55)
                    .padding(.bottom, 4)
                ForEach(widths.indices, id: \.self) { index in
                    Capsule()
                        .frame(width: (proxy.size.width - 36) * widths[index], height: monospaced ? 4 : 5)
                        .padding(.leading, monospaced && index % 3 != 0 ? 14 : 0)
                        .opacity(0.18)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .foregroundStyle(.primary)
        .background(.background)
    }
}

/// One entry point for every place an entry is drawn.
struct EntryThumbnail: View {
    enum Style { case row, tile, large }

    let entry: ArchiveEntry
    let style: Style

    var body: some View {
        switch (style, entry.kind) {
        case (.row, .image):
            PhotoArt(seed: entry.name)
                .clipShape(.rect(cornerRadius: 3))
                .padding(1)
        case (.row, _):
            NativeIcon(type: entry.contentType)
        case (.tile, .image), (.large, .image):
            PhotoArt(seed: entry.name)
                .clipShape(.rect(cornerRadius: style == .tile ? Radius.chip : Radius.card))
                .overlay {
                    RoundedRectangle(cornerRadius: style == .tile ? Radius.chip : Radius.card)
                        .strokeBorder(.primary.opacity(0.08))
                }
                .aspectRatio(4 / 3, contentMode: .fit)
        case (.large, .font):
            card { FontSpecimen(name: entry.name) }
        case (.tile, .font):
            FontSpecimen(name: entry.name, compact: true)
                .aspectRatio(4 / 3, contentMode: .fit)
                .clipShape(.rect(cornerRadius: Radius.chip))
                .overlay { RoundedRectangle(cornerRadius: Radius.chip).strokeBorder(.primary.opacity(0.1)) }
        case (.large, .text), (.large, .data):
            card { PageArt(seed: entry.name, monospaced: entry.kind == .data) }
        case (.large, .document):
            card { PageArt(seed: entry.name) }
        case (.large, .vector):
            card {
                ZStack {
                    Color(nsColor: .textBackgroundColor)
                    Image(systemName: "water.waves")
                        .font(.system(size: 54, weight: .semibold))
                        .foregroundStyle(.tint)
                }
            }
        case (.large, _):
            NativeIcon(type: entry.contentType)
                .frame(width: 112, height: 112)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case (.tile, _):
            NativeIcon(type: entry.contentType)
                .padding(4)
        }
    }

    private func card(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .aspectRatio(4 / 3, contentMode: .fit)
            .clipShape(.rect(cornerRadius: Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card).strokeBorder(.primary.opacity(0.1))
            }
    }
}

// MARK: - Helpers

/// SplitMix64 seeded from FNV-1a, so art is stable across launches (String.hashValue isn't).
struct SeededRandom {
    private var state: UInt64

    init(seed: String) {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in seed.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3 }
        state = hash
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> Float { Float(next() % 10_000) / 10_000 }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
