import Foundation
import Testing
@testable import Stow

@Suite("Localization")
struct LocalizationTests {
    private func chineseBundle() throws -> Bundle {
        let path = try #require(Bundle.main.path(forResource: "zh-Hans", ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    @Test func bundleDeclaresSimplifiedChinese() {
        #expect(Bundle.main.localizations.contains("zh-Hans"))
    }

    @Test func translatedSamples() throws {
        let bundle = try chineseBundle()
        #expect(bundle.localizedString(forKey: "General", value: nil, table: nil) == "通用")
        #expect(bundle.localizedString(forKey: "Extract All", value: nil, table: nil) == "全部解压缩")
        #expect(bundle.localizedString(forKey: "Settings", value: nil, table: nil) == "设置")
        #expect(bundle.localizedString(forKey: "Move to Trash", value: nil, table: nil) == "移到废纸篓")
    }

    @Test func everySettingsPaneHasTranslation() throws {
        let bundle = try chineseBundle()
        // The test host runs in English; pane titles are the catalog's English source keys.
        for pane in SettingsPane.allCases {
            let english = pane.title
            let translated = bundle.localizedString(forKey: english, value: nil, table: nil)
            #expect(!translated.isEmpty)
            #expect(translated != english)
        }
    }

    /// Apps are named as people know them in Chinese (DESIGN: plain words), not by their English names.
    @Test func appNamesUseTheirChineseNames() throws {
        let bundle = try chineseBundle()
        let names = ["WeChat": "微信", "WeCom": "企业微信", "DingTalk": "钉钉", "QQ": "QQ", "Telegram": "Telegram"]
        for (english, chinese) in names {
            #expect(bundle.localizedString(forKey: english, value: nil, table: nil) == chinese)
        }
    }

    @MainActor @Test func englishReportPluralsStayUnchanged() {
        let report = Associations.Report(kind: .madeDefault, changed: ["ZIP"], failed: ["RAR": "", "7Z": ""])
        #expect(report.summary == "1 type now open with Stow · 2 types not changed")
    }
}
