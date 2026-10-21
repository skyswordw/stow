import SwiftUI

/// "“Handoff.7z” is locked." Asks for the password in plain words; a rejected one says so and asks again.
struct PasswordSheet: View {
    let question: PasswordPrompt.Question
    let answer: (String?) -> Void
    @State private var password = ""
    @State private var showsPassword = SettingsKeys.flag(SettingsKeys.showPassword)
    @FocusState private var isFocused: Bool

    var body: some View {
        PromptCard(symbol: "lock.fill", title: String(localized: "“\(question.archiveName)” is locked"),
                   message: explanation, footnote: String(localized: "Stow keeps it only while this archive is open.")) {
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
                Toggle("Show password", isOn: $showsPassword)
                    .onChange(of: showsPassword) { isFocused = true }
                if question.isRetry {
                    Label("That password didn’t work. Check for typos and Caps Lock, then try again.",
                          systemImage: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                        .font(.callout)
                }
            }
            .padding(.leading, 32 + Space.m)
        } buttons: {
            Button("Cancel", role: .cancel) { answer(nil) }
                .keyboardShortcut(.cancelAction)
            Button(question.purpose == .open ? String(localized: "Open") : String(localized: "Extract"), action: submit)
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
        }
    }

    private func submit() {
        guard !password.isEmpty else { return }
        answer(password)
    }
}

extension View {
    /// Presents `prompt`'s questions as a sheet. Closing it any other way cancels the question.
    func passwordSheet(_ prompt: PasswordPrompt) -> some View {
        sheet(item: Binding(
            get: { prompt.question },
            set: { if $0 == nil, let question = prompt.question { prompt.answer(nil, to: question.id) } }
        )) { question in
            PasswordSheet(question: question) { prompt.answer($0, to: question.id) }
        }
    }
}
