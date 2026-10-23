import SwiftUI

/// "Pack “Project” as a ZIP for Windows PCs, without a password, as one file."
/// Every choice is a token in a sentence, and the report underneath says what that sentence will do.
/// Rarer choices (compression level, checking the result) wait under More Options.
struct PackSheet: View {
    let request: PackRequest
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        .animation(Motion.byKeyboard ? nil : Motion.resolved(Motion.token, reduceMotion: reduceMotion), value: options)
        .onAppear(perform: restore)
        .onDisappear {
            if !handedOffCleanup, let directory = request.cleanupDirectory { try? FileManager.default.removeItem(at: directory) }
        }
    }

    // MARK: Sentence

    private var sentence: some View {
        FlowLayout(spacing: 7, lineSpacing: 8) {
            ForEach(Array(PackSentence.segments(from: String(localized: "pack.sentence",
                defaultValue: "Pack {subject} as a {format} for {audience}, {password}, {split}.",
                comment: "Pack sheet sentence. Keep the five {…} placeholders (any order); each becomes a menu or the item name.")).enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let text): Text(text)
                case let .slot(slot, suffix): sentenceSlot(slot, suffix: suffix)
                }
            }
        }
        .font(.title2)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func sentenceSlot(_ slot: PackSentence.Slot, suffix: String) -> some View {
        switch slot {
        case .subject:
            subject(suffix: suffix)
        case .format:
            Token(title: options.format.displayName, suffix: suffix) {
                ForEach(options.audience.formats) { format in
                    Button(format.displayName) { options.setFormat(format) }
                }
            }
        case .audience:
            Token(title: options.audience.phrase, suffix: suffix) {
                ForEach(Audience.allCases) { audience in
                    Button(audience.phrase.prefix(1).uppercased() + audience.phrase.dropFirst()) {
                        setAudience(audience)
                    }
                }
            }
        case .password:
            Token(title: options.usesPassword ? String(localized: "with a password") : String(localized: "without a password"),
                  suffix: suffix, isEnabled: options.format.supportsPassword,
                  disabledHelp: String(localized: "\(options.format.displayName) can’t be password-protected")) {
                Button("Without a password") { options.usesPassword = false }
                Button("With a password") { options.usesPassword = true }
            }
        case .split:
            Token(title: options.split.phrase, suffix: suffix, isEnabled: options.format.supportsSplit,
                  disabledHelp: String(localized: "A \(options.format.displayName) is always one file")) {
                ForEach(SplitSize.allCases) { split in
                    Button(split.phrase.prefix(1).uppercased() + split.phrase.dropFirst()) { options.split = split }
                }
            }
        }
    }

    @ViewBuilder
    private func subject(suffix: String) -> some View {
        if request.roots.count == 1, let root = request.roots.first {
            Text(verbatim: "“\(root)”" + suffix)
                .fontWeight(.semibold)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 300)
                .fixedSize(horizontal: true, vertical: false)
        } else {
            Text(String(localized: "\(request.roots.count) items") + suffix)
                .fontWeight(.semibold)
                .liveNumber()
        }
    }

    private var passwordField: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "key.fill").accessibilityHidden(true).foregroundStyle(.secondary)
            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
            Button("Suggest") { password = Self.suggestedPassword() }
                .controlSize(.large)
        }
        // Slides down from the sentence that asked for it; goes faster than it came.
        .transition(AnyTransition.asymmetric(insertion: reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)),
                                removal: .opacity.animation(Motion.byKeyboard ? nil : Motion.resolved(Motion.exit, reduceMotion: reduceMotion))))
    }

    // MARK: More options

    private var levelCaption: String {
        guard options.format.isCompressed else { return String(localized: "A TAR collects files without compressing them.") }
        if options.format == .tarZst, options.level == .store {
            // zstd has no stored mode (Zstd.level(for:)), so say what Store means here.
            return String(localized: "Zstandard always compresses; Store uses its fastest level. Remembered for \(options.audience.phrase).")
        }
        return String(localized: "\(options.level.detail) Remembered for \(options.audience.phrase).")
    }

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
                        Text(levelCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if options.format == .dmg {
                    LabeledContent("Disk format") {
                        VStack(alignment: .leading, spacing: 2) {
                            Picker("Disk format", selection: $options.diskImageFilesystem) {
                                ForEach(DiskImageFilesystem.allCases) { Text($0.title).tag($0) }
                            }
                            .labelsHidden()
                            .fixedSize()
                            Text(options.diskImageFilesystem.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    LabeledContent("Layout") {
                        VStack(alignment: .leading, spacing: 2) {
                            Toggle("Applications shortcut", isOn: $options.diskImageApplicationsLink)
                            Text(String(localized: "Adds a link to /Applications so people can drag apps in Finder."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
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
                    .lineLimit(1)
                    .fixedSize() // ".tar.zst" wrapped after "tar."
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
        if let format = request.initialFormat {
            // A format only one audience offers (TAR.ZST) brings that audience with it.
            if !options.audience.formats.contains(format),
               let audience = Audience.allCases.first(where: { $0.formats.contains(format) }) {
                options.setAudience(audience)
            }
            options.format = format
        }
        options.level = PackPreferences.level(for: options.audience)
        options.verify = PackPreferences.verify
        options.split = options.format.supportsSplit ? SettingsKeys.splitSize() : .none
        // Design review: -StowPackDetails YES opens both disclosures.
        if UserDefaults.standard.bool(forKey: "StowPackDetails") { showDetails = true; showMore = true }
        // Design review: -StowPackPassword YES starts with "with a password" (formats that allow one).
        if UserDefaults.standard.bool(forKey: "StowPackPassword"), options.format.supportsPassword { options.usesPassword = true }
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
                threads: PackPreferences.threads,
                diskImageFilesystem: format == .dmg ? options.diskImageFilesystem : .hfsPlus,
                diskImageApplicationsLink: format == .dmg && options.diskImageApplicationsLink
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
    @Environment(\.colorSchemeContrast) private var contrast
    private var contrastStyle: ContrastStyle { .resolve(contrast) }
    let title: String
    var suffix = ""
    var isEnabled = true
    var disabledHelp = ""
    @ViewBuilder let items: () -> Items
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if isEnabled {
            // Punctuation sits against the chip's edge in sentence colour (-2 takes up the glyph's own
            // left margin); being in the same row, it wraps with the chip and never starts a line.
            HStack(spacing: -2) {
                menu
                if !suffix.isEmpty { Text(suffix) }
            }
        } else {
            fixed
        }
    }

    private var menu: some View {
        Menu {
            items()
        } label: {
            Text(title)
                .fontWeight(.semibold)
                .foregroundStyle(.tint)
                .id(title)
                // Blur-replace scales a little, so Reduce Motion gets the cross-fade alone.
                .transition(reduceMotion ? AnyTransition.opacity : AnyTransition(.blurReplace))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .background(.tint.opacity(isHovering ? 0.16 : 0.08), in: .rect(cornerRadius: 6))
        .onHover { isHovering = $0 }
        .help(String(localized: "Click to change"))
    }

    /// A word this format decides ("as one file" for a DMG): plain sentence text, not a faded
    /// button, with its punctuation attached in the same colour. The reason is in the tooltip
    /// and spoken after it.
    private var fixed: some View {
        Text(title + suffix)
            .foregroundStyle(contrastStyle.increased ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .id(title)
            .transition(reduceMotion ? AnyTransition.opacity : AnyTransition(.blurReplace))
            .fixedSize()
            .help(disabledHelp)
            .accessibilityHint(disabledHelp)
    }
}

private struct ReportView: View {
    @Environment(\.colorSchemeContrast) private var contrast
    private var contrastStyle: ContrastStyle { .resolve(contrast) }
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
                        Image(systemName: "arrow.right").accessibilityHidden(true)
                            .font(.caption)
                            .foregroundStyle(contrastStyle.metadata)
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
