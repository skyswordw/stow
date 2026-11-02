import AppKit
import SwiftUI
import Testing
@testable import Stow

/// White words on the accent and accent words on a dark panel both have to read (#104).
@Suite("Accent contrast")
struct AccentContrastTests {
    private typealias RGB = AccentText.RGB
    private let white = RGB(red: 1, green: 1, blue: 1)

    private func rgb(_ hex: Int) -> RGB {
        RGB(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    /// The asset's accent as macOS resolves it, whatever the Mac's own accent is set to.
    private func assetAccent(_ appearance: NSAppearance.Name) throws -> RGB {
        let color = try #require(NSColor(named: "AccentColor"))
        var result = RGB(red: 0, green: 0, blue: 0)
        try #require(NSAppearance(named: appearance)).performAsCurrentDrawingAppearance {
            let srgb = color.usingColorSpace(.sRGB)!
            result = RGB(red: srgb.redComponent, green: srgb.greenComponent, blue: srgb.blueComponent)
        }
        return result
    }

    @Test func whiteWordsReadOnTheDarkAccent() throws {
        #expect(AccentText.contrast(try assetAccent(.darkAqua), white) >= 4.5)
    }

    @Test func lightAccentIsUnchanged() throws {
        let light = try assetAccent(.aqua)
        #expect(abs(light.red - 0.851) < 0.002 && abs(light.green - 0.482) < 0.002 && abs(light.blue - 0.169) < 0.002)
    }

    @Test func deepAmberLiftsToReadOnADarkPanel() {
        let amber = rgb(0xB85E1C)
        #expect(AccentText.contrast(amber, AccentText.darkPanel) < 4.5)
        let lifted = AccentText.lifted(amber, toContrast: 4.5)
        #expect(AccentText.contrast(lifted, AccentText.darkPanel) >= 4.5)
        // Still amber: red leads, blue trails, and it hasn't washed out towards white.
        #expect(lifted.red > lifted.green && lifted.green > lifted.blue)
        #expect(lifted.blue < 0.3)
    }

    @Test func increaseContrastLiftsFurther() {
        let lifted = AccentText.lifted(rgb(0xA8551C), toContrast: 7)
        #expect(AccentText.contrast(lifted, AccentText.darkPanel) >= 7)
    }

    @Test func anAccentThatAlreadyReadsIsLeftAlone() {
        let green = rgb(0x30D158)
        #expect(AccentText.lifted(green, toContrast: 4.5) == green)
    }
}
