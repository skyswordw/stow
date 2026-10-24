import SwiftUI

/// Where an encrypted archive's password stands. The toolbar lock and the archive card read the
/// same state, so they never disagree.
///
/// `passwordAvailable` means a password has worked for at least one file — not that every file is
/// unlocked: a ZIP can use a different password for each entry.
enum ArchiveLockState: Equatable {
    case locked, checking, passwordAvailable

    init?(_ model: BrowserModel) {
        guard model.archive.isEncrypted else { return nil }
        if model.isUnlocking {
            self = .checking
        } else {
            self = model.level.password == nil ? .locked : .passwordAvailable
        }
    }
}

/// The title bar's password entry stays available when the sidebar or inspector is hidden.
///
/// While a password is being checked, a spinner takes the lock's place in the same button, so the
/// target never moves and clicking it again cancels (Handoff › Motion intent).
struct ArchiveUnlockControl: View {
    let model: BrowserModel

    var body: some View {
        switch ArchiveLockState(model) {
        case nil:
            EmptyView()
        case .checking:
            Button { model.cancelUnlocking() } label: {
                Label {
                    Text("Cancel Unlocking")
                } icon: {
                    ProgressView().controlSize(.small)
                }
            }
            .help("Checking the password — click to cancel")
        case .locked:
            Button(String(localized: "Unlock Archive…"), systemImage: "lock.fill") { model.unlockArchive() }
                .help("Enter the archive’s password to preview or extract files")
                .disabled(model.isListing)
        case .passwordAvailable:
            Button(String(localized: "Password Available"), systemImage: "lock.open.fill") { model.unlockArchive() }
                .help("A password is available for this archive. Individual files may still ask for a different password.")
                .disabled(model.isListing)
        }
    }
}

/// The archive card's lock line: says the archive is encrypted and offers the password right where
/// people look to learn what an archive is. The toolbar lock is icon-only and folds into the
/// overflow menu in narrow windows; this line stays put.
///
/// One line in every state, the icon in a fixed slot, so nothing below it jumps when the state changes.
struct ArchiveLockRow: View {
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var contrastStyle: ContrastStyle { .resolve(contrast) }
    let model: BrowserModel
    @State private var isHovering = false

    var body: some View {
        if let state = ArchiveLockState(model) {
            Group {
                if state == .passwordAvailable {
                    row(state)
                        .accessibilityElement(children: .combine)
                        .help("A password is available for this archive. Individual files may still ask for a different password.")
                } else {
                    Button {
                        state == .checking ? model.cancelUnlocking() : model.unlockArchive()
                    } label: {
                        row(state)
                    }
                    .buttonStyle(.plain)
                    .disabled(state == .locked && model.isListing)
                    .accessibilityLabel(state == .checking ? String(localized: "Checking password…")
                                        : String(localized: "Encrypted"))
                    .accessibilityValue(state == .checking ? "" : String(localized: "File names are visible; contents need the password."))
                    .accessibilityHint(state == .checking ? String(localized: "Cancel Unlocking") : String(localized: "Enter Password…"))
                    .help(state == .checking ? String(localized: "Checking the password — click to cancel")
                          : String(localized: "File names are visible; contents need the password."))
                }
            }
            // The state changes on its own (a check finishing), so it eases rather than springs.
            .animation(Motion.resolved(Motion.status, reduceMotion: reduceMotion), value: state)
        }
    }

    private func row(_ state: ArchiveLockState) -> some View {
        HStack(spacing: 6) {
            ZStack {
                if state == .checking {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: state == .locked ? "lock.fill" : "lock.open.fill")
                        .contentTransition(.symbolEffect(.replace))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 14)
            .accessibilityHidden(true)

            // A narrow sidebar keeps the action and drops the word: the lock already says “encrypted”.
            // Checking keeps its Cancel and shortens the words instead. Every option has content
            // for every state: an empty one would always "fit" and blank the line.
            ViewThatFits(in: .horizontal) {
                labelled(title(state), action: action(state))
                switch state {
                case .locked: labelled(nil, action: action(state))
                case .checking: labelled(String(localized: "Checking…"), action: action(state))
                case .passwordAvailable: labelled(title(state), action: nil)
                }
                // Last resort, narrower than any sidebar allows: one truncating line.
                Text(state == .locked ? action(state) ?? title(state) : title(state))
                    .font(.caption.weight(state == .locked ? .semibold : .medium))
                    .foregroundStyle(state == .locked ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, Space.s)
        .padding(.vertical, 6)
        .background(.primary.opacity(isHovering && state != .passwordAvailable ? 0.08 : 0.04),
                    in: .rect(cornerRadius: Radius.chip))
        .contentShape(.rect)
        .onHover { isHovering = $0 }
    }

    /// A title on the left and the action on the right, both at their full width (or one of them).
    private func labelled(_ title: String?, action: String?) -> some View {
        HStack(spacing: Space.xs) {
            if let title {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .fixedSize()
            }
            if let action {
                if title != nil { Spacer(minLength: Space.xs) }
                actionText(action).fixedSize()
            }
            if title == nil || action == nil { Spacer(minLength: 0) }
        }
    }

    private func actionText(_ action: String) -> some View {
        Text(action)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tint)
            .accessibilityHidden(true)
    }

    private func title(_ state: ArchiveLockState) -> String {
        switch state {
        case .locked: String(localized: "Encrypted")
        case .checking: String(localized: "Checking password…")
        case .passwordAvailable: String(localized: "Password available")
        }
    }

    private func action(_ state: ArchiveLockState) -> String? {
        switch state {
        case .locked: String(localized: "Enter Password…")
        case .checking: String(localized: "Cancel")
        case .passwordAvailable: nil
        }
    }
}
