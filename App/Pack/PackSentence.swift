/// Parses the translated sentence without tying its word order to the controls.
nonisolated enum PackSentence {
    static let defaultTemplate = "Pack {subject} as a {format} for {audience}, {password}, {split}."

    enum Slot: String, CaseIterable {
        case subject, format, audience, password, split
    }

    enum Segment: Equatable {
        case text(String)
        case slot(Slot, suffix: String = "")
    }

    static func segments(from template: String) -> [Segment] {
        parse(template) ?? parse(defaultTemplate)!
    }

    private static func parse(_ template: String) -> [Segment]? {
        var result: [Segment] = []
        var seen: Set<Slot> = []
        var remaining = template[...]

        func appendLiteral(_ literal: Substring) {
            var literal = literal
            if let last = result.last, case let .slot(slot, suffix) = last {
                let punctuation = literal.prefix { ",，.。、：".contains($0) }
                result[result.count - 1] = .slot(slot, suffix: suffix + String(punctuation))
                literal = literal.dropFirst(punctuation.count)
            }
            result.append(contentsOf: literal.split(separator: " ").map { .text(String($0)) })
        }

        while let opening = remaining.firstIndex(of: "{") {
            let literal = remaining[..<opening]
            guard !literal.contains("}"),
                  let closing = remaining[opening...].firstIndex(of: "}"),
                  let slot = Slot(rawValue: String(remaining[remaining.index(after: opening)..<closing])),
                  seen.insert(slot).inserted else { return nil }
            appendLiteral(literal)
            result.append(.slot(slot))
            remaining = remaining[remaining.index(after: closing)...]
        }
        guard !remaining.contains("}"), seen.count == Slot.allCases.count else { return nil }
        appendLiteral(remaining)
        return result
    }
}
