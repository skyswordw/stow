import AppKit
import SwiftUI

/// One look for everything Stow stops to ask or tell: conflicts, signature warnings, replacing an
/// app, passwords, and failures. A symbol, what's being asked (or what happened) in one line, the
/// plain-words detail, anything the question needs (a field, a comparison, "do the same"), then
/// the choices on the right with the safe one on Return.
struct PromptCard<Content: View, Buttons: View>: View {
    let symbol: String
    var tint: Color?
    let title: String
    let message: String
    var footnote: String?
    /// A failure's code and the text "Copy Details" puts on the clipboard.
    var report: ErrorReport.Copyable?
    @ViewBuilder var content: Content
    @ViewBuilder var buttons: Buttons

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            HStack(alignment: .top, spacing: Space.m) {
                Image(systemName: symbol)
                    .font(.title)
                    .symbolRenderingMode(tint == nil ? .hierarchical : .monochrome)
                    .foregroundStyle(tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.tint))
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(title)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    if !message.isEmpty {
                        Text(message)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            content
            HStack(spacing: Space.s) {
                if let report {
                    CopyErrorDetails(report: report)
                }
                if let footnote {
                    Text(footnote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                buttons
            }
            .controlSize(.large)
        }
        .padding(Space.xl)
        .frame(width: 460)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

/// A question asked from code that waits for the answer (extraction, installs, packing).
struct Prompt {
    struct Choice {
        enum Role { case normal, cancel, primary }

        let title: String
        var role: Role = .normal
        /// A key for a `.normal` choice, like ⌘D for Don’t Save.
        var shortcut: KeyboardShortcut?
    }

    /// A name to type (Rename Archive). It opens focused with the base name selected, the
    /// extension left out, like Finder; Return answers the `.primary` choice, Escape the `.cancel` one.
    struct Field {
        var text: String
        var label: String
    }

    var symbol: String
    var tint: Color?
    var title: String
    var message: String
    /// Label–value rows under the message: "Existing · 1.2 MB, 3 Oct" / "Extracted · …".
    var details: [(label: String, value: String)] = []
    /// Left to right; the `.primary` one is the default (Return), the `.cancel` one answers Escape.
    var choices: [Choice]
    /// "Do the same for other files"; nil hides the checkbox.
    var suppression: String?
    /// A failure's code and copyable details; nil for questions.
    var report: ErrorReport.Copyable?
    var field: Field?

    struct Answer {
        /// Index into `choices`.
        let choice: Int
        let suppress: Bool
        /// What was in `field` when the choice was made.
        var text = ""
    }
}

struct PromptView: View {
    let prompt: Prompt
    let answer: (Prompt.Answer) -> Void
    @State private var suppress = false
    @State private var text: String

    init(prompt: Prompt, answer: @escaping (Prompt.Answer) -> Void) {
        self.prompt = prompt
        self.answer = answer
        _text = State(initialValue: prompt.field?.text ?? "")
    }

    var body: some View {
        PromptCard(symbol: prompt.symbol, tint: prompt.tint, title: prompt.title, message: prompt.message, report: prompt.report) {
            if !prompt.details.isEmpty || prompt.suppression != nil || prompt.field != nil {
                VStack(alignment: .leading, spacing: Space.m) {
                    if let field = prompt.field {
                        PromptNameField(text: $text, label: field.label,
                                        submit: { choose(prompt.choices.firstIndex { $0.role == .primary }) },
                                        cancel: { choose(prompt.choices.firstIndex { $0.role == .cancel }) })
                            .frame(height: 22)
                    }
                    if !prompt.details.isEmpty { details }
                    if let suppression = prompt.suppression {
                        Toggle(suppression, isOn: $suppress)
                    }
                }
                .padding(.leading, 32 + Space.m)
            }
        } buttons: {
            ForEach(prompt.choices.indices, id: \.self) { index in
                button(index)
            }
        }
        .background {
            // With no Cancel among the choices, Escape answers the safe default.
            if !prompt.choices.contains(where: { $0.role == .cancel }),
               let primary = prompt.choices.firstIndex(where: { $0.role == .primary }) {
                Button { choose(primary) } label: { EmptyView() }
                    .keyboardShortcut(.cancelAction)
                    .opacity(0)
                    .accessibilityHidden(true)
            }
        }
    }

    private var details: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Space.m, verticalSpacing: Space.xs) {
            ForEach(prompt.details.indices, id: \.self) { index in
                GridRow {
                    Text(prompt.details[index].label)
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    Text(prompt.details[index].value)
                        .monospacedDigit()
                }
            }
        }
        .font(.callout)
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.primary.opacity(0.05), in: .rect(cornerRadius: Radius.card))
    }

    private func choose(_ index: Int?) {
        guard let index else { return }
        answer(Prompt.Answer(choice: index, suppress: suppress, text: text))
    }

    @ViewBuilder
    private func button(_ index: Int) -> some View {
        let choice = prompt.choices[index]
        let action = { choose(index) }
        switch choice.role {
        case .primary:
            Button(choice.title, action: action)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.glassProminent)
        case .cancel:
            Button(choice.title, role: .cancel, action: action)
                .keyboardShortcut(.cancelAction)
        case .normal:
            Button(choice.title, action: action)
                .keyboardShortcut(choice.shortcut)
        }
    }
}

/// A native field, so it can open focused with the base name selected (SwiftUI's TextField
/// selects everything). Return and Escape go to the prompt's choices.
private struct PromptNameField: NSViewRepresentable {
    @Binding var text: String
    let label: String
    let submit: () -> Void
    let cancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.delegate = context.coordinator
        field.bezelStyle = .roundedBezel
        field.setAccessibilityLabel(label)
        field.placeholderString = label
        DispatchQueue.main.async { [weak field] in
            guard let field, let window = field.window else { return }
            window.makeFirstResponder(field)
            let stem = (field.stringValue as NSString).deletingPathExtension
            field.currentEditor()?.selectedRange = NSRange(location: 0, length: (stem as NSString).length)
        }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) { context.coordinator.parent = self }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PromptNameField
        init(_ parent: PromptNameField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSTextField { parent.text = field.stringValue }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)) { parent.submit(); return true }
            if selector == #selector(NSResponder.cancelOperation(_:)) { parent.cancel(); return true }
            return false
        }
    }
}

/// A failure, told the same way as every question: what happened, what to do, one action.
struct FailureCard: View {
    let failure: Failure
    /// Called with the failure's action, or nil for OK.
    let answer: (Failure.Action?) -> Void

    var body: some View {
        PromptView(prompt: Prompt(failure)) { reply in
            answer(failure.action != nil && reply.choice == 1 ? failure.action : nil)
        }
    }
}

extension Prompt {
    /// OK, plus the failure's own next step as the default when it has one.
    init(_ failure: Failure) {
        self.init(symbol: CheckupFinding.Severity.caution.symbol, tint: CheckupFinding.Severity.caution.color, title: failure.title, message: failure.advice,
                  choices: failure.action.map { [Choice(title: String(localized: "OK"), role: .cancel),
                                                 Choice(title: $0.title, role: .primary)] }
                      ?? [Choice(title: String(localized: "OK"), role: .primary)],
                  report: ErrorReport.Copyable(failure))
    }
}

// MARK: - Presenting

extension Prompts {
    /// Shows `prompt` as a sheet on Stow's window (or, with no window, on its own) and waits.
    /// Escape picks the `.cancel` choice.
    /// `window`, when given and free, takes the sheet instead of the front window.
    static func present(_ prompt: Prompt, on window: NSWindow? = nil) async -> Prompt.Answer {
        let preferred = window?.attachedSheet == nil ? window : nil
        return await withCheckedContinuation { continuation in
            let window = PromptWindow()
            var answered = false
            let parent = preferred ?? Self.sheetParent()
            window.contentViewController = NSHostingController(rootView: PromptView(prompt: prompt) { answer in
                guard !answered else { return }
                answered = true
                if let parent {
                    parent.endSheet(window)
                } else {
                    NSApp.stopModal()
                    window.orderOut(nil)
                }
                continuation.resume(returning: answer)
            })
            window.setContentSize(window.contentViewController?.view.fittingSize ?? CGSize(width: 460, height: 200))
            if let parent {
                parent.beginSheet(window)
                window.makeKey()
            } else {
                NSApp.activate()
                window.center()
                NSApp.runModal(for: window)
            }
        }
    }

    /// Tells people about `failure`; returns its action if they chose it.
    static func explain(_ failure: Failure) async -> Failure.Action? {
        let answer = await present(Prompt(failure))
        return failure.action != nil && answer.choice == 1 ? failure.action : nil
    }

    /// Stow's front window, when it can take a sheet. An app-modal prompt would stop everything
    /// else (progress, the batch queue) until it's answered.
    static func sheetParent() -> NSWindow? {
        let window = [NSApp.keyWindow, NSApp.mainWindow].compactMap(\.self).first { !($0 is NSPanel) }
            ?? NSApp.windows.first { $0.isVisible && !($0 is NSPanel) && $0.sheetParent == nil }
        return window?.attachedSheet == nil ? window : nil
    }
}

/// The window a prompt sits in: a sheet's plain panel, or a small titled window when Stow has none.
private final class PromptWindow: NSWindow {
    init() {
        super.init(contentRect: CGRect(x: 0, y: 0, width: 460, height: 200),
                   styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: true)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }

    override var canBecomeKey: Bool { true }
}
