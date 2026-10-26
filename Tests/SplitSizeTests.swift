import Foundation
import Testing
@testable import Stow

@Suite("SplitSize")
struct SplitSizeTests {
    @Test func presetsIncludeNewMediaSizes() {
        #expect(SplitSize.allCases == [
            .none, .mb100, .mb500, .mb700, .gb1, .fat32
        ])
        #expect(SplitSize.mb500.rawValue == 500_000_000)
        #expect(SplitSize.gb1.rawValue == 1_000_000_000)
        #expect(SplitSize.mb500.phrase == "in 500 MB parts")
        #expect(SplitSize.gb1.phrase == "in 1 GB parts")
    }

    @Test func storedUnknownPositiveBecomesCustom() {
        let custom = SplitSize.stored(250_000_000)
        #expect(custom.isCustom)
        #expect(custom.rawValue == 250_000_000)
        #expect(custom.phrase == "in 250 MB parts")
        #expect(SplitSize.stored(0) == .none)
        #expect(SplitSize.stored(-10) == .none)
    }

    @Test func customValidationRejectsOutOfRange() {
        #expect(SplitSize.custom(0) == nil)
        #expect(SplitSize.custom(1_023) == nil)
        #expect(SplitSize.custom(1_024)?.rawValue == 1_024)
        #expect(SplitSize.custom(SplitSize.maximumCustomBytes + 1) == nil)
    }

    @Test func parseCustomAcceptsDecimalUnits() {
        #expect(SplitSize.parseCustom("250", unit: .megabyte)?.rawValue == 250_000_000)
        #expect(SplitSize.parseCustom("1.5", unit: .gigabyte)?.rawValue == 1_500_000_000)
        #expect(SplitSize.parseCustom("0", unit: .megabyte) == nil)
        #expect(SplitSize.parseCustom("abc", unit: .megabyte) == nil)
        #expect(SplitSize.parseCustom(" 2 ", unit: .gigabyte)?.rawValue == 2_000_000_000)
    }

    @Test func reportPartsUseCustomVolumeSize() {
        let files = [PackFile(path: "big.bin", size: 900_000_000)]
        var options = PackOptions()
        options.format = .zip
        options.level = .store
        options.split = SplitSize.stored(300_000_000)
        let report = Compatibility.report(for: files, options: options, password: "")
        #expect(report.parts == 3)
    }

    @Test func formatBytesUsesDecimalLabels() {
        #expect(SplitSize.formatBytes(250_000_000) == "250 MB")
        #expect(SplitSize.formatBytes(1_500_000_000) == "1.5 GB")
        #expect(SplitSize.formatBytes(1_000_000_000) == "1 GB")
    }
}
