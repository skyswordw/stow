import Foundation
import Testing
@testable import Stow

@Suite("Pack sentence")
struct PackSentenceTests {
    @Test func englishWordsAndPunctuation() {
        #expect(PackSentence.segments(from: PackSentence.defaultTemplate) == [
            .text("Pack"), .slot(.subject), .text("as"), .text("a"), .slot(.format),
            .text("for"), .slot(.audience, suffix: ","), .slot(.password, suffix: ","),
            .slot(.split, suffix: ".")
        ])
    }

    @Test func chineseRunsAndPunctuation() {
        #expect(PackSentence.segments(from: "将{subject}压缩为{format}格式，用于{audience}，{password}，{split}。") == [
            .text("将"), .slot(.subject), .text("压缩为"), .slot(.format), .text("格式，用于"),
            .slot(.audience, suffix: "，"), .slot(.password, suffix: "，"), .slot(.split, suffix: "。")
        ])
    }

    @Test func invalidTemplatesFallBack() {
        for template in [
            "Pack {subject} as {format} for {audience}, {password}.",
            "{subject}{format}{audience}{password}{split}{unknown}",
            "{subject}{format}{audience}{password}{split}{subject}"
        ] {
            #expect(PackSentence.segments(from: template) == PackSentence.segments(from: PackSentence.defaultTemplate))
        }
    }

    @Test func reorderedSlotsAndSubjectPunctuation() {
        #expect(PackSentence.segments(from: "{format} {subject}、{split} {password} {audience}") == [
            .slot(.format), .slot(.subject, suffix: "、"), .slot(.split), .slot(.password), .slot(.audience)
        ])
    }

    @Test func chineseCatalogKeepsEverySlot() throws {
        let path = try #require(Bundle.main.path(forResource: "zh-Hans", ofType: "lproj"))
        let bundle = try #require(Bundle(path: path))
        let template = bundle.localizedString(forKey: "pack.sentence", value: nil, table: nil)
        for slot in PackSentence.Slot.allCases {
            #expect(template.components(separatedBy: "{\(slot.rawValue)}").count == 2)
        }
        #expect(template.hasPrefix("将"))
    }
}
