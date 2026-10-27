import AppKit
import SwiftUI

/// "Pack “Project” as a ZIP for Windows PCs, without a password, as one file."
/// Every choice is a token in a sentence, and the report underneath says what that sentence will do.
/// Rarer choices (compression level, checking the result) wait under More Options, whose
/// heading says what they're set to while it's closed.
struct PackSheet: View {
    let request: PackRequest
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var options = PackOptions()
    @State private var password = ""
    @State private var confirmation = ""
    @State private var revealsPassword = false
    /// The password as it last appeared on screen. Seeing it counts as checking it.
    @State private var seenPassword: String?
    @FocusState private var focus: Field?
    @State private var name = ""
    @State private var overrides: [String: String] = [:]
    @State private var showDetails = false
    @State private var showMore = false
    @State private var middleHeight: CGFloat?
    @State private var overflow = ScrollEdges()
    /// Where the middle is scrolled to; opening More Options moves it.
    @State private var scrollPosition = ScrollPosition()
    @State private var isChoosing = false
    @State private var handedOffCleanup = false
    /// Which Custom… opened the part-size editor; it pops out of that control.
    @State private var editingSplit: SplitEditorAnchor?

    private enum SplitEditorAnchor { case sentence, options }

    private var report: PackReport {
        Compatibility.report(for: request.files, options: options, password: password, overrides: overrides)
    }

    private var archiveName: String { Compatibility.archiveName(name, for: options.audience) }

    /// A sheet takes its height from its content's minimum, and a scroll view's is almost nothing.
    /// So the middle asks for all of itself, up to what fits on screen beside the sentence, name
    /// and buttons (about 380 pt); past that it scrolls.
    private var middleMinHeight: CGFloat {
        // Design review: -StowPackWhole YES lifts the screen budget so a view-tree snapshot shows it all.
        if UserDefaults.standard.bool(forKey: "StowPackWhole") { return middleHeight ?? 0 }
        let budget = (NSScreen.main?.visibleFrame.height ?? 800) - 380
        return min(middleHeight ?? 0, max(budget, 240))
    }

    /// More Options' place in the scrolling middle.
    private static let moreOptionsID = "moreOptions"

    private enum Field: Hashable { case password, confirmation }

    var body: some View {
        let report = report
        VStack(alignment: .leading, spacing: Space.xl) {
            sentence
            // The middle grows with what people open (names, options). It asks for its full height,
            // so the sheet fits it when it can; when the screen can't, only the middle scrolls and
            // the sentence, name and buttons stay where they are. One copy of the fields, so focus
            // and typing survive the switch.
            ScrollView {
                middle(report)
                    .padding(Space.xs) // room for focus rings inside the clip…
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) { middleHeight = $0 }
            }
            .scrollPosition($scrollPosition)
            .frame(minHeight: middleMinHeight, idealHeight: middleHeight)
            .scrollBounceBehavior(.basedOnSize)
            .onScrollGeometryChange(for: ScrollEdges.self, of: ScrollEdges.init) { _, edges in overflow = edges }
            // Whichever edge has more beyond it fades out, so a cut-off section reads as "scroll for more".
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: overflow.above ? Space.xl : 0)
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: overflow.below ? Space.xl : 0)
                }
            }
            .onChange(of: showMore) { _, opened in
                // Opening More Options at the foot of a short screen would grow it out of sight;
                // bring its heading to the top instead. When everything fits there's nothing to
                // scroll and this does nothing. It waits for the section to finish opening: until
                // then the middle isn't tall enough to scroll, and an earlier scroll was measured
                // to go nowhere. A move in space, so a spring; none when a key opened it or under
                // Reduce Motion, where the middle just jumps (DESIGN.md › Motion).
                guard opened else { return }
                let animation = Motion.byKeyboard || reduceMotion ? nil : Motion.appear
                Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard showMore else { return }
                    withAnimation(animation) { scrollPosition.scrollTo(id: Self.moreOptionsID, anchor: .top) }
                }
            }
            .padding(-Space.xs) // …without moving the content off the sheet's grid
            VStack(alignment: .leading, spacing: Space.l) {
                nameRow
                footer(report)
            }
        }
        .padding(Space.xxl)
        .frame(minWidth: 580)
        .animation(Motion.byKeyboard ? nil : Motion.resolved(Motion.token, reduceMotion: reduceMotion), value: options)
        .onChange(of: options.usesPassword) { _, uses in
            // Choosing "with a password" means typing one next.
            if uses { focus = .password }
        }
        .onChange(of: password) { _, new in
            if revealsPassword { seenPassword = new }
        }
        .onAppear(perform: restore)
        .onDisappear {
            if !handedOffCleanup, let directory = request.cleanupDirectory, !request.cleanupOnlyOnSuccess {
                try? FileManager.default.removeItem(at: directory)
            }
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
                    Button(audience.phrase.sentenceCased) {
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
                    Button(split.phrase.sentenceCased) { options.split = split }
                }
                Divider()
                Button("Custom…") { editingSplit = .sentence }
            }
            // Out of the words that were clicked, not down in More Options where it may be scrolled away.
            .popover(isPresented: isEditingSplit(from: .sentence), arrowEdge: .bottom) { splitEditor }
        }
    }

    private func isEditingSplit(from anchor: SplitEditorAnchor) -> Binding<Bool> {
        Binding(get: { editingSplit == anchor }, set: { if !$0, editingSplit == anchor { editingSplit = nil } })
    }

    private var splitEditor: some View {
        let estimate = report.estimatedSize
        // Starts from the size in use, so 700 MB can become 650 MB without retyping the unit.
        return SplitSizeEditor(initial: options.split) { size in
            let parts = size.parts(for: estimate)
            return parts > 1 ? String(localized: "About \(parts) parts for these items.")
                             : String(localized: "These items probably fit in one part.")
        } apply: { size in
            options.split = size
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

    private func middle(_ report: PackReport) -> some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            if options.usesPassword { passwordField }
            ReportView(report: report, audience: options.audience, overrides: $overrides, showDetails: $showDetails)
            moreOptions(report)
                .id(Self.moreOptionsID)
        }
    }

    // MARK: Password

    /// Typed twice or seen once: either way the person knows what they'll have to type to open it.
    private var passwordChecked: Bool {
        revealsPassword || seenPassword == password || confirmation == password
    }

    private var needsConfirmation: Bool { !revealsPassword && seenPassword != password }

    /// Only once the second entry has gone wrong — not while it's still a correct beginning.
    private var showsMismatch: Bool {
        guard needsConfirmation, !confirmation.isEmpty, confirmation != password else { return false }
        return !password.hasPrefix(confirmation) || focus != .confirmation
    }

    private var passwordField: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                Image(systemName: "key.fill").accessibilityHidden(true).foregroundStyle(.secondary)
                    .frame(width: 18)
                Group {
                    if revealsPassword {
                        TextField("Password", text: $password)
                            .autocorrectionDisabled()
                            .font(.body.monospaced()) // l, 1 and I read apart
                    } else {
                        SecureField("Password", text: $password)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .focused($focus, equals: .password)
                .onSubmit { if needsConfirmation { focus = .confirmation } }
                suggestButton
            }
            if needsConfirmation {
                HStack(spacing: Space.s) {
                    Color.clear.frame(width: 18, height: 1)
                    SecureField("Re-enter Password", text: $confirmation)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.large)
                        .focused($focus, equals: .confirmation)
                    // Same width as Suggest above, so both fields line up end to end.
                    suggestButton.hidden().accessibilityHidden(true)
                }
                .transition(.opacity)
            }
            if showsMismatch {
                Label {
                    Text("Passwords don’t match")
                } icon: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                }
                .font(.callout)
                .padding(.leading, 18 + Space.s)
                .transition(.opacity)
            }
            // The same option, in the same place, as the sheet that asks for a password to open one.
            Toggle("Show password", isOn: Binding(get: { revealsPassword }, set: setRevealsPassword))
                .padding(.leading, 18 + Space.s)
        }
        .animation(Motion.byKeyboard ? nil : Motion.resolved(Motion.status, reduceMotion: reduceMotion), value: needsConfirmation)
        .animation(Motion.byKeyboard ? nil : Motion.resolved(Motion.status, reduceMotion: reduceMotion), value: showsMismatch)
        // Slides down from the sentence that asked for it; goes faster than it came.
        .transition(AnyTransition.asymmetric(insertion: reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)),
                                removal: .opacity.animation(Motion.byKeyboard ? nil : Motion.resolved(Motion.exit, reduceMotion: reduceMotion))))
    }

    private var suggestButton: some View {
        Button("Suggest") {
            password = Self.suggestedPassword()
            confirmation = ""
            // A password nobody has seen is one nobody can type; show what was made.
            setRevealsPassword(true)
        }
        .controlSize(.large)
    }

    private func setRevealsPassword(_ reveals: Bool) {
        revealsPassword = reveals
        if reveals { seenPassword = password }
        // Swapping the secure field for a plain one would otherwise drop the caret.
        focus = .password
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

    /// What More Options is set to, so a closed section still says what it holds. The sentence
    /// already shows the password and parts, so they aren't repeated here; a purpose's usual
    /// choices go without saying, and only the ones changed from it are named.
    private var optionsSummary: String {
        var parts = [compressionSummary]
        if options.verify { parts.append(String(localized: "Tested after packing")) }
        if options.format == .dmg { parts.append(options.diskImageFilesystem.title) }
        if changesHelperFiles {
            parts.append(options.dropsMacHelperFiles
                ? String(localized: "No Mac support files")
                : String(localized: "Keeping Mac support files"))
        }
        if changesMacMetadata {
            parts.append(options.effectiveKeepsMacMetadata
                ? String(localized: "Storing Mac metadata")
                : String(localized: "No Mac metadata"))
        }
        if options.format == .sevenZip, options.usesPassword, !options.encryptFilenames {
            parts.append(String(localized: "File names visible"))
        }
        if let threads = options.threads {
            parts.append(threads == 1 ? String(localized: "1 CPU core") : String(localized: "\(threads) CPU cores"))
        }
        // Each item keeps its words together, so a second line never starts at "CPU cores".
        return parts.map { $0.replacingOccurrences(of: " ", with: "\u{00A0}") }.joined(separator: " · ")
    }

    // MARK: Changed from the purpose

    /// What Reset would bring back. Compression is remembered as it's chosen, so it's never
    /// "changed"; parts, Verify and the DMG layout come from Settings and the last pack.
    private var purposeDefaults: PackOptions {
        var defaults = options
        defaults.resetToPurposeDefaults()
        return defaults
    }

    private var changesHelperFiles: Bool { options.dropsMacHelperFiles != options.audience.dropsMacHelperFiles }

    private var changesMacMetadata: Bool {
        options.format == .zip && options.effectiveKeepsMacMetadata != options.audience.keepsMacMetadata
    }

    /// Something in More Options does other than the usual for this purpose. Compared by what it
    /// does, so a choice the current format ignores (file-name encryption for a ZIP) doesn't count.
    private var isCustomized: Bool {
        let defaults = purposeDefaults
        return options.level != defaults.level
            || options.verify != defaults.verify
            || options.split != defaults.split
            || changesHelperFiles
            || changesMacMetadata
            || (options.format == .sevenZip && options.usesPassword && !options.encryptFilenames)
            || options.threads != nil
            || options.diskImageFilesystem != defaults.diskImageFilesystem
            || options.diskImageApplicationsLink != defaults.diskImageApplicationsLink
    }

    /// Checkboxes for a purpose's defaults show what will happen; `PackOptions` decides what to store.
    private var includesHelperFiles: Binding<Bool> {
        Binding(get: { !options.dropsMacHelperFiles }, set: { options.setIncludesMacHelperFiles($0) })
    }

    private var storesMacMetadata: Binding<Bool> {
        Binding(get: { options.effectiveKeepsMacMetadata }, set: { options.setKeepsMacMetadata($0) })
    }

    private var compressionSummary: String {
        if options.format == .tarZst, options.level == .store {
            return String(localized: "\(CompressionLevel.fastest.title) compression") // zstd has no stored mode
        }
        guard options.format.isCompressed, options.level != .store else { return String(localized: "No compression") }
        return String(localized: "\(options.level.title) compression")
    }

    /// Part names come from `ArchiveCreation`: "Project.zip.001", "Project.zip.002", …
    private func splitCaption(_ report: PackReport) -> String? {
        guard options.format.supportsSplit else {
            return String(localized: "A \(options.format.displayName) is always one file")
        }
        guard options.split != .none else { return nil }
        let base = archiveName + "." + options.format.fileExtension
        guard report.parts > 1 else {
            return String(localized: "Probably fits in one part, \(base + ".001").")
        }
        return String(localized: "About \(report.parts) parts, \(base + ".001") to \(String(format: ".%03d", report.parts)). Opening it needs all of them.")
    }

    private var passwordCaption: String {
        guard options.format.supportsPassword else {
            return String(localized: "\(options.format.displayName) can’t be password-protected. Choose ZIP or 7Z to add one.")
        }
        guard options.usesPassword else { return String(localized: "Anyone with the file can open it and see the names inside.") }
        if options.format == .sevenZip {
            return options.encryptFilenames
                ? String(localized: "File names are hidden until the password is entered.")
                : String(localized: "File names stay visible; only the contents need the password.")
        }
        return String(localized: "File names stay visible without the password.")
    }

    /// Grouped by what each choice is about: what comes out (size, parts, checking), what a disk
    /// image looks like, who can read the names, what a Mac adds, and how hard the Mac works.
    /// Something people expect that a format can't do says why (a DMG is one file, a TAR has no
    /// password); a choice that only exists with one format (DMG layout, ZIP metadata, 7Z name
    /// encryption with a password) appears only with it.
    private func moreOptions(_ report: PackReport) -> some View {
        DisclosureGroup(isExpanded: $showMore) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Space.m, verticalSpacing: Space.l) {
                optionRow("Compression") {
                    Picker("Compression", selection: levelBinding) {
                        ForEach(CompressionLevel.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(!options.format.isCompressed)
                    caption(levelCaption)
                }
                // The same choices as the sentence's last words, bound to the same state.
                optionRow("Split archives") {
                    if options.format.supportsSplit {
                        Picker("Split archives", selection: splitPickerSelection) {
                            ForEach(SplitSize.allCases) { Text($0.phrase.sentenceCased).tag($0) }
                            if options.split.isCustom {
                                Text(options.split.phrase.sentenceCased).tag(options.split)
                            }
                            Divider()
                            Text("Custom…").tag(Self.customSplitTag)
                        }
                        .labelsHidden()
                        .fixedSize()
                        .popover(isPresented: isEditingSplit(from: .options), arrowEdge: .trailing) { splitEditor }
                    } else {
                        Text(SplitSize.none.phrase.sentenceCased)
                    }
                    if let text = splitCaption(report) { caption(text) }
                }
                optionRow("Verify") {
                    Toggle("Test every file once it’s packed", isOn: $options.verify)
                }

                if options.format == .dmg {
                    groupDivider
                    optionRow("Disk format") {
                        Picker("Disk format", selection: $options.diskImageFilesystem) {
                            ForEach(DiskImageFilesystem.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                        caption(options.diskImageFilesystem.detail)
                    }
                    optionRow("Layout") {
                        Toggle("Applications shortcut", isOn: $options.diskImageApplicationsLink)
                        caption(String(localized: "Adds a link to /Applications so people can drag apps in Finder."))
                    }
                }

                groupDivider
                // Who can see what. The password itself is chosen in the sentence; this says what it covers.
                optionRow("Password") {
                    if options.format == .sevenZip, options.usesPassword {
                        Toggle("Encrypt file names", isOn: $options.encryptFilenames)
                    }
                    caption(passwordCaption)
                }

                groupDivider
                optionRow("Mac support files") {
                    Toggle("Include .DS_Store and other Finder files", isOn: includesHelperFiles)
                    if changesHelperFiles { changedCaption }
                }
                if options.format == .zip {
                    optionRow("Mac metadata") {
                        Toggle("Store Finder tags and extended attributes", isOn: storesMacMetadata)
                        caption(String(localized: "They travel in a “__MACOSX” folder that a Mac reads back when extracting."))
                        if changesMacMetadata { changedCaption }
                    }
                }

                groupDivider
                optionRow("CPU cores") {
                    Picker("CPU cores", selection: $options.threads) {
                        Text(settingsCores).tag(Int?.none)
                        Divider()
                        ForEach(1...ProcessInfo.processInfo.activeProcessorCount, id: \.self) { n in
                            Text(n == 1 ? String(localized: "1 core") : String(localized: "\(n) cores")).tag(Int?.some(n))
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    caption(String(localized: "A limit is a request; some formats may still use fewer cores."))
                }
            }
            .padding(.top, Space.m)
            .padding(.leading, Space.xs)
        } label: {
            // Full-strength title, and the current settings beside it while closed: the section is
            // easy to find and says whether it's worth opening. The whole line opens it.
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text("More Options")
                    .fontWeight(.medium)
                if !showMore {
                    // Two lines at most: a changed choice is what's worth reading, and it comes last.
                    Text(optionsSummary)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(String(localized: "Set to \(optionsSummary)"))
                }
                Spacer(minLength: Space.m)
                // Only while something differs: a Reset that's always there says nothing. Short and
                // in the sentence's amber, like the other words here that change things; the summary
                // beside it keeps the room.
                if isCustomized {
                    Button {
                        options.resetToPurposeDefaults()
                    } label: {
                        Label("Reset", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.tint)
                    .fixedSize()
                    .help(String(localized: "Go back to the usual choices for \(options.audience.phrase)"))
                    .accessibilityLabel(String(localized: "Reset More Options"))
                    .accessibilityHint(String(localized: "Go back to the usual choices for \(options.audience.phrase)"))
                    .transition(.opacity)
                }
            }
            .contentShape(.rect)
            .onTapGesture {
                withAnimation(Motion.presence(!showMore, reduceMotion: reduceMotion)) { showMore.toggle() }
            }
        }
        .font(.callout)
    }

    /// Between groups: a hairline across both columns, inside the grid's own spacing.
    private var groupDivider: some View {
        Divider().gridCellUnsizedAxes(.horizontal)
    }

    /// Under a purpose choice someone changed: what Reset would undo.
    private var changedCaption: some View {
        Label {
            Text("Changed from the usual choice for \(options.audience.phrase).")
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: "pencil.circle.fill").foregroundStyle(.tint).accessibilityHidden(true)
        }
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The first CPU choice says what Settings › General is set to, not just that it exists.
    private var settingsCores: String {
        switch PackPreferences.threads {
        case nil: String(localized: "As in Settings (all cores)")
        case 1: String(localized: "As in Settings (1 core)")
        case let threads?: String(localized: "As in Settings (\(threads) cores)")
        }
    }

    private func optionRow(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            VStack(alignment: .leading, spacing: Space.xs) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
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
                .disabled(isChoosing || report.included.isEmpty || (options.usesPassword && (password.isEmpty || !passwordChecked)))
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
        // Settings › Passwords: visible by default also lets Chinese and Japanese input methods work.
        revealsPassword = SettingsKeys.flag(SettingsKeys.showPassword)
        // Design review: -StowPackDetails YES opens both disclosures.
        if UserDefaults.standard.bool(forKey: "StowPackDetails") { showDetails = true; showMore = true }
        // Design review: -StowPackPassword YES starts with "with a password" (formats that allow one).
        if UserDefaults.standard.bool(forKey: "StowPackPassword"), options.format.supportsPassword { options.usesPassword = true }
        // Design review: -StowPackPasswordReview mismatch|shown fills in a sample password in that state.
        switch UserDefaults.standard.string(forKey: "StowPackPasswordReview") {
        case "mismatch": password = "harbor-sample"; confirmation = "harbor-smaple"
        case "shown": password = "harbor-sample"; setRevealsPassword(true)
        default: break
        }
        // Design review: -StowPackMore YES opens More Options alone; -StowPackChanged YES changes two
        // choices from the purpose (support files, CPU cores); -StowPackSplitEditor sentence|options
        // opens the part-size editor from that control once the sheet is up.
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "StowPackMore") { showMore = true }
        if defaults.bool(forKey: "StowPackChanged") {
            options.includeMacHelperFiles = options.audience.dropsMacHelperFiles
            options.threads = min(2, ProcessInfo.processInfo.activeProcessorCount)
        }
        if let anchor = defaults.string(forKey: "StowPackSplitEditor") {
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                editingSplit = anchor == "options" ? .options : .sentence
            }
        }
    }

    private func setAudience(_ audience: Audience) {
        options.setAudience(audience)
        options.level = PackPreferences.level(for: audience)
    }

    /// The Custom… item's tag: no real size is negative.
    private static let customSplitTag = SplitSize(rawValue: -1)

    /// Presets and the custom size in use pick themselves; Custom… opens the editor beside the
    /// menu and leaves the menu showing what's in use until the editor's Use.
    private var splitPickerSelection: Binding<SplitSize> {
        Binding(
            get: { options.split },
            set: { chosen in
                if chosen == Self.customSplitTag { editingSplit = .options } else { options.split = chosen }
            }
        )
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
            let severalFolders = GatherDestination.sources(of: request.origins).count > 1
            guard let destination = await PackDestination.choose(for: fileName, startingAt: request.directory,
                                                                  severalFolders: severalFolders) else { return }
            GatherDestination.remember(destination, for: request.origins)
            var conflict = ArchiveCreation.Conflict.keepBoth
            if !ArchiveCreation.existing(named: archiveName, format: format, in: destination).isEmpty {
                var free = 2
                while !ArchiveCreation.existing(named: "\(archiveName) \(free)", format: format, in: destination).isEmpty { free += 1 }
                guard let choice = await PackDestination.resolveConflict(
                    fileName: fileName, keepBothName: "\(archiveName) \(free).\(format.fileExtension)", in: destination
                ) else { return }
                conflict = choice
            }
            let keepsMetadata = options.effectiveKeepsMacMetadata
            let cleanupDirectory = self.request.cleanupDirectory
            let cleanupOnlyOnSuccess = self.request.cleanupOnlyOnSuccess
            var request = CreateRequest(
                operationID: UUID().uuidString,
                archiveName: archiveName,
                format: format,
                level: options.level,
                password: options.usesPassword ? password : nil,
                volumeSize: options.split.isNone ? nil : options.split.rawValue,
                keepsMacMetadata: keepsMetadata,
                verify: options.verify,
                threads: options.effectiveThreads(global: PackPreferences.threads),
                diskImageFilesystem: format == .dmg ? options.diskImageFilesystem : .hfsPlus,
                diskImageApplicationsLink: format == .dmg && options.diskImageApplicationsLink
            )
            request.encryptFilenames = options.format == .sevenZip && options.encryptFilenames
            handedOffCleanup = true
            app.packing.start(.init(items: report.items, totalBytes: report.totalBytes, attributes: keepsMetadata,
                                    request: request, name: archiveName, destination: destination, conflict: conflict,
                                    cleanupDirectory: cleanupDirectory, cleanupOnlyOnSuccess: cleanupOnlyOnSuccess))
            dismiss()
        }
    }

    static func suggestedPassword() -> String {
        let alphabet = Array("abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return (0..<4).map { _ in String((0..<4).map { _ in alphabet.randomElement()! }) }.joined(separator: "-")
    }
}

/// Whether a scroll view has content past its top or bottom edge.
private struct ScrollEdges: Equatable {
    var above = false
    var below = false

    init() {}

    init(_ geometry: ScrollGeometry) {
        above = geometry.contentOffset.y > 1
        below = geometry.contentOffset.y + geometry.containerSize.height < geometry.contentSize.height - 1
    }
}

private extension String {
    /// `Audience` and `SplitSize` phrases sit inside the sentence; a menu item or label starts upper-case.
    var sentenceCased: String { prefix(1).uppercased() + dropFirst() }
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
            // The small chevron is the Mac's pull-down cue: it says "this word is a menu" without
            // a hover. It stays put while the word beside it blurs over to the new choice.
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(title)
                    .fontWeight(.semibold)
                    .id(title)
                    // Blur-replace scales a little, so Reduce Motion gets the cross-fade alone.
                    .transition(reduceMotion ? AnyTransition.opacity : AnyTransition(.blurReplace))
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.bold))
                    .opacity(contrastStyle.increased ? 1 : 0.6)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.tint)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.leading, 6)
        .padding(.trailing, 5)
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
