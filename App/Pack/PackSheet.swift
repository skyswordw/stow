import SwiftUI

struct PackRequest: Identifiable {
    let id = UUID()
    var files: [PackFile]
}

/// "Pack 12 items as a ZIP for Windows PCs, without a password, as one file."
/// Every choice is a token in a sentence, and the report underneath says what that sentence will do.
struct PackSheet: View {
    let request: PackRequest
    @Environment(\.dismiss) private var dismiss
    @State private var options = PackOptions()
    @State private var password = ""
    @State private var showDetails = false

    private var report: PackReport { Compatibility.report(for: request.files, options: options) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            sentence
            if options.usesPassword { passwordField }
            ReportView(report: report, showDetails: $showDetails)
            footer
        }
        .padding(Space.xxl)
        .frame(width: 560)
        .animation(Motion.token, value: options)
    }

    // MARK: Sentence

    private var sentence: some View {
        FlowLayout(spacing: 7, lineSpacing: 8) {
            words("Pack")
            Text("\(report.included.count) items")
                .fontWeight(.semibold)
                .liveNumber()
            words("as a")
            Token(title: options.format.displayName) {
                ForEach(options.audience.formats) { format in
                    Button(format.displayName) { options.setFormat(format) }
                }
            }
            words("for")
            Token(title: options.audience.phrase, suffix: ",") {
                ForEach(Audience.allCases) { audience in
                    Button(audience.phrase.prefix(1).uppercased() + audience.phrase.dropFirst()) {
                        options.setAudience(audience)
                    }
                }
            }
            Token(title: options.usesPassword ? "with a password" : "without a password",
                  suffix: ",", isEnabled: options.format.supportsPassword) {
                Button("Without a password") { options.usesPassword = false }
                Button("With a password") { options.usesPassword = true }
            }
            Token(title: options.split.phrase, suffix: ".") {
                ForEach(SplitSize.allCases) { split in
                    Button(split.phrase.prefix(1).uppercased() + split.phrase.dropFirst()) { options.split = split }
                }
            }
        }
        .font(.title2)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func words(_ string: String) -> some View {
        ForEach(string.split(separator: " ").map(String.init), id: \.self) { Text($0) }
    }

    private var passwordField: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "key.fill").foregroundStyle(.secondary)
            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
            Button("Suggest") { password = Self.suggestedPassword() }
                .controlSize(.large)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var footer: some View {
        HStack {
            Text("≈ \(report.estimatedSize.bytes)\(report.parts > 1 ? " in \(report.parts) parts" : "")")
                .font(.callout)
                .foregroundStyle(.secondary)
                .liveNumber()
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .controlSize(.large)
            Button("Pack") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(options.usesPassword && password.isEmpty)
        }
    }

    static func suggestedPassword() -> String {
        let alphabet = Array("abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return (0..<4).map { _ in String((0..<4).map { _ in alphabet.randomElement()! }) }.joined(separator: "-")
    }
}

/// A sentence word you can change. Looks like text, behaves like a menu.
private struct Token<Items: View>: View {
    let title: String
    var suffix = ""
    var isEnabled = true
    @ViewBuilder let items: () -> Items
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 1) {
            menu
            if !suffix.isEmpty { Text(suffix) }
        }
    }

    private var menu: some View {
        Menu {
            items()
        } label: {
            Text(title)
                .fontWeight(.semibold)
                .foregroundStyle(isEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                .id(title)
                .transition(.blurReplace)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .background(.tint.opacity(isHovering && isEnabled ? 0.16 : 0.08), in: .rect(cornerRadius: 6))
        .onHover { isHovering = $0 }
        .disabled(!isEnabled)
        .help(isEnabled ? "Click to change" : "This format can’t be password-protected")
    }
}

private struct ReportView: View {
    let report: PackReport
    @Binding var showDetails: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            if report.renames.isEmpty {
                row(.fine, "All names work there", "No characters or names that the other system rejects.")
            } else {
                row(.info,
                    "\(report.renames.count) \(report.renames.count == 1 ? "name" : "names") will be adjusted",
                    "Characters Windows doesn’t allow are replaced. Your originals stay as they are.")
            }
            if !report.excluded.isEmpty {
                row(.info,
                    "\(report.excluded.count) Mac-only files left out",
                    "“.DS_Store”, “._” and other Finder files mean nothing on other systems.")
            }
            ForEach(report.notes, id: \.title) { note in
                row(note.tone, note.title, note.detail)
            }

            if !report.renames.isEmpty {
                DisclosureGroup("Show changes", isExpanded: $showDetails) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(report.renames, id: \.from) { rename in
                            HStack(spacing: 6) {
                                Text(rename.from.replacingOccurrences(of: "\r", with: "␍"))
                                    .strikethrough()
                                    .foregroundStyle(.secondary)
                                Image(systemName: "arrow.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                Text(rename.to)
                            }
                            .font(.callout.monospaced())
                            .lineLimit(1)
                        }
                    }
                    .padding(.top, Space.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.callout)
                .padding(.leading, 26)
            }
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: Radius.card))
    }

    private func row(_ tone: PackReport.Tone, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Image(systemName: tone.symbol)
                .foregroundStyle(tone.color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
