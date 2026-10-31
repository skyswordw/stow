import SwiftUI

/// Sizes shared by the Browser's floating glass, so the navigation capsule, the archive's
/// controls and Actions read as one family: the same capsule, the same inset, buttons concentric
/// inside it (button radius + inset = capsule radius).
enum FloatingGlass {
    /// The navigation capsule.
    static let barHeight: CGFloat = 36
    static let barInset: CGFloat = 3
}

/// The row over the top of the files (#160): Back, Forward and Up beside where you are, in one
/// glass capsule. Search lives in the title bar (#215), so a deep path has the whole row.
struct BrowserNavigation: View {
    @Bindable var model: BrowserModel

    var body: some View {
        HStack(spacing: Space.s) {
            NavigationCapsule(model: model)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.m)
        .padding(.top, Space.xs)
        .padding(.bottom, Space.s)
    }
}

/// Back, Forward and Up beside where you are, in one glass capsule: the Browser's and Glance's
/// way around an archive. A short path takes only its width; a deep one scrolls and fades at its start.
struct NavigationCapsule: View {
    let model: BrowserModel

    var body: some View {
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

/// The whole archive's controls, floating at the bottom's leading edge: the way to the archive's
/// other window, then Extract All, in one glass capsule. The full window offers Glance there and
/// Glance offers the full window, so switching is in the same place in both. Extract All is the
/// window's primary action until Actions shows, whose front button then carries the accent; it
/// keeps its place and words either way.
struct ArchiveActions: View {
    let model: BrowserModel
    let prominent: Bool
    var switchTo: WindowSwitch?

    /// Where the leading button takes the archive.
    enum WindowSwitch {
        case glance(() -> Void)
        case fullWindow(() -> Void)
    }

    var body: some View {
        HStack(spacing: 2) {
            switch switchTo {
            case .glance(let action):
                switchButton(String(localized: "Glance"), "arrow.down.right.and.arrow.up.left",
                             help: String(localized: "Switch to Glance, a small window — same folder, selection and history"),
                             action: action)
            case .fullWindow(let action):
                switchButton(String(localized: "Open in Full Window"), "arrow.up.left.and.arrow.down.right",
                             help: String(localized: "Show this archive in the full window — same folder, selection and history"),
                             action: action)
            case nil:
                EmptyView()
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
    }

    private func switchButton(_ title: String, _ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(title, systemImage: symbol, action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(ActionButtonStyle(iconOnly: true))
            .accessibilityLabel(title)
            .help(help)
    }
}
