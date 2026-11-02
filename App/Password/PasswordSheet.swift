import SwiftUI

/// "“Handoff.7z” is locked." Asks for the password in plain words; a rejected one says so and asks again.
/// The full window shows it as a sheet; Glance, narrower than the sheet, as a card in the window
/// (`inWindowPasswordCard`). Same words, field, keys and answers in both.
struct PasswordSheet: View {
    let question: PasswordPrompt.Question
    /// The sheet's 460 pt, or nil to fit Glance (`PromptCard.width`).
    var width: CGFloat? = 460
    let answer: (String?) -> Void
    @State private var password = ""
    @State private var showsPassword = SettingsKeys.flag(SettingsKeys.showPassword)
    @FocusState private var isFocused: Bool

    var body: some View {
        PromptCard(symbol: "lock.fill", title: String(localized: "“\(question.archiveName)” is locked"),
                   message: explanation, footnote: footnote, width: width) {
            VStack(alignment: .leading, spacing: Space.s) {
                Group {
                    if showsPassword {
                        TextField("Password", text: $password)
                    } else {
                        SecureField("Password", text: $password)
                    }
                }
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .focused($isFocused)
                    .onSubmit(submit)
                // Right under the field it is about, before the Show password option.
                if question.isRetry {
                    Label("That password didn’t work. Check for typos and Caps Lock, then try again.",
                          systemImage: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Toggle("Show password", isOn: $showsPassword)
                    .onChange(of: showsPassword) { isFocused = true }
                    .padding(.top, question.isRetry ? Space.xs : 0)
            }
            .padding(.leading, 32 + Space.m)
        } buttons: {
            Button("Cancel", role: .cancel) { answer(nil) }
                .keyboardShortcut(.cancelAction)
            Button(submitTitle, action: submit)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.glassProminent)
                .disabled(password.isEmpty)
        }
        .onAppear { isFocused = true }
    }

    private var explanation: String {
        switch question.purpose {
        case .open: String(localized: "Its list of files is encrypted. Enter the password to see what’s inside.")
        case .extract: String(localized: "Its files are encrypted. Enter the password to extract them.")
        // Asked from an archive whose file names are already showing: say they stay browsable.
        case .unlock: String(localized: "You can browse its file names. Enter the password to preview or extract the files.")
        }
    }

    private var submitTitle: String {
        switch question.purpose {
        case .open: String(localized: "Open")
        case .extract: String(localized: "Extract")
        case .unlock: String(localized: "Unlock")
        }
    }

    private var footnote: String {
        if ArchivePasswordVault.isEnabled {
            String(localized: "If this unlocks it, Stow saves the password in your Keychain for next time.")
        } else {
            String(localized: "Stow keeps it only while this archive is open.")
        }
    }

    private func submit() {
        guard !password.isEmpty else { return }
        answer(password)
    }
}

extension View {
    /// Glance's way to ask (#104): the same question as a card in the middle of the window, over
    /// everything else dimmed, as ArcZip's Mini asks. The 460-pt sheet is wider than Glance
    /// (440 pt, 400 at the least) and a borderless window has no title bar for it to drop from.
    /// It answers exactly as the sheet does: Return submits, Escape or Cancel cancels, and the
    /// window behind takes no clicks until it's answered.
    func inWindowPasswordCard(_ prompt: PasswordPrompt) -> some View {
        modifier(InWindowPasswordCard(prompt: prompt))
    }

    /// Presents `prompt`'s questions as a sheet. Closing it any other way cancels the question.
    /// `isActive` false leaves the question to another window, which answers it there.
    func passwordSheet(_ prompt: PasswordPrompt, isActive: Bool = true) -> some View {
        sheet(item: Binding(
            get: { isActive ? prompt.question : nil },
            set: { if $0 == nil, isActive, let question = prompt.question { prompt.answer(nil, to: question.id) } }
        )) { question in
            PasswordSheet(question: question) { prompt.answer($0, to: question.id) }
        }
    }
}

private struct InWindowPasswordCard: ViewModifier {
    let prompt: PasswordPrompt
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let question = prompt.question
        content
            // As under a sheet: nothing behind it takes a click, the keyboard or VoiceOver's cursor.
            .disabled(question != nil)
            .accessibilityHidden(question != nil)
            .overlay {
                ZStack {
                    if let question {
                        Rectangle()
                            .fill(.black.opacity(colorScheme == .dark ? 0.36 : 0.2))
                            .contentShape(.rect)
                            .onTapGesture {}
                            .accessibilityHidden(true)
                            // Over the header too, where the title bar would be.
                            .ignoresSafeArea()
                            .transition(.opacity)
                        PasswordSheet(question: question, width: nil) { prompt.answer($0, to: question.id) }
                            .background(Color(nsColor: .windowBackgroundColor), in: .rect(cornerRadius: Radius.windowPanel))
                            .overlay {
                                RoundedRectangle(cornerRadius: Radius.windowPanel)
                                    .strokeBorder(.primary.opacity(ContrastStyle.resolve(contrast).increased ? 0.45 : 0.1))
                                    .allowsHitTesting(false)
                            }
                            .shadow(color: .black.opacity(0.22), radius: 24, y: 10)
                            .padding(GlanceLayout.inset)
                            .id(question.id)
                            // Asked for: it springs up a little, out of the window. Asked again after a
                            // wrong password: it only fades back, so a retry doesn't look like a new start.
                            .transition(question.isRetry || reduceMotion
                                        ? .opacity
                                        : .asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.96)),
                                                      removal: .opacity))
                            // Closing the window answers it, as closing a sheet's window does.
                            .onDisappear { prompt.answer(nil, to: question.id) }
                    }
                }
                // A click springs it in; it eases out; Return, Escape and Space-to-preview change it
                // at once (DESIGN.md › Motion).
                .animation(Motion.presence(question != nil, reduceMotion: reduceMotion), value: question?.id)
            }
    }
}
