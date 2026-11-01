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
    /// Glance has no Search beside it, so its capsule runs the window's width.
    var fillsWidth = false

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
            if fillsWidth { Spacer(minLength: 0) }
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
    /// The Browser narrows it so Search keeps its room (#231); a long name truncates in the middle.
    var maxWidth: CGFloat = 360
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
            .frame(maxWidth: maxWidth, alignment: .leading)
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
/// other window, then Extract All, in one glass capsule. The full window offers Glance there;
/// Glance has Open in Full Window among its own window controls just before it, so switching is
/// still bottom left in both. Extract All is the
/// window's primary action until Actions shows, whose front button then carries the accent; it
/// keeps its place and words either way.
struct ArchiveActions: View {
    let model: BrowserModel
    let prominent: Bool
    var switchTo: WindowSwitch?
    /// Extract All as its icon alone, for a row without room for its words (Glance at its smallest
    /// with Actions showing). Its name stays its accessibility label and help.
    var compact = false

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
                    .labelStyle(compact ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))
            }
            .buttonStyle(ActionButtonStyle(prominent: prominent, iconOnly: compact))
            .accessibilityLabel(String(localized: "Extract All"))
            .help(model.extractAllUnavailableReason ?? String(localized: "Extract everything to a folder you choose"))
            .disabled(model.extractAllUnavailableReason != nil)
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

/// The files hold the keyboard unless Search does (#215). Two moments need help with the toolbar
/// search field: when it lets go (Esc, or a click away), and when the window first becomes key,
/// where AppKit makes the field the first responder without telling SwiftUI's focus state.
private struct FilesTakeKeyboard: ViewModifier {
    var isFocused: FocusState<Bool>.Binding
    var isSearchFocused: Binding<Bool>
    @State private var window: NSWindow?
    @State private var tookInitialFocus = false

    func body(content: Content) -> some View {
        content
            // Search's field is hosted by the toolbar, outside this view's focus system (#231),
            // so the files let go explicitly when it takes the keyboard.
            .onChange(of: isSearchFocused.wrappedValue) { _, searching in
                isFocused.wrappedValue = !searching
            }
            .background { WindowReader { window = $0 } }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
                guard !tookInitialFocus, let window, note.object as? NSWindow === window else { return }
                tookInitialFocus = true
                guard !isSearchFocused.wrappedValue else { return }
                // Re-assert: SwiftUI may already think the files have it.
                isFocused.wrappedValue = false
                DispatchQueue.main.async { isFocused.wrappedValue = true }
            }
    }
}

extension View {
    func filesTakeKeyboard(_ isFocused: FocusState<Bool>.Binding, isSearchFocused: Binding<Bool>) -> some View {
        modifier(FilesTakeKeyboard(isFocused: isFocused, isSearchFocused: isSearchFocused))
    }
}

/// Search in the middle of the title bar, over the files it searches (#231).
///
/// The system's toolbar search field always settles at the window's trailing end, over Details,
/// so this is the Browser's own field in the toolbar's capsule. It keeps the system field's
/// contracts (#215): the same query and results, ⌘F and a click reach the same field, and Esc
/// clears it and hands the keyboard back to the files in one step (`filesTakeKeyboard` does the
/// handing back when focus leaves).
struct ToolbarSearchField: View {
    @Binding var query: String
    let prompt: String
    /// The Browser's copy of whether Search has the keyboard; setting it moves the keyboard.
    @Binding var isFocused: Bool
    /// Bumped by ⌘F and the collapsed button: put the keyboard in the field, even if it has it.
    let focusRequest: Int
    /// From `TitleBarLayout`: the toolbar sizes items at their ideal width, so the field is told
    /// how wide to be rather than left to shrink. Below `TitleBarLayout.fieldMinimum` it's a button.
    let width: CGFloat
    /// Widens a collapsed Search and puts the keyboard in it.
    let activate: () -> Void

    var body: some View {
        if width < TitleBarLayout.fieldMinimum {
            Button("Search", systemImage: "magnifyingglass", action: activate)
                .labelStyle(.iconOnly)
                .help("Search")
                .frame(width: width)
        } else {
            Field(query: $query, prompt: prompt, isFocused: $isFocused, focusRequest: focusRequest)
                .frame(width: width)
        }
    }

    private struct Field: View {
        @Binding var query: String
        let prompt: String
        @Binding var isFocused: Bool
        let focusRequest: Int
        /// Focus state has to live in the toolbar item's own view: a `FocusState` in the
        /// Browser doesn't reach a field the toolbar hosts.
        @FocusState private var hasKeyboard: Bool

        var body: some View {
            HStack(spacing: Space.xs + 2) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Search", text: $query, prompt: Text(prompt))
                    .textFieldStyle(.plain)
                    .foregroundStyle(.primary)
                    .focused($hasKeyboard)
                    // Esc clears and lets go in one step, as the system field did. A plain text
                    // field's editor would take Esc as "complete", so it's caught first.
                    .onKeyPress(.escape) {
                        query = ""
                        hasKeyboard = false
                        isFocused = false
                        anchor.releaseField()
                        return .handled
                    }
                if !query.isEmpty {
                    Button("Clear Search", systemImage: "xmark.circle.fill") {
                        query = ""
                        takeKeyboard()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Clear Search")
                }
            }
            .padding(.horizontal, Space.m)
            // The whole capsule takes the click, not only the text.
            .contentShape(.capsule)
            .onTapGesture { takeKeyboard() }
            .background { anchor }
            .onChange(of: hasKeyboard) { _, has in if isFocused != has { isFocused = has } }
            .onChange(of: isFocused, initial: true) { _, wants in
                if hasKeyboard != wants { hasKeyboard = wants }
                // While a native table holds the keyboard, SwiftUI's focus doesn't cross into the
                // toolbar's hosting view; AppKit hands it over directly.
                if wants { DispatchQueue.main.async { anchor.focusField() } }
            }
            .onChange(of: focusRequest) { takeKeyboard() }
        }

        private func takeKeyboard() {
            hasKeyboard = true
            DispatchQueue.main.async { anchor.focusField() }
        }

        @State private var anchor = FieldAnchor()
    }
}

/// Finds the toolbar item's text field from inside it, so it can be made first responder.
private struct FieldAnchor: NSViewRepresentable {
    private let box = Box()

    private final class Box {
        weak var view: NSView?
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        box.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}

    @MainActor func focusField() {
        guard let field = ownField(), let window = field.window else { return }
        if (window.firstResponder as? NSText)?.delegate !== field { window.makeFirstResponder(field) }
    }

    /// Lets go of the keyboard if this item's field has it; the files then take it back.
    @MainActor func releaseField() {
        guard let field = ownField(), let window = field.window,
              (window.firstResponder as? NSText)?.delegate === field else { return }
        window.makeFirstResponder(nil)
    }

    /// The item's own field: in the closest ancestor (the toolbar item's hosting view) that holds one.
    @MainActor private func ownField() -> NSTextField? {
        var ancestor = box.view?.superview
        // Never past the title bar, into the window's content (a rename field, say).
        let frame = box.view?.window?.contentView?.superview
        while let current = ancestor, current !== frame {
            if let field = Self.editableField(in: current) { return field }
            ancestor = current.superview
        }
        return nil
    }

    private static func editableField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable { return field }
        for subview in view.subviews {
            if let field = editableField(in: subview) { return field }
        }
        return nil
    }
}

/// How the files' part of the title bar is shared between the archive's name and Search (#231).
/// The view and editing controls sit over Details and don't take from it.
nonisolated struct TitleBarLayout: Equatable, Sendable {
    var searchWidth: CGFloat
    var titleMaxWidth: CGFloat
    /// An encrypted archive's password control, after the name: "Enter Password…" while there's
    /// room, the lock alone when there isn't (its help and accessibility label still say it).
    var unlockShowsTitle: Bool

    static let fieldMinimum: CGFloat = 150
    static let fieldMaximum: CGFloat = 300
    static let titleMinimum: CGFloat = 120
    /// A collapsed Search: a round button the size of the toolbar's others.
    static let buttonWidth: CGFloat = 32
    static let unlockTitled: CGFloat = 170
    static let unlockIcon: CGFloat = 44

    /// - Parameters:
    ///   - filesWidth: the files area's width, which the title bar's leading part spans.
    ///   - isSearchActive: Search has the keyboard or a query. A narrow window then gives Search
    ///     its field back and shortens the archive's name instead, as the system field did.
    ///   - isEncrypted: the password control shares the room too.
    init(filesWidth: CGFloat, isSearchActive: Bool, isEncrypted: Bool = false) {
        // Window controls, the toolbar's margins, its capsules' padding and the spaces around Search.
        var room = max(0, filesWidth - 190)
        let comfortable = Self.fieldMinimum + Self.titleMinimum + 40
        unlockShowsTitle = isEncrypted && room >= comfortable + Self.unlockTitled
        if isEncrypted { room -= unlockShowsTitle ? Self.unlockTitled : Self.unlockIcon }
        if room >= comfortable {
            searchWidth = min(max(room * 0.48, Self.fieldMinimum), Self.fieldMaximum)
            titleMaxWidth = min(room - searchWidth, 360)
        } else if isSearchActive {
            searchWidth = Self.fieldMinimum
            titleMaxWidth = max(room - searchWidth, 60)
        } else {
            searchWidth = Self.buttonWidth
            titleMaxWidth = max(room - searchWidth, Self.titleMinimum)
        }
    }
}
