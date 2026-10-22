// Renders the generated files of the sample archive (Resources/Sample/Harbor Rebrand Handoff):
// the logo SVGs and PNG, the app screens, the brand guidelines PDF, the earlier-round sketches and
// the video poster. Inputs are the CC0 photos and OFL fonts already in that folder (see
// Resources/Sample/CREDITS.md). Every word, colour and shape here is our own.
//
//     swift scripts/make-sample-content.swift        (from the repository root)
//
// SF Symbols appear only as icons inside the mock iOS screens, which is what they're licensed for.
import AppKit
import CoreText
import SwiftUI

let root = URL(filePath: FileManager.default.currentDirectoryPath)
    .appending(path: "Resources/Sample/Harbor Rebrand Handoff", directoryHint: .isDirectory)
guard FileManager.default.fileExists(atPath: root.appending(path: "Fonts").path) else {
    print("Run from the repository root."); exit(1)
}
func file(_ path: String) -> URL { root.appending(path: path) }

for font in ["Atkinson Hyperlegible Regular", "Atkinson Hyperlegible Bold", "Instrument Serif Italic"] {
    CTFontManagerRegisterFontsForURL(file("Fonts/\(font).ttf") as CFURL, .process, nil)
}

// MARK: - Brand

func hex(_ value: UInt32, _ opacity: Double = 1) -> Color {
    Color(.sRGB, red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
          blue: Double(value & 0xFF) / 255, opacity: opacity)
}
func ui(_ size: CGFloat, bold: Bool = false) -> Font {
    .custom(bold ? "AtkinsonHyperlegible-Bold" : "AtkinsonHyperlegible-Regular", fixedSize: size)
}
func display(_ size: CGFloat) -> Font { .custom("InstrumentSerif-Italic", fixedSize: size) }

let navy900: UInt32 = 0x0E2133, navy800: UInt32 = 0x173049, navy600: UInt32 = 0x1E4867, navy400: UInt32 = 0x3B7F9C
let amber500: UInt32 = 0xE2802F, amber300: UInt32 = 0xF2A65A, amber100: UInt32 = 0xFFD48F
let sand50: UInt32 = 0xFFF6EA, sand200: UInt32 = 0xE9D7C0

struct Palette {
    let dark: Bool
    var background: Color { dark ? hex(0x0B1824) : hex(sand50) }
    var surface: Color { dark ? hex(0x13283B) : .white }
    var text: Color { dark ? hex(0xEEF2F5) : hex(navy900) }
    var secondary: Color { dark ? hex(0x9DB0C0) : hex(0x5B6B7A) }
    var accent: Color { dark ? hex(amber300) : hex(amber500) }
    var onAccent: Color { hex(navy900) }
    var line: Color { dark ? .white.opacity(0.09) : hex(navy900, 0.09) }
    var link: Color { dark ? hex(0x7FB8D0) : hex(navy400) }
    var onTime: Color { dark ? hex(0x5BC08F) : hex(0x2F7D5B) }
    var late: Color { dark ? hex(0xF0905A) : hex(0xB5541C) }
}

/// The mark on a 256-unit artboard: a lighthouse, its beam (one shape) and a wave. The SVG files
/// and every drawing of the mark below use these numbers.
enum Mark {
    static let beam = [CGPoint(x: 36, y: 52), CGPoint(x: 220, y: 102), CGPoint(x: 220, y: 52), CGPoint(x: 36, y: 102)]
    static let roof = [CGPoint(x: 108, y: 62), CGPoint(x: 128, y: 40), CGPoint(x: 148, y: 62)]
    static let lamp = CGRect(x: 115, y: 60, width: 26, height: 30)
    static let gallery = CGRect(x: 106, y: 88, width: 44, height: 11)
    static let tower = [CGPoint(x: 117, y: 99), CGPoint(x: 139, y: 99), CGPoint(x: 148, y: 206), CGPoint(x: 108, y: 206)]
    static func band(_ top: CGFloat, _ bottom: CGFloat) -> [CGPoint] {
        func left(_ y: CGFloat) -> CGFloat { 117 - 9 * (y - 99) / 107 }
        return [CGPoint(x: left(top), y: top), CGPoint(x: 256 - left(top), y: top),
                CGPoint(x: 256 - left(bottom), y: bottom), CGPoint(x: left(bottom), y: bottom)]
    }
    static let bands = [band(126, 144), band(164, 182)]
    /// M40 222 Q62 210 84 222 T128 222 T172 222 T216 222, with the smooth segments written out.
    static let wave: [(control: CGPoint, end: CGPoint)] = [
        (CGPoint(x: 62, y: 210), CGPoint(x: 84, y: 222)), (CGPoint(x: 106, y: 234), CGPoint(x: 128, y: 222)),
        (CGPoint(x: 150, y: 210), CGPoint(x: 172, y: 222)), (CGPoint(x: 194, y: 234), CGPoint(x: 216, y: 222)),
    ]

    static func svg(ink: String, accent: String) -> String {
        func poly(_ points: [CGPoint]) -> String { "M" + points.map { "\(n($0.x)) \(n($0.y))" }.joined(separator: " L") + " Z" }
        func rect(_ r: CGRect, _ radius: CGFloat) -> String {
            "x=\"\(n(r.minX))\" y=\"\(n(r.minY))\" width=\"\(n(r.width))\" height=\"\(n(r.height))\" rx=\"\(n(radius))\""
        }
        let wavePath = "M40 222 " + wave.map { "Q\(n($0.control.x)) \(n($0.control.y)) \(n($0.end.x)) \(n($0.end.y))" }.joined(separator: " ")
        return """
          <path d="\(poly(beam))" fill="\(accent)" fill-opacity=".38"/>
          <path d="\(poly(tower))" fill="\(ink)"/>
          <path d="\(bands.map(poly).joined(separator: " "))" fill="\(accent)"/>
          <rect \(rect(gallery, 3)) fill="\(ink)"/>
          <rect \(rect(lamp, 4)) fill="\(accent)"/>
          <path d="\(poly(roof))" fill="\(ink)"/>
          <path d="\(wavePath)" fill="none" stroke="\(ink)" stroke-width="11" stroke-linecap="round"/>
        """
    }
}

func n(_ value: CGFloat) -> String {
    let text = String(format: "%.1f", value)
    return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
}

struct MarkView: View {
    var ink = hex(navy800)
    var accent = hex(amber500)

    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 256, y: size.height / 256)
            func poly(_ points: [CGPoint]) -> Path { Path { $0.addLines(points); $0.closeSubpath() } }
            context.fill(poly(Mark.beam), with: .color(accent.opacity(0.38)))
            context.fill(poly(Mark.tower), with: .color(ink))
            for band in Mark.bands { context.fill(poly(band), with: .color(accent)) }
            context.fill(Path(roundedRect: Mark.gallery, cornerRadius: 3), with: .color(ink))
            context.fill(Path(roundedRect: Mark.lamp, cornerRadius: 4), with: .color(accent))
            context.fill(poly(Mark.roof), with: .color(ink))
            var wave = Path()
            wave.move(to: CGPoint(x: 40, y: 222))
            for segment in Mark.wave { wave.addQuadCurve(to: segment.end, control: segment.control) }
            context.stroke(wave, with: .color(ink), style: StrokeStyle(lineWidth: 11, lineCap: .round))
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// The wordmark: the mark, then "Harbor" in Instrument Serif Italic.
struct Wordmark: View {
    var height: CGFloat
    var ink = hex(navy800)
    var accent = hex(amber500)

    var body: some View {
        HStack(alignment: .center, spacing: height * 0.12) {
            MarkView(ink: ink, accent: accent).frame(width: height, height: height)
            Text("Harbor").font(display(height * 0.92)).foregroundStyle(ink).offset(y: -height * 0.04)
        }
    }
}

// MARK: - Output

@MainActor func render(_ view: some View, size: CGSize, scale: CGFloat) -> CGImage {
    let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
    renderer.scale = scale
    return renderer.cgImage!
}

@MainActor func writePNG(_ view: some View, size: CGSize, scale: CGFloat, to path: String) {
    let data = NSBitmapImageRep(cgImage: render(view, size: size, scale: scale)).representation(using: .png, properties: [:])!
    try! data.write(to: file(path))
    print("\(path)  \(data.count / 1024) kB")
}

@MainActor func writeJPEG(_ view: some View, size: CGSize, scale: CGFloat, quality: Double, to path: String) {
    let data = NSBitmapImageRep(cgImage: render(view, size: size, scale: scale))
        .representation(using: .jpeg, properties: [.compressionFactor: quality])!
    try! data.write(to: file(path))
    print("\(path)  \(data.count / 1024) kB")
}

@MainActor func writePDF(_ pages: [AnyView], size: CGSize, title: String, to path: String) {
    var box = CGRect(origin: .zero, size: size)
    let info = [kCGPDFContextTitle: title, kCGPDFContextAuthor: "Harbor Design", kCGPDFContextCreator: "Harbor"] as CFDictionary
    let context = CGContext(file(path) as CFURL, mediaBox: &box, info)!
    for page in pages {
        ImageRenderer(content: page.frame(width: size.width, height: size.height)).render { _, draw in
            context.beginPDFPage(nil)
            draw(context)
            context.endPDFPage()
        }
    }
    context.closePDF()
    print("\(path)  \((try! Data(contentsOf: file(path))).count / 1024) kB")
}

func writeText(_ text: String, to path: String) {
    try! text.write(to: file(path), atomically: true, encoding: .utf8)
    print("\(path)  \(text.utf8.count / 1024) kB")
}

/// A photo from Photos/, at most `pixels` on its long side. JPEG-backed, so a PDF embeds it
/// compressed instead of as raw pixels.
func photo(_ name: String, pixels: Int = 1440) -> NSImage { jpeg(file("Photos/\(name)"), pixels: pixels) }

func jpeg(_ url: URL, pixels: Int, quality: Double = 0.72) -> NSImage {
    let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
    let options = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: pixels,
                   kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary
    let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, options)!
    let data = NSBitmapImageRep(cgImage: decoded).representation(using: .jpeg, properties: [.compressionFactor: quality])!
    let image = CGImage(jpegDataProviderSource: CGDataProvider(data: data as CFData)!, decode: nil,
                        shouldInterpolate: true, intent: .defaultIntent)!
    return NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height))
}

func fill(_ image: NSImage) -> some View {
    Color.clear.overlay { Image(nsImage: image).resizable().aspectRatio(contentMode: .fill) }.clipped()
}

/// Glyph outlines as SVG path data, so the SVG files don't depend on the font being installed.
func outlines(_ string: String, font name: String, size: CGFloat, tracking: CGFloat = 0, x: CGFloat, baseline: CGFloat) -> (path: String, width: CGFloat) {
    let font = CTFontCreateWithName(name as CFString, size, nil)
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): font, .kern: tracking,
    ]))
    var d = ""
    for run in CTLineGetGlyphRuns(line) as! [CTRun] {
        let count = CTRunGetGlyphCount(run)
        var glyphs = [CGGlyph](repeating: 0, count: count), positions = [CGPoint](repeating: .zero, count: count)
        CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
        CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
        for index in 0..<count {
            var transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: x + positions[index].x, ty: baseline)
            guard let glyph = CTFontCreatePathForGlyph(font, glyphs[index], &transform) else { continue }
            glyph.applyWithBlock { element in
                let p = element.pointee.points
                switch element.pointee.type {
                case .moveToPoint: d += "M\(n(p[0].x)) \(n(p[0].y))"
                case .addLineToPoint: d += "L\(n(p[0].x)) \(n(p[0].y))"
                case .addQuadCurveToPoint: d += "Q\(n(p[0].x)) \(n(p[0].y)) \(n(p[1].x)) \(n(p[1].y))"
                case .addCurveToPoint: d += "C\(n(p[0].x)) \(n(p[0].y)) \(n(p[1].x)) \(n(p[1].y)) \(n(p[2].x)) \(n(p[2].y))"
                case .closeSubpath: d += "Z"
                @unknown default: break
                }
            }
        }
    }
    return (d, CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)))
}

// MARK: - Logo files

func logoFiles() {
    writeText("""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" width="256" height="256">
      <title>Harbor mark</title>
    \(Mark.svg(ink: "#173049", accent: "#E2802F"))
    </svg>

    """, to: "Logo/Harbor Mark.svg")

    // Mark 120 high, a 16-unit gap, then the name; the cap height sits inside the mark's tower.
    let text = outlines("Harbor", font: "InstrumentSerif-Italic", size: 116, x: 138, baseline: 98)
    let width = Int(138 + text.width + 8)
    writeText("""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \(width) 120" width="\(width * 2)" height="240">
      <title>Harbor wordmark</title>
      <g transform="scale(0.46875)">
    \(Mark.svg(ink: "#173049", accent: "#E2802F"))
      </g>
      <path d="\(text.path)" fill="#173049"/>
    </svg>

    """, to: "Logo/Harbor Wordmark.svg")

    let draft = outlines("HARBOR", font: "AtkinsonHyperlegible-Bold", size: 88, tracking: 16, x: 12, baseline: 96)
    let draftWidth = Int(draft.width + 12)
    writeText("""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \(draftWidth) 120" width="\(draftWidth * 2)" height="240">
      <title>Harbor wordmark, draft B (round 2)</title>
      <path d="\(draft.path)" fill="#1E4867"/>
      <rect x="12" y="106" width="\(draftWidth - 28)" height="5" fill="#E2802F"/>
    </svg>

    """, to: "Earlier Rounds/Old Explorations/Round 2/Wordmark Draft.svg")
}

@MainActor func logoRenders() {
    writePNG(MarkView(), size: CGSize(width: 256, height: 256), scale: 2, to: "Logo/Harbor Mark@2x.png")
    writeJPEG(ZStack {
        LinearGradient(colors: [hex(navy600), hex(navy900)], startPoint: .top, endPoint: .bottom)
        Wordmark(height: 150, ink: hex(sand50), accent: hex(amber300))
    }, size: CGSize(width: 1280, height: 720), scale: 1, quality: 0.8, to: "Video/Logo Reveal.jpg")
}

// MARK: - Screens

struct StatusBar: View {
    let color: Color
    var body: some View {
        HStack {
            Text("9:41").font(ui(16, bold: true))
            Spacer()
            HStack(spacing: 5) {
                Image(systemName: "cellularbars")
                Image(systemName: "wifi")
                Image(systemName: "battery.100")
            }
            .font(.system(size: 14, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 30)
        .frame(height: 54)
    }
}

struct TabBar: View {
    let palette: Palette
    let selected: Int
    var body: some View {
        let items = [("ferry.fill", "Departures"), ("ticket.fill", "Tickets"), ("map.fill", "Map"), ("person.crop.circle", "You")]
        VStack(spacing: 0) {
            Rectangle().fill(palette.line).frame(height: 1)
            HStack {
                ForEach(items.indices, id: \.self) { index in
                    VStack(spacing: 4) {
                        Image(systemName: items[index].0).font(.system(size: 20, weight: .medium))
                        Text(items[index].1).font(ui(11, bold: index == selected))
                    }
                    .foregroundStyle(index == selected ? palette.accent : palette.secondary)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 9)
            Spacer()
            Capsule().fill(palette.text).frame(width: 134, height: 5).padding(.bottom, 8)
        }
        .frame(height: 86)
        .background(palette.surface)
    }
}

struct Departure: View {
    let palette: Palette
    let time: String, place: String, detail: String, status: String
    var late = false
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(time).font(ui(19, bold: true)).monospacedDigit().frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(place).font(ui(17, bold: true))
                Text(detail).font(ui(14)).foregroundStyle(palette.secondary)
            }
            Spacer()
            Text(status).font(ui(14, bold: true)).foregroundStyle(late ? palette.late : palette.onTime)
        }
        .padding(.vertical, 12)
    }
}

func homeScreen(_ palette: Palette, hero: NSImage) -> some View {
    VStack(alignment: .leading, spacing: 0) {
        StatusBar(color: palette.text)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                MarkView(ink: palette.text, accent: palette.accent).frame(width: 34, height: 34)
                Spacer()
                Text("JL").font(ui(14, bold: true)).foregroundStyle(palette.onAccent)
                    .frame(width: 36, height: 36).background(hex(sand200), in: .circle)
            }
            Text("Good morning, Jordan").font(ui(15)).foregroundStyle(palette.secondary).padding(.top, 14)
            Text("Where to today?").font(display(40)).padding(.top, 2)
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(palette.secondary)
                Text("From North Quay").font(ui(16))
                Spacer()
                Image(systemName: "arrow.up.arrow.down").foregroundStyle(palette.link)
            }
            .padding(14)
            .background(palette.surface, in: .rect(cornerRadius: 12))
            .padding(.top, 14)
            ZStack(alignment: .bottomLeading) {
                fill(hero)
                LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 4) {
                    Text("NEXT SAILING").font(ui(11, bold: true)).tracking(1.2).opacity(0.85)
                    Text("7:40  Lantern Point").font(ui(23, bold: true)).monospacedDigit()
                    Text("Pier 2 · 25 min · On time").font(ui(14))
                }
                .foregroundStyle(.white)
                .padding(16)
            }
            .frame(height: 190)
            .clipShape(.rect(cornerRadius: 16))
            .padding(.top, 18)
            Text("Departures").font(ui(19, bold: true)).padding(.top, 20)
            VStack(spacing: 0) {
                Departure(palette: palette, time: "7:55", place: "Gull Island", detail: "Water taxi · 12 min", status: "On time")
                Rectangle().fill(palette.line).frame(height: 1)
                Departure(palette: palette, time: "8:10", place: "Old Customs Pier", detail: "Ferry · 18 min", status: "3 min late", late: true)
                Rectangle().fill(palette.line).frame(height: 1)
                Departure(palette: palette, time: "8:25", place: "Lantern Point", detail: "Ferry · 25 min", status: "On time")
            }
        }
        .padding(.horizontal, 20)
        Spacer(minLength: 0)
        TabBar(palette: palette, selected: 0)
    }
    .foregroundStyle(palette.text)
    .background(palette.background)
}

func checkoutScreen(_ palette: Palette) -> some View {
    func row(_ label: String, _ value: String, bold: Bool = false) -> some View {
        HStack {
            Text(label).font(ui(16, bold: bold))
            Spacer()
            Text(value).font(ui(16, bold: bold)).monospacedDigit()
        }
    }
    func field(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(ui(11, bold: true)).tracking(1).foregroundStyle(palette.secondary)
            Text(value).font(ui(16, bold: true)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    return VStack(alignment: .leading, spacing: 0) {
        StatusBar(color: palette.text)
        HStack {
            Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).foregroundStyle(palette.link)
            Spacer()
            Text("Checkout").font(ui(17, bold: true))
            Spacer()
            Color.clear.frame(width: 18)
        }
        .padding(.horizontal, 20)
        .frame(height: 44)
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("FROM").font(ui(11, bold: true)).tracking(1).foregroundStyle(palette.secondary)
                        Text("North Quay").font(display(30))
                    }
                    Spacer()
                    Image(systemName: "arrow.right").font(.system(size: 18, weight: .semibold)).foregroundStyle(palette.accent)
                        .padding(.bottom, 8)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("TO").font(ui(11, bold: true)).tracking(1).foregroundStyle(palette.secondary)
                        Text("Lantern Point").font(display(30))
                    }
                }
                Line().stroke(palette.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 4])).frame(height: 1)
                HStack { field("DATE", "Thu 8 Oct"); field("DEPARTS", "7:40"); field("PIER", "2") }
                HStack { field("PASSENGERS", "1 adult"); field("EXTRAS", "1 bike"); field("BOAT", "Tern") }
            }
            .padding(18)
            .background(palette.surface, in: .rect(cornerRadius: 16))
            .padding(.top, 10)
            VStack(spacing: 12) {
                row("Adult single", "$4.50")
                row("Bike", "$1.00")
                Rectangle().fill(palette.line).frame(height: 1)
                row("Total", "$5.50", bold: true)
            }
            .padding(.top, 26)
            Text("PAY WITH").font(ui(11, bold: true)).tracking(1).foregroundStyle(palette.secondary).padding(.top, 28)
            HStack(spacing: 12) {
                Image(systemName: "wallet.pass.fill").font(.system(size: 20)).foregroundStyle(palette.accent)
                    .frame(width: 40, height: 40).background(palette.accent.opacity(0.15), in: .rect(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Harbor Wallet").font(ui(16, bold: true))
                    Text("$18.20 left").font(ui(14)).foregroundStyle(palette.secondary)
                }
                Spacer()
                Text("Change").font(ui(15, bold: true)).foregroundStyle(palette.link)
            }
            .padding(14)
            .background(palette.surface, in: .rect(cornerRadius: 14))
            .padding(.top, 8)
        }
        .padding(.horizontal, 20)
        Spacer(minLength: 0)
        VStack(spacing: 10) {
            Text("Pay $5.50").font(ui(18, bold: true)).foregroundStyle(palette.onAccent)
                .frame(maxWidth: .infinity, minHeight: 54).background(palette.accent, in: .rect(cornerRadius: 12))
            Text("You can get a refund until the boat leaves.").font(ui(13)).foregroundStyle(palette.secondary)
        }
        .padding(.horizontal, 20)
        Capsule().fill(palette.text).frame(width: 134, height: 5).frame(maxWidth: .infinity).padding(.top, 18).padding(.bottom, 8)
    }
    .foregroundStyle(palette.text)
    .background(palette.background)
}

struct Line: Shape {
    func path(in rect: CGRect) -> Path { Path { $0.move(to: CGPoint(x: 0, y: rect.midY)); $0.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)) } }
}

func onboardingScreen(_ palette: Palette, image: NSImage, page: Int, title: String, body: String) -> some View {
    VStack(alignment: .leading, spacing: 0) {
        ZStack(alignment: .top) {
            fill(image)
            LinearGradient(colors: [.black.opacity(0.35), .clear], startPoint: .top, endPoint: .init(x: 0.5, y: 0.3))
            StatusBar(color: .white)
        }
        .frame(height: 440)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule().fill(index == page ? palette.accent : palette.secondary.opacity(0.3))
                        .frame(width: index == page ? 22 : 7, height: 7)
                }
            }
            Text(title).font(display(38)).fixedSize(horizontal: false, vertical: true).padding(.top, 6)
            Text(body).font(ui(17)).foregroundStyle(palette.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack {
                Text(page == 2 ? "" : "Skip").font(ui(16, bold: true)).foregroundStyle(palette.link)
                Spacer()
                Text(page == 2 ? "Get started" : "Next").font(ui(17, bold: true)).foregroundStyle(palette.onAccent)
                    .padding(.horizontal, 26).frame(height: 50).background(palette.accent, in: .capsule)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        Capsule().fill(palette.text).frame(width: 134, height: 5).frame(maxWidth: .infinity).padding(.top, 22).padding(.bottom, 8)
    }
    .foregroundStyle(palette.text)
    .background(palette.background)
}

func settingsScreen(_ palette: Palette) -> some View {
    func toggle(_ on: Bool) -> some View {
        Capsule().fill(on ? palette.onTime : palette.secondary.opacity(0.3)).frame(width: 51, height: 31)
            .overlay(alignment: on ? .trailing : .leading) { Circle().fill(.white).padding(2).shadow(radius: 1, y: 1) }
    }
    func row(_ label: String, value: String? = nil, on: Bool? = nil) -> some View {
        HStack {
            Text(label).font(ui(16))
            Spacer()
            if let value { Text(value).font(ui(16)).foregroundStyle(palette.secondary) }
            if let on { toggle(on) } else { Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.secondary.opacity(0.6)) }
        }
        .frame(height: 46)
    }
    func section(_ title: String, _ rows: [AnyView]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(ui(12, bold: true)).tracking(1).foregroundStyle(palette.secondary).padding(.leading, 16)
            VStack(spacing: 0) {
                ForEach(rows.indices, id: \.self) { index in
                    rows[index]
                    if index < rows.count - 1 { Rectangle().fill(palette.line).frame(height: 1) }
                }
            }
            .padding(.horizontal, 16)
            .background(palette.surface, in: .rect(cornerRadius: 14))
        }
    }
    return VStack(alignment: .leading, spacing: 0) {
        StatusBar(color: palette.text)
        VStack(alignment: .leading, spacing: 22) {
            Text("Settings").font(display(40))
            HStack(spacing: 14) {
                Text("JL").font(ui(18, bold: true)).foregroundStyle(palette.onAccent)
                    .frame(width: 52, height: 52).background(hex(sand200), in: .circle)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Jordan Lee").font(ui(18, bold: true))
                    Text("Harbor Wallet · $18.20").font(ui(14)).foregroundStyle(palette.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.secondary.opacity(0.6))
            }
            .padding(14)
            .background(palette.surface, in: .rect(cornerRadius: 14))
            section("NOTIFICATIONS", [AnyView(row("Delays and cancellations", on: true)),
                                      AnyView(row("Boarding reminder", value: "15 min before")),
                                      AnyView(row("When a boat is full", on: false))])
            section("TRAVEL", [AnyView(row("Home pier", value: "North Quay")),
                               AnyView(row("I travel with a bike", on: true))])
            section("APP", [AnyView(row("Appearance", value: "Automatic")),
                            AnyView(row("About Harbor", value: "3.0 (412)"))])
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        Spacer(minLength: 0)
        TabBar(palette: palette, selected: 3)
    }
    .foregroundStyle(palette.text)
    .background(palette.background)
}

@MainActor func screens() {
    let size = CGSize(width: 390, height: 844), scale: CGFloat = 1
    let light = Palette(dark: false), dark = Palette(dark: true)
    let pier = photo("Pier at Dawn.jpg", pixels: 900)
    writePNG(homeScreen(light, hero: pier), size: size, scale: scale, to: "Screens/Home.png")
    writePNG(homeScreen(dark, hero: pier), size: size, scale: scale, to: "Screens/Dark/Home.png")
    writePNG(checkoutScreen(light), size: size, scale: scale, to: "Screens/Checkout.png")
    writePNG(checkoutScreen(dark), size: size, scale: scale, to: "Screens/Dark/Checkout.png")
    let pages = [
        ("Lighthouse.jpg", "Every crossing in one place", "Ferries and water taxis across the bay, with live times from every pier."),
        ("Old Jetty.heic", "Tickets that live in your pocket", "Buy before you board and show your phone at the gate. No paper, no queue."),
        ("Harbor at Night.jpg", "Know before you go", "We’ll tell you when a boat is late, full or cancelled, before you leave home."),
    ]
    for (index, page) in pages.enumerated() {
        writePNG(onboardingScreen(light, image: photo(page.0, pixels: 900), page: index, title: page.1, body: page.2),
                 size: size, scale: scale, to: "Screens/Onboarding \(index + 1).png")
    }
    writePNG(settingsScreen(light), size: size, scale: scale, to: "Screens/Settings.png")
}

// MARK: - Brand guidelines

struct GuidePage<Content: View>: View {
    let number: Int
    var dark = false
    @ViewBuilder let content: Content
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            (dark ? hex(navy900) : hex(sand50))
            content
            HStack {
                Text("Harbor Brand Guidelines · 3.0")
                Spacer()
                Text("\(number)").monospacedDigit()
            }
            .font(ui(11))
            .foregroundStyle(dark ? hex(sand50, 0.6) : hex(navy900, 0.5))
            .padding(.horizontal, 56)
            .padding(.bottom, 28)
        }
        .foregroundStyle(dark ? hex(sand50) : hex(navy900))
    }
}

func heading(_ kicker: String, _ title: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(kicker.uppercased()).font(ui(12, bold: true)).tracking(1.6).foregroundStyle(hex(amber500))
        Text(title).font(display(54))
    }
}

func swatch(_ color: UInt32, _ name: String, _ token: String, light: Bool = false) -> some View {
    VStack(alignment: .leading, spacing: 0) {
        hex(color).frame(height: 96)
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(ui(14, bold: true))
            Text(String(format: "#%06X", color)).font(ui(12)).monospacedDigit()
            Text(token).font(ui(11)).foregroundStyle(hex(navy900, 0.55))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white)
    }
    .clipShape(.rect(cornerRadius: 10))
    .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(hex(navy900, light ? 0.15 : 0.06)) }
}

@MainActor func guidelines() {
    let size = CGSize(width: 1024, height: 768)
    let cover = GuidePage(number: 1, dark: true) {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Wordmark(height: 64, ink: hex(sand50), accent: hex(amber300))
                Spacer()
                Text("Brand Guidelines").font(display(72)).foregroundStyle(hex(amber300))
                Text("Version 3.0 · October 2026").font(ui(18)).opacity(0.8).padding(.top, 6)
                Text("For the app, the piers and everything in between.").font(ui(18)).opacity(0.8).padding(.top, 2)
                Spacer().frame(height: 120)
            }
            .padding(56)
            .frame(width: 520, alignment: .leading)
            fill(photo("Lighthouse.jpg", pixels: 1000))
        }
    }
    let voice = GuidePage(number: 2) {
        VStack(alignment: .leading, spacing: 0) {
            heading("Who we are", "Calm, clear, on time.")
            Text("Harbor gets people across the bay. Ferries, water taxis, the 6:10 to Gull Island. Everything we make should feel like a good crew: it knows the water, says what’s happening and doesn’t make a fuss.")
                .font(ui(19)).lineSpacing(5).frame(width: 720, alignment: .leading).padding(.top, 22)
            HStack(alignment: .top, spacing: 36) {
                ForEach([("Say when, not maybe", "Departures, delays and prices come first. Everything else can wait."),
                         ("Talk like the crew", "Short sentences and plain words. No exclamation marks, no jokes about the weather."),
                         ("Show the real bay", "Our own photos of our own piers. Never stock skylines.")], id: \.0) { item in
                    VStack(alignment: .leading, spacing: 10) {
                        Rectangle().fill(hex(amber500)).frame(width: 36, height: 4)
                        Text(item.0).font(ui(20, bold: true))
                        Text(item.1).font(ui(16)).lineSpacing(3).foregroundStyle(hex(navy900, 0.75))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 56)
        }
        .padding(56)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    let logo = GuidePage(number: 3) {
        VStack(alignment: .leading, spacing: 0) {
            heading("Logo", "The mark and the name")
            HStack(spacing: 24) {
                ZStack {
                    Color.white
                    Rectangle().strokeBorder(hex(amber500, 0.8), style: StrokeStyle(lineWidth: 1, dash: [5, 4])).padding(38)
                    MarkView().padding(70)
                }
                .frame(width: 300, height: 300)
                .clipShape(.rect(cornerRadius: 14))
                VStack(spacing: 24) {
                    ZStack { hex(navy800); Wordmark(height: 72, ink: hex(sand50), accent: hex(amber300)) }
                        .frame(height: 138).clipShape(.rect(cornerRadius: 14))
                    ZStack { Color.white; Wordmark(height: 72) }
                        .frame(height: 138).clipShape(.rect(cornerRadius: 14))
                }
            }
            .padding(.top, 28)
            HStack(alignment: .top, spacing: 36) {
                ForEach([("Clear space", "Keep a gap the height of the lamp room on every side."),
                         ("Smallest sizes", "Mark: 24 pt tall. Wordmark: 72 pt wide. Smaller than that, write “Harbor” in the headline face."),
                         ("Don’t", "Recolour the beam, put the mark on a busy photo, or stretch it.")], id: \.0) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.0).font(ui(16, bold: true))
                        Text(item.1).font(ui(14)).lineSpacing(2).foregroundStyle(hex(navy900, 0.75))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 30)
        }
        .padding(56)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    let colour = GuidePage(number: 4) {
        VStack(alignment: .leading, spacing: 0) {
            heading("Colour and type", "Navy does the work. Amber points.")
            HStack(spacing: 14) {
                swatch(navy900, "Navy 900", "navy.900")
                swatch(navy800, "Navy 800", "navy.800")
                swatch(navy400, "Navy 400", "navy.400")
                swatch(amber500, "Amber 500", "amber.500")
                swatch(amber100, "Amber 100", "amber.100")
                swatch(sand50, "Sand 50", "sand.50", light: true)
            }
            .padding(.top, 26)
            HStack(alignment: .top, spacing: 40) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Headlines").font(ui(13, bold: true)).foregroundStyle(hex(navy900, 0.6))
                    Text("Where to today?").font(display(56))
                    Text("Instrument Serif Italic · one headline per screen").font(ui(14)).foregroundStyle(hex(navy900, 0.7))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Everything else").font(ui(13, bold: true)).foregroundStyle(hex(navy900, 0.6))
                    Text("7:40  Lantern Point").font(ui(30, bold: true)).monospacedDigit().padding(.top, 10)
                    Text("Pier 2 · 25 min · On time").font(ui(22))
                    Text("Atkinson Hyperlegible · tabular figures for times").font(ui(14)).foregroundStyle(hex(navy900, 0.7)).padding(.top, 8)
                }
            }
            .padding(.top, 40)
        }
        .padding(56)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    let shot = { (path: String) -> NSImage in jpeg(file(path), pixels: 700, quality: 0.8) }
    let darkMode = GuidePage(number: 5, dark: true) {
        HStack(alignment: .top, spacing: 40) {
            VStack(alignment: .leading, spacing: 0) {
                heading("Dark mode", "Night crossing")
                Text("Dark mode isn’t light mode inverted. Backgrounds go to deep navy, not black, and amber gets lighter so it still reads at night on deck.")
                    .font(ui(18)).lineSpacing(5).padding(.top, 22)
                VStack(alignment: .leading, spacing: 10) {
                    Text("•  Photos stay as they are. Never dim them.")
                    Text("•  Surfaces are one step lighter than the background.")
                    Text("•  Status colours lift to keep contrast.")
                }
                .font(ui(16)).opacity(0.85).padding(.top, 26)
            }
            .frame(width: 380)
            HStack(spacing: 22) {
                Image(nsImage: shot("Screens/Home.png")).resizable().aspectRatio(contentMode: .fit).clipShape(.rect(cornerRadius: 22))
                Image(nsImage: shot("Screens/Dark/Home.png")).resizable().aspectRatio(contentMode: .fit).clipShape(.rect(cornerRadius: 22))
            }
            .frame(height: 600)
        }
        .padding(56)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    let photography = GuidePage(number: 6) {
        VStack(alignment: .leading, spacing: 0) {
            heading("Photography", "Our water, our light")
            Grid(horizontalSpacing: 14, verticalSpacing: 14) {
                GridRow {
                    fill(photo("Pier at Dawn.jpg", pixels: 800)).gridCellColumns(2)
                    fill(photo("Rope Detail.jpg", pixels: 500))
                }
                GridRow {
                    fill(photo("Old Jetty.heic", pixels: 500))
                    fill(photo("Harbor at Night.jpg", pixels: 500))
                    fill(photo("Lighthouse.jpg", pixels: 500))
                }
            }
            .clipShape(.rect(cornerRadius: 12))
            .frame(height: 430)
            .padding(.top, 24)
            Text("Early light, late light, real boats. Crop to 3:2 for cards and 4:5 for onboarding; keep the horizon in the top third.")
                .font(ui(15)).foregroundStyle(hex(navy900, 0.75)).padding(.top, 16)
        }
        .padding(56)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    writePDF([AnyView(cover), AnyView(voice), AnyView(logo), AnyView(colour), AnyView(darkMode), AnyView(photography)],
             size: size, title: "Harbor Brand Guidelines 3.0", to: "Specs/Brand Guidelines.pdf")
}

// MARK: - Earlier rounds

@MainActor func earlierRounds() {
    let ideas = ZStack(alignment: .topLeading) {
        hex(0xFAF8F4)
        VStack(alignment: .leading, spacing: 0) {
            Text("Wordmark — round 1").font(ui(30, bold: true))
            Text("Four directions, 12 June 2026. Votes in the notes.").font(ui(16)).foregroundStyle(hex(navy900, 0.6)).padding(.top, 4)
            Grid(horizontalSpacing: 20, verticalSpacing: 20) {
                GridRow {
                    idea("A", Text("harbor").font(ui(84, bold: true)), "Lowercase, bold. Friendly, but a bit like a bank.")
                    idea("B", Text("Harbor").font(ui(84)), "Regular weight. Clear, a little plain.")
                }
                GridRow {
                    idea("C", Text("Harbor").font(display(100)), "Serif italic. Feels like the sea. Most votes.")
                    idea("D", Text("HARBOR").font(ui(64, bold: true)).tracking(10), "All caps. Too loud next to times.")
                }
            }
            .padding(.top, 28)
        }
        .padding(48)
        .foregroundStyle(hex(navy900))
    }
    writePDF([AnyView(ideas)], size: CGSize(width: 1024, height: 768), title: "Wordmark Ideas — round 1",
             to: "Earlier Rounds/Old Explorations/Round 1/Wordmark Ideas.pdf")

    let pencil = hex(0x3D4650)
    let sketches = ZStack {
        hex(0xF6F1E7)
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                sketch(1) {
                    Canvas { context, size in
                        context.scaleBy(x: size.width / 256, y: size.height / 256)
                        var lines = Path()
                        lines.addLines([CGPoint(x: 117, y: 99), CGPoint(x: 108, y: 206), CGPoint(x: 148, y: 206), CGPoint(x: 139, y: 99)])
                        lines.addRect(Mark.gallery)
                        lines.addRect(Mark.lamp)
                        lines.addLines(Mark.roof)
                        for y in [70, 80] { lines.move(to: CGPoint(x: 112, y: y)); lines.addLine(to: CGPoint(x: 30, y: y - 26)) }
                        for y in [70, 80] { lines.move(to: CGPoint(x: 144, y: y)); lines.addLine(to: CGPoint(x: 226, y: y - 26)) }
                        lines.move(to: CGPoint(x: 40, y: 222))
                        for segment in Mark.wave { lines.addQuadCurve(to: segment.end, control: segment.control) }
                        context.stroke(lines, with: .color(pencil), style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                    }
                }
                sketch(2) {
                    ZStack {
                        Circle().stroke(pencil, lineWidth: 3.5).padding(20)
                        MarkView(ink: pencil, accent: pencil.opacity(0.7)).padding(56)
                    }
                }
                sketch(3) {
                    ZStack {
                        Text("H").font(display(190)).foregroundStyle(pencil)
                        Capsule().fill(hex(amber500)).frame(width: 170, height: 7).rotationEffect(.degrees(-12)).offset(y: -24)
                    }
                }
            }
            GridRow {
                sketch(4) {
                    Canvas { context, size in
                        context.scaleBy(x: size.width / 256, y: size.height / 256)
                        context.stroke(Path(ellipseIn: CGRect(x: 104, y: 50, width: 48, height: 48)), with: .color(pencil), lineWidth: 3.5)
                        for offset in [0.0, 26.0] {
                            var wave = Path()
                            wave.move(to: CGPoint(x: 40, y: 150 + offset))
                            for segment in Mark.wave {
                                wave.addQuadCurve(to: CGPoint(x: segment.end.x, y: segment.end.y - 72 + offset),
                                                  control: CGPoint(x: segment.control.x, y: segment.control.y - 72 + offset))
                            }
                            context.stroke(wave, with: .color(pencil), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                        }
                    }
                }
                sketch(5) { MarkView(ink: hex(navy800), accent: hex(amber500)).padding(24) }
                sketch(6) {
                    VStack(spacing: 10) {
                        MarkView(ink: pencil, accent: pencil.opacity(0.6)).frame(width: 90, height: 90)
                        Text("harbor").font(ui(44, bold: true)).foregroundStyle(pencil)
                    }
                }
            }
        }
        .padding(30)
    }
    writePNG(sketches, size: CGSize(width: 900, height: 600), scale: 1, to: "Earlier Rounds/Old Explorations/Round 2/Mark Sketches.png")
}

func idea(_ letter: String, _ sample: some View, _ note: String) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        Text(letter).font(ui(14, bold: true)).foregroundStyle(hex(amber500))
        sample.frame(maxWidth: .infinity, minHeight: 130)
        Text(note).font(ui(14)).foregroundStyle(hex(navy900, 0.65))
    }
    .padding(18)
    .background(.white, in: .rect(cornerRadius: 12))
}

func sketch(_ number: Int, @ViewBuilder _ content: () -> some View) -> some View {
    ZStack(alignment: .topLeading) {
        content().frame(maxWidth: .infinity, maxHeight: .infinity)
        Text("\(number)").font(display(30)).foregroundStyle(hex(0x3D4650, 0.7)).padding(14)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .overlay { Rectangle().strokeBorder(hex(0x3D4650, 0.12)) }
}

// MARK: - Run

MainActor.assumeIsolated {
    logoFiles()
    logoRenders()
    screens()
    guidelines()
    earlierRounds()
}
