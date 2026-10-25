import SwiftUI

/// The row above the files (#160): the folder list's toggle, Back, Forward and Up, where you are,
/// Search, and the preview's toggle. Everything for getting around sits here, beside the files it
/// works on, so it all stays in reach with both optional panes closed.
struct BrowserHeader: View {
    @Bindable var model: BrowserModel
    @Binding var showsFolders: Bool
    var isSearchFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: Space.s) {
            PaneToggle(title: String(localized: "Folders"), systemImage: "sidebar.left", isOn: $showsFolders,
                       help: showsFolders ? String(localized: "Hide the folder list") : String(localized: "Show the folder list"))
                .keyboardShortcut("s", modifiers: [.control, .command])

            HStack(spacing: 0) {
                navigationButton(String(localized: "Back"), "chevron.left", help: String(localized: "See the previous place"),
                                 enabled: model.canGoBack) { model.goBack() }
                navigationButton(String(localized: "Forward"), "chevron.right", help: String(localized: "See the next place"),
                                 enabled: model.canGoForward) { model.goForward() }
                navigationButton(String(localized: "Enclosing Folder"), "arrow.up", help: String(localized: "See the folder this one is in"),
                                 enabled: model.canGoUp) { model.goUp() }
            }

            Breadcrumbs(model: model)
                .frame(maxWidth: .infinity, alignment: .leading)

            ArchiveSearchField(model: model, isFocused: isSearchFocused)
                .frame(minWidth: 120, idealWidth: 200, maxWidth: 220)

            PaneToggle(title: String(localized: "Preview"), systemImage: "sidebar.right", isOn: $model.showInspector,
                       help: model.showInspector ? String(localized: "Hide the preview") : String(localized: "Show the preview"))
                .keyboardShortcut("i", modifiers: [.command, .option])
        }
        .controlSize(.regular)
        .padding(.horizontal, Space.m)
        .frame(height: BrowserHeader.height)
        .accessibleBar()
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Navigation"))
    }

    static let height: CGFloat = 40

    private func navigationButton(_ title: String, _ symbol: String, help: String, enabled: Bool,
                                  action: @escaping () -> Void) -> some View {
        Button(title, systemImage: symbol, action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.accessoryBar)
            .accessibilityLabel(title)
            .help(help)
            .disabled(!enabled)
    }
}

/// A pane's show/hide button: its name beside the icon, so it reads without a hover, and lit
/// while the pane is open. A key press switches the pane at once; a click lets it slide.
private struct PaneToggle: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool
    let help: String

    var body: some View {
        Toggle(isOn: Binding {
            isOn
        } set: { shown in
            withTransaction(Motion.keyboardAware) { isOn = shown }
        }) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
        }
        .toggleStyle(.button)
        .buttonStyle(.accessoryBar)
        .help(help)
    }
}

/// Search, beside the files it searches. Esc clears it, then hands the keyboard back.
struct ArchiveSearchField: View {
    @Bindable var model: BrowserModel
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(prompt, text: $model.query, prompt: Text(prompt))
                .textFieldStyle(.plain)
                .focused(isFocused)
                .accessibilityLabel(String(localized: "Search"))
                .onKeyPress(.escape) {
                    if model.query.isEmpty { isFocused.wrappedValue = false } else { model.query = "" }
                    return .handled
                }
            if !model.query.isEmpty {
                Button(String(localized: "Clear Search"), systemImage: "xmark.circle.fill") { model.query = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(String(localized: "Clear Search"))
                    .help(String(localized: "Clear Search"))
            }
        }
        .padding(.horizontal, Space.s)
        .frame(height: 26)
        .background(.primary.opacity(0.06), in: .capsule)
        .overlay {
            Capsule().strokeBorder(Color.accentColor.opacity(isFocused.wrappedValue ? 0.6 : 0), lineWidth: 1.5)
                .allowsHitTesting(false)
        }
    }

    private var prompt: String {
        model.indexingProgress ?? String(localized: "Search \(model.archive.files.count) files")
    }
}

/// The title bar's title: the archive's name with a chevron, what it is underneath, and a menu
/// for the archive as a whole (Archive Info, Show in Finder, Rename, Close).
struct ArchiveTitleMenu<Items: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let items: Items
    @State private var isHovering = false

    var body: some View {
        Menu {
            items
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: Space.xs) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: 360, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.primary.opacity(isHovering ? 0.06 : 0), in: .rect(cornerRadius: 6))
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { isHovering = $0 }
        .help(title)
        .accessibilityLabel(title)
        .accessibilityValue(subtitle)
        .accessibilityHint(String(localized: "Archive Info, Show in Finder, Rename and Close"))
    }
}

/// The row under the files: Glance, how much is here or selected, and Extract All — the one action
/// for the whole archive, at the window's trailing edge whatever is selected.
struct BrowserStatusBar: View {
    let model: BrowserModel
    /// Actions is up with its own Extract for the selection, so Extract All steps back.
    let selectionHasActions: Bool
    let glance: () -> Void

    var body: some View {
        HStack(spacing: Space.m) {
            Button(action: glance) {
                Label("Glance", systemImage: "arrow.down.right.and.arrow.up.left")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.accessoryBar)
            .accessibilityLabel(String(localized: "Glance"))
            .help("Switch to Glance, a small window — same folder, selection and history")

            Text(model.statusText)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .liveNumber()

            Spacer(minLength: Space.s)

            Button {
                model.extractAll()
            } label: {
                Label("Extract All", systemImage: "arrow.down.to.line")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(ExtractAllStyle(prominent: !selectionHasActions))
            .help("Extract everything to a folder you choose")
        }
        .controlSize(.regular)
        .padding(.horizontal, Space.m)
        .frame(height: BrowserStatusBar.height)
        .accessibleBar()
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .contain)
    }

    static let height: CGFloat = 40
}

/// Extract All is the window's primary action until a selection brings up Actions, whose own
/// Extract then carries the accent: one prominent extraction at a time, scoped by where it sits.
/// The button keeps its place and its words either way; only the emphasis moves.
private struct ExtractAllStyle: PrimitiveButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        if prominent {
            Button(configuration).buttonStyle(.borderedProminent)
        } else {
            Button(configuration).buttonStyle(.bordered)
        }
    }
}
