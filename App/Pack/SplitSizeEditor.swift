import SwiftUI

/// The one editor for a custom part size (#151, #153). It opens in a popover from whatever was
/// clicked — the sentence's last words, the Split archives menu in More Options, Settings ›
/// Packing — so it appears where the person is looking, and nothing changes until Use.
struct SplitSizeEditor: View {
    /// Where the fields start: the size in use when it's custom, otherwise empty.
    let initial: SplitSize
    /// What a valid size would mean for the items being packed ("About 12 parts"), when known.
    var outcome: ((SplitSize) -> String)?
    let apply: (SplitSize) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var unit = SplitSize.CustomUnit.megabyte
    @FocusState private var isFocused: Bool

    private var input: SplitSize.CustomInput { SplitSize.readCustom(text, unit: unit) }
    private var parsed: SplitSize? {
        if case .size(let size) = input { return size }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Size of Each Part")
                .font(.headline)
            HStack(spacing: Space.s) {
                TextField("Size", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: 96)
                    .focused($isFocused)
                    .onSubmit(use)
                // Two units, both visible: a segmented control says which one applies at a glance.
                Picker("Unit", selection: $unit) {
                    ForEach(SplitSize.CustomUnit.allCases) { Text($0.symbol).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            // One line that always says something, so the popover never changes height as people type.
            status
                .font(.callout)
                .lineLimit(2, reservesSpace: true)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Space.s) {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Use") { use() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(parsed == nil)
            }
        }
        .padding(Space.l)
        .frame(width: 280)
        // A popover inherits its anchor's environment: the sentence's title2, More Options' callout.
        // It looks the same wherever it came from.
        .font(.body)
        .controlSize(.regular)
        .onAppear {
            (text, unit) = initial.editableAmount
            isFocused = true
        }
    }

    @ViewBuilder
    private var status: some View {
        if let parsed {
            Text(outcome?(parsed) ?? String(localized: "Each part is at most this size."))
                .foregroundStyle(.secondary)
                .liveNumber()
        } else if input == .empty {
            Text("Each part is at most this size.")
                .foregroundStyle(.secondary)
        } else {
            // #194: "abc" or "1,000" isn't a size out of range; say what to type instead.
            Label {
                Text(input == .notANumber
                     ? String(localized: "Enter a number, like 250 or 1.5.")
                     : String(localized: "Enter a size between 1 KB and 100 TB."))
            } icon: {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
            }
        }
    }

    private func use() {
        guard let parsed else { return }
        apply(parsed)
        dismiss()
    }
}
