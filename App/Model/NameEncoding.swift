import Foundation

/// Older encodings that ZIP names turn up in. ZIP has one flag for "these names are UTF-8"; without
/// it, a name is whatever bytes the zipping computer used — GBK in China, Shift JIS in Japan, CP437
/// on old DOS tools — and nothing in the archive says which.
nonisolated struct NameEncoding: Hashable, Sendable, Identifiable {
    let id: String
    let title: String
    let encoding: String.Encoding

    private init(_ id: String, _ title: String, _ cf: CFStringEncodings) {
        self.id = id
        self.title = title
        encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(cf.rawValue)))
    }

    private init(_ id: String, _ title: String, _ encoding: String.Encoding) {
        self.id = id
        self.title = title
        self.encoding = encoding
    }

    static let utf8 = NameEncoding("utf8", "Unicode (UTF-8)", .utf8)

    /// Most likely first: these cover nearly every legacy ZIP in the wild.
    static let candidates: [NameEncoding] = [
        NameEncoding("gbk", "Chinese, Simplified (GBK)", .GB_18030_2000),
        NameEncoding("big5", "Chinese, Traditional (Big5)", .big5_HKSCS_1999),
        NameEncoding("sjis", "Japanese (Shift JIS)", .dosJapanese),
        NameEncoding("cp949", "Korean (CP949)", .dosKorean),
        NameEncoding("cp1251", "Cyrillic (Windows-1251)", .windowsCyrillic),
        NameEncoding("cp866", "Cyrillic (DOS 866)", .dosRussian),
        NameEncoding("cp437", "Western (DOS 437)", .dosLatinUS),
        NameEncoding("cp850", "Western (DOS 850)", .dosLatin1),
        NameEncoding("cp1252", "Western (Windows-1252)", String.Encoding.windowsCP1252),
        NameEncoding("cp1250", "Central European (Windows-1250)", .windowsLatin2),
        NameEncoding("cp1253", "Greek (Windows-1253)", .windowsGreek),
        NameEncoding("cp1254", "Turkish (Windows-1254)", .windowsLatin5),
        NameEncoding("cp1255", "Hebrew (Windows-1255)", .windowsHebrew),
        NameEncoding("cp1256", "Arabic (Windows-1256)", .windowsArabic),
        NameEncoding("cp874", "Thai (Windows-874)", .dosThai),
        NameEncoding("macroman", "Mac OS Roman", String.Encoding.macOSRoman),
    ]

    static func named(_ id: String) -> NameEncoding? {
        id == utf8.id ? utf8 : candidates.first { $0.id == id }
    }

    func decode(_ bytes: Data) -> String? {
        String(data: bytes, encoding: encoding)
    }

    /// `nil` encoding means automatic: valid UTF-8 stays UTF-8, anything else gets the encoding
    /// that reads most like a real name — per name, so archives that mix encodings still read.
    static func decode(_ bytes: Data, as chosen: NameEncoding?) -> String {
        if let chosen, let name = chosen.decode(bytes) { return name }
        if let name = String(data: bytes, encoding: .utf8) { return name }
        return bestReading(of: bytes).name
    }

    static func bestReading(of bytes: Data) -> (name: String, encoding: NameEncoding) {
        var best: (name: String, encoding: NameEncoding, score: Double)?
        for candidate in candidates {
            guard let name = candidate.decode(bytes) else { continue }
            let score = plausibility(of: name)
            if best == nil || score > best!.score { best = (name, candidate, score) }
        }
        return best.map { ($0.name, $0.encoding) } ?? (String(decoding: bytes, as: UTF8.self), utf8)
    }

    /// The single encoding that reads a set of names best (for the picker's suggestion).
    static func bestGuess(for names: [Data]) -> NameEncoding? {
        guard !names.isEmpty else { return nil }
        var totals: [NameEncoding: Double] = [:]
        for candidate in candidates {
            var total = 0.0
            for bytes in names {
                guard let name = candidate.decode(bytes) else { total = -.infinity; break }
                total += plausibility(of: name)
            }
            totals[candidate] = total
        }
        return candidates.max { (totals[$0] ?? -.infinity) < (totals[$1] ?? -.infinity) }
    }

    /// How much a decoded name looks like something a person typed: common characters of a real
    /// script score up, box drawing, control and private-use characters (the look of mojibake) down.
    static func plausibility(of name: String) -> Double {
        var score = 0.0, counted = 0
        for scalar in name.unicodeScalars where !scalar.isASCII || scalar.value < 0x20 {
            counted += 1
            let value = scalar.value
            switch value {
            case 0..<0x20, 0x7F...0x9F, 0xE000...0xF8FF, 0xFFFD: score -= 6
            case 0x2500...0x259F, 0x2320...0x23FF, 0x2190...0x21FF, 0x2660...0x266F: score -= 4
            case 0x3040...0x30FF: score += 3                                   // kana
            case 0xAC00...0xD7A3: score += 2                                   // Hangul
            case 0x4E00...0x9FFF:
                score += Self.common.contains(Character(scalar)) ? 3 : 0.5    // CJK ideographs
            case 0x3400...0x4DBF, 0x20000...: score -= 1                     // rare ideographs
            case 0x0400...0x045F: score += 1.5                                // Cyrillic letters
            case 0x0590...0x05FF, 0x0600...0x06FF, 0x0E00...0x0E7F: score += 1.5
            case 0x0391...0x03C9: score += 0.5                                // Greek
            case 0xC0...0xFF where value != 0xD7 && value != 0xF7: score += 1  // accented Latin
            case 0x0100...0x017F: score += 0.5
            case 0x3000...0x303F, 0xFF01...0xFF5E: score += 1                // CJK punctuation, full width
            case 0xFF61...0xFF9F: score -= 1                                 // half-width kana: usually a misreading
            default: score -= 1.5
            }
        }
        return counted == 0 ? 0 : score / Double(counted) + (name.contains("\u{FFFD}") ? -10 : 0)
    }

    /// Frequent Chinese characters in both simplified and traditional forms, and common kanji.
    private static let common = Set("""
    的一是不了人我在有他这中大来上国个到说们为子和你地出道也时年得就那要下以生会自着去之过家学对可她里后小么心多天而能好都然没日于起\
    还发成事只作当想看文无开手十用主行方又如前所本见经头面公同三已老从动两长知民样现分将外但身些与高意进把法此实回二理美点月明其种声全\
    工己话儿者向情部正名定女问力机给等几很业最间新什打便位因重被走电四第门相次东政海口使教西再平真听世气信北少关并内加化由却代军产入先\
    山五太水万市眼体别处总才场师书比住员九笑性通目华报立马命张活难神数件安表原车白应路期叫死常提感金何更反合放做系计或司利受光王果亲界\
    及今京务制解各任至清物台象记边共风战干接它许八特觉望直服毛林题建南度统色字请交爱让认算论百吃义科怎元社术结六功指思非流每青管夫连远\
    资队跟带花快条院变联言权往展该领传近留红治决周保达办运武半候七必城父强步完革深区即求品士转量空甚众技轻程告江语英基派满式李息写呢识\
    极令黄德收脸钱党倒未持取设始版双历越史商千片容研像找友孩站广改议形委早房音火际则首单据导影失拿网香似斯专石若兵弟谁校读志飞观争究包\
    组造落视济喜离虽坏兴图档案资料照片视频音乐软件下载备份设计文档项目报告合同发票简历课件作业试卷附件新建压缩包表格数据统计图片\
    們個這來國說會時對過學後經現動兩長樣將實進點開頭話種從東間電門問題當聽氣輕書樂機關係區發無與還應給對們義體們邊選擇項計劃\
    檔資圖錄專業設計報告檔案資料照片視頻音樂軟體備份項目合約發票簡歷課程作業試題附件壓縮表單數據統計圖片範例說明\
    写真資料画像動画音楽書類新規作成会議議事録報告書請求書見積書契約書企画提案設計仕様説明版最終確認用年月日
    """.filter { !$0.isNewline && $0 != "\\" })
}
