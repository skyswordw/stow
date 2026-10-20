import SwiftUI

/// Shown above the contents when names were stored in an older encoding.
struct LegacyNamesBanner: View {
    let model: BrowserModel

    var body: some View {
        let source = model.archive.source
        let reading = source?.nameEncoding?.title
            ?? NameEncoding.bestGuess(for: model.legacyNames).map { "\($0.title), automatically" } ?? "automatically"
        HStack(spacing: Space.s) {
            Image(systemName: "character.book.closed")
                .foregroundStyle(.tint)
            Text("Some names were stored in an older encoding. Reading them as \(reading).")
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: Space.s)
            Button("Change…") { model.isChoosingEncoding = true }
                .controlSize(.small)
        }
        .font(.callout)
        .padding(.horizontal, Space.m)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// Pick how legacy names are read, with the names themselves as the preview.
struct EncodingSheet: View {
    let model: BrowserModel
    @Environment(\.dismiss) private var dismiss
    @State private var choice: String

    init(model: BrowserModel) {
        self.model = model
        _choice = State(initialValue: model.archive.source?.nameEncoding?.id ?? "auto")
    }

    private var encoding: NameEncoding? { NameEncoding.named(choice) }
    private var samples: [Data] { Array(model.legacyNames.prefix(14)) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Read Names As")
                    .font(.headline)
                Text("This archive doesn’t say how its names are encoded. Pick the one where the names read right.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .top, spacing: Space.l) {
                List(selection: $choice) {
                    Label("Automatic", systemImage: "wand.and.stars")
                        .tag("auto")
                    Section("Encodings") {
                        ForEach(options) { option in
                            HStack {
                                Text(option.title)
                                Spacer()
                                if option.id == suggested?.id {
                                    Text("Suggested")
                                        .font(.caption)
                                        .foregroundStyle(.tint)
                                }
                            }
                            .tag(option.id)
                            .foregroundStyle(readable(option) ? .primary : .tertiary)
                        }
                    }
                }
                .listStyle(.bordered)
                .frame(width: 270, height: 300)

                VStack(alignment: .leading, spacing: Space.s) {
                    SectionLabel("Preview")
                    ScrollView {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(samples.indices, id: \.self) { index in
                                Text(preview(samples[index]))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .font(.callout)
                        .padding(Space.m)
                    }
                    .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: Radius.chip))
                    .overlay { RoundedRectangle(cornerRadius: Radius.chip).strokeBorder(.primary.opacity(0.1)) }
                }
                .frame(width: 320, height: 300)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Use") {
                    model.readNames(as: encoding)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(encoding.map(readable) == false)
            }
        }
        .padding(Space.xl)
    }

    private var options: [NameEncoding] { NameEncoding.candidates }
    private var suggested: NameEncoding? { NameEncoding.bestGuess(for: model.legacyNames) }

    private func readable(_ option: NameEncoding) -> Bool {
        samples.allSatisfy { option.decode($0) != nil }
    }

    private func preview(_ bytes: Data) -> String {
        guard let encoding else { return NameEncoding.decode(bytes, as: nil) }
        return encoding.decode(bytes) ?? "— can’t be read this way —"
    }
}
