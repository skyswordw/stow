import Foundation

/// Keeps incomplete numeric edits separate from the last valid PackOptions override.
/// `nil` still means inherit Settings; it is never the result of an invalid custom edit.
struct CPUCoreLimitInput: Equatable {
    var isCustom: Bool
    var text: String

    init(threads: Int? = nil, inherited: Int? = nil, available: Int = ProcessInfo.processInfo.activeProcessorCount) {
        isCustom = threads != nil
        text = String(min(max(1, threads ?? inherited ?? available), max(1, available)))
    }

    func customValue(available: Int) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.allSatisfy({ (48...57).contains($0) }),
              let value = Int(trimmed), (1...max(1, available)).contains(value) else { return nil }
        return value
    }

    func isValid(available: Int) -> Bool { !isCustom || customValue(available: available) != nil }

    func overrideValue(available: Int) -> Int? {
        isCustom ? customValue(available: available) : nil
    }

    mutating func edit(_ text: String) {
        // SwiftUI may write the current string back when the native editor gains focus.
        // Focusing an untouched default must not freeze it as a per-job override.
        guard text != self.text else { return }
        isCustom = true
        self.text = text
    }
}
