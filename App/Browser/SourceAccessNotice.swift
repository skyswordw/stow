import SwiftUI

/// The archive opened, but Stow couldn't save access to its folder (#253). Nothing is wrong with
/// the archive, so this is the quietest card in the notice family: the same shape and insets as
/// the archive's own notices under it, a neutral tint instead of a severity colour, and a small ×
/// rather than a button. Nothing modal, nothing takes focus. Copy Details stays under the words.
struct SourceAccessNotice: View {
    @Bindable var model: BrowserModel
    var placement: ArchiveNotices.Placement = .browser
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        // The Group keeps a view here when the notice is gone, so its exit can animate.
        Group {
            if let notice = model.sourceAccessNotice {
                card(notice)
                    .transition(.opacity)
            }
        }
        .animation(Motion.resolved(Motion.exit, reduceMotion: reduceMotion), value: model.sourceAccessNotice == nil)
    }

    private func card(_ notice: Failure) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        let contrastStyle = ContrastStyle.resolve(contrast)
        return HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Image(systemName: "folder.badge.questionmark")
                .foregroundStyle(.secondary)
                .frame(width: 14)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(notice.title)
                    .fontWeight(.medium)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(notice.advice)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                CopyErrorDetails(report: ErrorReport.Copyable(notice))
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                model.sourceAccessNotice = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(String(localized: "Dismiss"))
            .help(String(localized: "Dismiss"))
            // Level with the title's first line, not centred on the card.
            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
        }
        .font(.callout)
        .padding(.leading, Space.m)
        .padding(.trailing, Space.s)
        .padding(.vertical, Space.s)
        .background(.primary.opacity(colorScheme == .dark ? 0.06 : 0.035), in: shape)
        .overlay {
            shape.strokeBorder(.primary.opacity(contrastStyle.borderOpacity))
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        // The Browser's notices stack with their own spacing; Glance's sit flush, so the card brings it.
        .padding(.horizontal, placement == .browser ? Space.m : 0)
        .padding(.bottom, placement == .glance ? Space.s : 0)
    }
}
