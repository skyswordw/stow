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

    @Test func parseCustomReadsTheLocalesDecimalComma() {
        let german = Locale(identifier: "de_DE")
        let french = Locale(identifier: "fr_FR")
        #expect(SplitSize.parseCustom("1,5", unit: .gigabyte, locale: german)?.rawValue == 1_500_000_000)
        #expect(SplitSize.parseCustom("1,5", unit: .megabyte, locale: french)?.rawValue == 1_500_000)
        // The written-back form ("1.5") still reads the same everywhere.
        #expect(SplitSize.parseCustom("1.5", unit: .gigabyte, locale: german)?.rawValue == 1_500_000_000)
    }

    @Test func parseCustomDoesntGuessAtGroupingCommas() {
        let english = Locale(identifier: "en_US")
        #expect(SplitSize.readCustom("1,000", unit: .megabyte, locale: english) == .notANumber)
        #expect(SplitSize.readCustom("1,5", unit: .megabyte, locale: english) == .notANumber)
        #expect(SplitSize.readCustom("1,5", unit: .megabyte, locale: Locale(identifier: "zh_CN")) == .notANumber)
        #expect(SplitSize.readCustom("1,000,5", unit: .megabyte, locale: Locale(identifier: "de_DE")) == .notANumber)
    }

    @Test(arguments: ["en_US", "zh_CN", "ja_JP", "de_DE"])
    func parseCustomFoldsFullWidthDigits(locale: String) {
        let locale = Locale(identifier: locale)
        #expect(SplitSize.parseCustom("２５０", unit: .megabyte, locale: locale)?.rawValue == 250_000_000)
        #expect(SplitSize.parseCustom("１．５", unit: .gigabyte, locale: locale)?.rawValue == 1_500_000_000)
        #expect(SplitSize.parseCustom("　２　", unit: .gigabyte, locale: locale)?.rawValue == 2_000_000_000)
    }

    @Test func readCustomTellsNotANumberFromOutOfRange() {
        let english = Locale(identifier: "en_US")
        #expect(SplitSize.readCustom("", unit: .megabyte, locale: english) == .empty)
        #expect(SplitSize.readCustom("  ", unit: .megabyte, locale: english) == .empty)
        for text in ["abc", "1e3", "0x10", "-5", "+5", "inf", "nan", ".", "1.2.3", "1 000"] {
            #expect(SplitSize.readCustom(text, unit: .megabyte, locale: english) == .notANumber, "\(text)")
        }
        #expect(SplitSize.readCustom("0", unit: .megabyte, locale: english) == .outOfRange)
        #expect(SplitSize.readCustom("0.0005", unit: .megabyte, locale: english) == .outOfRange)
        #expect(SplitSize.readCustom("200000", unit: .gigabyte, locale: english) == .outOfRange)
        #expect(SplitSize.readCustom("1e30", unit: .gigabyte, locale: english) == .notANumber)
        #expect(SplitSize.readCustom("99999999999999999999", unit: .gigabyte, locale: english) == .outOfRange)
        #expect(SplitSize.readCustom("250", unit: .megabyte, locale: english) == .size(SplitSize(rawValue: 250_000_000)))
        #expect(SplitSize.readCustom(".5", unit: .gigabyte, locale: english) == .size(SplitSize(rawValue: 500_000_000)))
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

    /// The part-size editor starts from the size in use; reading its fields back gives the same bytes.
    @Test(arguments: [
        (Int64(250_000_000), "250", SplitSize.CustomUnit.megabyte),
        (1_500_000_000, "1.5", .gigabyte),
        (1_250_000_000, "1.25", .gigabyte),
        (4_000_000_000, "4", .gigabyte),
        (700_000_000, "700", .megabyte),
        (500_000, "0.5", .megabyte),
        (1_234_000, "1.234", .megabyte),
        (1_024, "0.001024", .megabyte),
        (1_234_567, "1.234567", .megabyte),
    ])
    func editableAmountRoundTrips(bytes: Int64, text: String, unit: SplitSize.CustomUnit) {
        let size = SplitSize(rawValue: bytes)
        #expect(size.editableAmount.text == text)
        #expect(size.editableAmount.unit == unit)
        #expect(SplitSize.parseCustom(text, unit: unit) == size)
    }

    @Test func editableAmountIsEmptyForOneFile() {
        #expect(SplitSize.none.editableAmount.text.isEmpty)
        #expect(SplitSize.none.editableAmount.unit == .megabyte)
    }

    @Test func partsRoundUpAndOneFileIsOnePart() {
        #expect(SplitSize(rawValue: 300_000_000).parts(for: 900_000_000) == 3)
        #expect(SplitSize(rawValue: 300_000_000).parts(for: 900_000_001) == 4)
        #expect(SplitSize(rawValue: 300_000_000).parts(for: 1) == 1)
        #expect(SplitSize(rawValue: 300_000_000).parts(for: 0) == 1)
        #expect(SplitSize.none.parts(for: 9_000_000_000) == 1)
    }

    @Test func formatBytesUsesDecimalLabels() {
        #expect(SplitSize.formatBytes(250_000_000) == "250 MB")
        #expect(SplitSize.formatBytes(1_500_000_000) == "1.5 GB")
        #expect(SplitSize.formatBytes(1_000_000_000) == "1 GB")
    }
}
