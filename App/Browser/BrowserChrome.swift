import SwiftUI

/// Sizes shared by the Browser's floating glass, so the navigation capsule, Search, the archive's
/// controls and Actions read as one family: the same capsule, the same inset, buttons concentric
/// inside it (button radius + inset = capsule radius).
enum FloatingGlass {
    /// The navigation capsule and Search.
    static let barHeight: CGFloat = 36
    static let barInset: CGFloat = 3
}

/// The row over the top of the files (#160): Back, Forward and Up beside where you are, in one
/// glass capsule, and Search on the trailing side. Everything for getting around, beside the files
/// it works on.
struct BrowserNavigation: View {
    @Bindable var model: BrowserModel
    var isSearchFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: Space.s) {
            HStack(spacing: 0) {
                navigationButton(String(localized: "Back"), "chevron.left", help: String(localized: "See the previous place"),
                                 enabled: model.canGoBack) { model.goBack() }
                navigationButton(String(localized: "Forward"), "chevron.right", help: String(localized: "See the next place"),
                                 enabled: model.canGoForward) { model.goForward() }
                navigationButton(String(localized: "Enclosing Folder"), "arrow.up", help: String(localized: "See the folder this one is in"),
                                 enabled: model.canGoUp) { model.goUp() }
                Rectangle()
                    .fill(.separator)
                    .frame(width: 1, height: 16)
                    .padding(.horizontal, Space.xs)
                    .accessibilityHidden(true)
                Breadcrumbs(model: model)
                    .padding(.trailing, Space.xs)
            }
            .padding(FloatingGlass.barInset)
            .frame(height: FloatingGlass.barHeight)
            .accessibleGlass(in: .capsule)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(String(localized: "Navigation"))
            .layoutPriority(1)

            Spacer(minLength: 0)

            ArchiveSearchField(model: model, isFocused: isSearchFocused)
                .frame(minWidth: 150, idealWidth: 220, maxWidth: 240)
        }
        .padding(.horizontal, Space.m)
        .padding(.top, Space.xs)
        .padding(.bottom, Space.s)
    }

    private func navigationButton(_ title: String, _ symbol: String, help: String, enabled: Bool,
                                  action: @escaping () -> Void) -> some View {
        Button(title, systemImage: symbol, action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(ActionButtonStyle(iconOnly: true, height: FloatingGlass.barHeight - 2 * FloatingGlass.barInset))
            .accessibilityLabel(title)
            .help(help)
            .disabled(!enabled)
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
        .padding(.horizontal, Space.m)
        .frame(height: FloatingGlass.barHeight)
        .accessibleGlass(in: .capsule)
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

/// The whole archive's controls, floating at the bottom's leading edge: Glance, then Extract All,
/// in one glass capsule. Extract All is the window's primary action until Actions shows, whose
/// front button then carries the accent; it keeps its place and words either way. Glance itself
/// shows Extract All alone this way beside Actions, with no `glance` button.
struct ArchiveActions: View {
    let model: BrowserModel
    let prominent: Bool
    var glance: (() -> Void)?

    var body: some View {
        HStack(spacing: 2) {
            if let glance {
                Button(String(localized: "Glance"), systemImage: "arrow.down.right.and.arrow.up.left", action: glance)
                    .labelStyle(.iconOnly)
                    .buttonStyle(ActionButtonStyle(iconOnly: true))
                    .accessibilityLabel(String(localized: "Glance"))
                    .help("Switch to Glance, a small window — same folder, selection and history")
            }

            Button {
                model.extractAll()
            } label: {
                Label("Extract All", systemImage: "arrow.down.to.line")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(ActionButtonStyle(prominent: prominent))
            .help("Extract everything to a folder you choose")
        }
        .padding(ActionButtonStyle.inset)
        .accessibleGlass(in: .capsule)
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Archive"))
    }
}
