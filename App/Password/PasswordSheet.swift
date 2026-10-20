import SwiftUI

/// "“Handoff.7z” is locked." Asks for the password in plain words; a rejected one says so and asks again.
struct PasswordSheet: View {
    let question: PasswordPrompt.Question
    let answer: (String?) -> Void
    @State private var password = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            HStack(alignment: .top, spacing: Space.m) {
                Image(systemName: "lock.fill")
                    .font(.title)
                    .foregroundStyle(.tint)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("“\(question.archiveName)” is locked")
                        .font(.headline)
                    Text(explanation)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: Space.s) {
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .focused($isFocused)
                    .onSubmit(submit)
                if question.isRetry {
                    Label("That password didn’t work. Check it and try again.",
                          systemImage: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                        .font(.callout)
                }
            }

            HStack {
                Text("Stow keeps it only while this archive is open.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { answer(nil) }
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.large)
                Button(question.purpose == .open ? "Open" : "Extract", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .disabled(password.isEmpty)
            }
        }
        .padding(Space.xl)
        .frame(width: 440)
        .onAppear { isFocused = true }
    }

    private var explanation: String {
        switch question.purpose {
        case .open: "Its list of files is encrypted. Enter the password to see what’s inside."
        case .extract: "Its files are encrypted. Enter the password to extract them."
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
