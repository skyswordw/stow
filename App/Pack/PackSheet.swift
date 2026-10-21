import SwiftUI

/// "Pack “Project” as a ZIP for Windows PCs, without a password, as one file."
/// Every choice is a token in a sentence, and the report underneath says what that sentence will do.
/// Rarer choices (compression level, checking the result) wait under More Options.
struct PackSheet: View {
    let request: PackRequest
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var options = PackOptions()
    @State private var password = ""
    @State private var name = ""
    @State private var overrides: [String: String] = [:]
    @State private var showDetails = false
    @State private var showMore = false
    @State private var isChoosing = false
    @State private var handedOffCleanup = false

    private var report: PackReport {
        Compatibility.report(for: request.files, options: options, password: password, overrides: overrides)
    }

    private var archiveName: String { Compatibility.archiveName(name, for: options.audience) }

    var body: some View {
        let report = report
        VStack(alignment: .leading, spacing: Space.xl) {
            sentence
            if options.usesPassword { passwordField }
            ReportView(report: report, audience: options.audience, overrides: $overrides, showDetails: $showDetails)
            moreOptions
            VStack(alignment: .leading, spacing: Space.l) {
                nameRow
                footer(report)
            }
        }
        .padding(Space.xxl)
        .frame(minWidth: 580)
        .animation(Motion.token, value: options)
        .onAppear(perform: restore)
        .onDisappear {
            if !handedOffCleanup, let directory = request.cleanupDirectory { try? FileManager.default.removeItem(at: directory) }
        }
    }

    // MARK: Sentence

    private var sentence: some View {
        FlowLayout(spacing: 7, lineSpacing: 8) {
            words(String(localized: "Pack"))
            subject
            words(String(localized: "as a"))
            Token(title: options.format.displayName) {
                ForEach(options.audience.formats) { format in
                    Button(format.displayName) { options.setFormat(format) }
                }
            }
            words(String(localized: "for"))
            Token(title: options.audience.phrase, suffix: String(localized: ",")) {
                ForEach(Audience.allCases) { audience in
                    Button(audience.phrase.prefix(1).uppercased() + audience.phrase.dropFirst()) {
                        setAudience(audience)
                    }
                }
            }
            Token(title: options.usesPassword ? String(localized: "with a password") : String(localized: "without a password"),
                  suffix: String(localized: ","), isEnabled: options.format.supportsPassword,
                  disabledHelp: String(localized: "\(options.format.displayName) can’t be password-protected")) {
                Button("Without a password") { options.usesPassword = false }
                Button("With a password") { options.usesPassword = true }
            }
            Token(title: options.split.phrase, suffix: String(localized: ".")) {
                ForEach(SplitSize.allCases) { split in
                    Button(split.phrase.prefix(1).uppercased() + split.phrase.dropFirst()) { options.split = split }
                }
            }
        }
        .font(.title2)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var subject: some View {
        if request.roots.count == 1, let root = request.roots.first {
            Text("“\(root)”")
                .fontWeight(.semibold)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 300)
                .fixedSize(horizontal: true, vertical: false)
        } else {
            Text("\(request.roots.count) items")
                .fontWeight(.semibold)
                .liveNumber()
        }
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

    // MARK: More options

    private var moreOptions: some View {
        DisclosureGroup("More Options", isExpanded: $showMore) {
            VStack(alignment: .leading, spacing: Space.m) {
                LabeledContent("Compression") {
                    VStack(alignment: .leading, spacing: 2) {
                        Picker("Compression", selection: levelBinding) {
                            ForEach(CompressionLevel.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .disabled(!options.format.isCompressed)
                        Text(options.format.isCompressed
                             ? String(localized: "\(options.level.detail) Remembered for \(options.audience.phrase).")
                             : String(localized: "A TAR collects files without compressing them."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Verify") {
                    Toggle("Test every file once it’s packed", isOn: $options.verify)
                }
            }
            .padding(.top, Space.s)
            .padding(.leading, Space.xs)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    private var levelBinding: Binding<CompressionLevel> {
        Binding(get: { options.level }, set: { level in
            options.level = level
            PackPreferences.setLevel(level, for: options.audience)
        })
    }

    // MARK: Footer

    private var nameRow: some View {
        HStack(spacing: Space.s) {
            Text("Save as")
                .foregroundStyle(.secondary)
            HStack(spacing: Space.xs) {
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                Text("." + options.format.fileExtension)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }
            if archiveName != name.trimmingCharacters(in: .whitespaces), !name.isEmpty {
                Text("→ \(archiveName)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help("Characters \(options.audience.phrase) don’t allow are replaced.")
            }
        }
    }

    private func footer(_ report: PackReport) -> some View {
        HStack {
            Text("≈ \(report.estimatedSize.bytes)\(report.parts > 1 ? String(localized: " in \(report.parts) parts") : "")")
                .font(.callout)
                .foregroundStyle(.secondary)
                .liveNumber()
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .controlSize(.large)
            Button("Pack…") { pack(report) }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(isChoosing || report.included.isEmpty || (options.usesPassword && password.isEmpty))
        }
    }

    // MARK: Actions

    private func restore() {
        name = request.suggestedName
        options.setAudience(PackPreferences.audience)
        if let format = request.initialFormat { options.format = format }
        options.level = PackPreferences.level(for: options.audience)
        options.verify = PackPreferences.verify
        options.split = SettingsKeys.splitSize()
        // Design review: -StowPackDetails YES opens both disclosures.
        if UserDefaults.standard.bool(forKey: "StowPackDetails") { showDetails = true; showMore = true }
    }

    private func setAudience(_ audience: Audience) {
        options.setAudience(audience)
        options.level = PackPreferences.level(for: audience)
    }

    private func pack(_ report: PackReport) {
        let format = options.format
        let fileName = archiveName + "." + format.fileExtension
        PackPreferences.audience = options.audience
        PackPreferences.verify = options.verify
        guard !request.isSample else {
            app.packing.simulate(name: fileName)
            dismiss()
            return
        }
        isChoosing = true
        Task {
            defer { isChoosing = false }
            guard let destination = await PackDestination.choose(for: fileName, startingAt: request.directory) else { return }
            var conflict = ArchiveCreation.Conflict.keepBoth
            if !ArchiveCreation.existing(named: archiveName, format: format, in: destination).isEmpty {
                var free = 2
                while !ArchiveCreation.existing(named: "\(archiveName) \(free)", format: format, in: destination).isEmpty { free += 1 }
                guard let choice = await PackDestination.resolveConflict(
                    fileName: fileName, keepBothName: "\(archiveName) \(free).\(format.fileExtension)", in: destination
                ) else { return }
                conflict = choice
            }
            let keepsMetadata = options.audience.keepsMacMetadata && format == .zip
            let cleanupDirectory = self.request.cleanupDirectory
            let request = CreateRequest(
                operationID: UUID().uuidString,
                archiveName: archiveName,
                format: format,
                level: options.level,
                password: options.usesPassword ? password : nil,
                volumeSize: options.split == .none ? nil : options.split.rawValue,
                keepsMacMetadata: keepsMetadata,
                verify: options.verify,
                threads: PackPreferences.threads
            )
            handedOffCleanup = true
            app.packing.start(.init(items: report.items, totalBytes: report.totalBytes, attributes: keepsMetadata,
                                    request: request, name: archiveName, destination: destination, conflict: conflict, cleanupDirectory: cleanupDirectory))
            dismiss()
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
    var disabledHelp = ""
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
        .help(isEnabled ? String(localized: "Click to change") : disabledHelp)
    }
}

private struct ReportView: View {
    let report: PackReport
    let audience: Audience
    @Binding var overrides: [String: String]
    @Binding var showDetails: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            if report.renames.isEmpty {
                row(.fine, String(localized: "All names work there"), String(localized: "No characters or names that the other system rejects."))
            } else {
                row(.info,
                    String(localized: "\(report.renames.count) names will be adjusted"),
                    audience.normalizesNames
                        ? String(localized: "Characters Windows doesn’t allow are replaced. Your originals stay as they are.")
                        : String(localized: "Names that would clash are numbered. Your originals stay as they are."))
            }
            if !report.excluded.isEmpty {
                row(.info,
                    String(localized: "\(report.excluded.count) Mac-only files left out"),
                    String(localized: "“.DS_Store”, “._” and other Finder files mean nothing on other systems."))
            }
            if !report.leftOutLinks.isEmpty {
                row(.info,
                    String(localized: "\(report.leftOutLinks.count) links left out"),
                    String(localized: "\(audience.phrase.prefix(1).uppercased() + audience.phrase.dropFirst()) can’t recreate symbolic links. Choose Macs or Linux to keep them."))
            }
            ForEach(report.notes, id: \.title) { note in
                row(note.tone, note.title, note.detail)
            }

            if !report.renames.isEmpty {
                DisclosureGroup("Review names", isExpanded: $showDetails) {
                    renameList
                }
                .font(.callout)
                .padding(.leading, 26)
            }
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: Radius.card))
    }

    /// Each suggested name is editable; what people type is made safe the same way.
    private var renameList: some View {
        ScrollView {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(report.renames) { rename in
                    GridRow {
                        Text(rename.from.replacingOccurrences(of: "\r", with: "␍"))
                            .strikethrough()
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(rename.path)
                        Image(systemName: "arrow.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        TextField(rename.suggested, text: binding(for: rename))
                            .textFieldStyle(.roundedBorder)
                    }
                    .font(.callout.monospaced())
                }
            }
            .padding(.top, Space.s)
            .padding(.trailing, Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 180)
        .scrollBounceBehavior(.basedOnSize)
    }

    private func binding(for rename: PackReport.Rename) -> Binding<String> {
        Binding(get: { overrides[rename.path] ?? rename.to },
                set: { overrides[rename.path] = $0.isEmpty ? nil : $0 })
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
