import SwiftUI

/// Settings › Actions: whether the stack appears, what it would hold for a sample selection, and
/// which actions it suggests.
struct NextStepsSettingsView: View {
    @AppStorage(SettingsKeys.nextStepsShown) private var isShown = true
    @AppStorage(SettingsKeys.nextStepsHidden) private var hidden = NextStepsSettings.encode(NextStepsSettings.defaultHidden)
    /// `-StowActionsExample app` (any `ActionsExample` raw value) picks the sample for design shots.
    @State private var example = UserDefaults.standard.string(forKey: "StowActionsExample")
        .flatMap(ActionsExample.init(rawValue:)) ?? .photos

    private var settings: NextStepsSettings {
        NextStepsSettings(isShown: isShown, hidden: NextStepsSettings.decode(hidden))
    }

    var body: some View {
        Form {
            Section {
                Toggle("Show suggested file actions", isOn: $isShown)
            } footer: {
                Text("Actions offer commands for your selection, or Install App when an archive contains one app. Turning this off hides suggestions; commands remain in the menus.")
            }
            // What the toggles below add up to, for a selection people can pick (#161, #162): a
            // drawing of the Browser's stack, folded and fanned out, then the two menus in words.
            Section {
                Picker("When you select", selection: $example) {
                    ForEach(ActionsExample.allCases) { Text($0.title).tag($0) }
                }
                ActionsExampleRows(layout: example.layout(with: settings), hasMore: example.hasMore)
            } header: {
                Text("Preview")
            } footer: {
                Text("Point at the stack or click its edges to show the actions behind the front one. More (⋯) lists every action except the front one; File › Actions lists them all, hidden suggestions included.")
            }
            .disabled(!isShown)
            Section {
                ForEach(NextStep.Kind.allCases) { kind in
                    Toggle(isOn: binding(for: kind)) {
                        Label {
                            Text(kind.title)
                            Text(kind.when)
                        } icon: {
                            Image(systemName: kind.symbol)
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                                .accessibilityHidden(true)
                        }
                    }
                    .accessibilityLabel(kind.title)
                    .accessibilityHint(kind.when)
                }
                .disabled(!isShown)
            } header: {
                Text("Suggested Actions")
            } footer: {
                VStack(alignment: .leading, spacing: Space.m) {
                    Text("The main action appears in front, with up to two alternatives behind it. Turning off a suggestion hides its button, not the command in the menus.")
                    // Also brings Actions back when it's turned off, so it stays enabled.
                    Button("Restore Defaults") { NextStepsSettings.restoreDefaults() }
                        .disabled(settings.isDefault)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func binding(for kind: NextStep.Kind) -> Binding<Bool> {
        Binding {
            settings.shows(kind)
        } set: { shown in
            var changed = settings
            changed.set(kind, shown: shown)
            hidden = NextStepsSettings.encode(changed.hidden)
        }
    }
}

/// Sample selections for the Actions preview: between them they reach the specific steps, and the
/// last is the Browser with nothing selected in an archive that's one app.
private enum ActionsExample: String, CaseIterable, Identifiable {
    case photos, app, fonts, installer, archive, nothingInAppArchive
    var id: Self { self }

    var title: String {
        switch self {
        case .photos: String(localized: "Two photos")
        case .app: String(localized: "An app")
        case .fonts: String(localized: "Two fonts")
        case .installer: String(localized: "An installer package")
        case .archive: String(localized: "An archive")
        case .nothingInAppArchive: String(localized: "Nothing, in an archive of one app")
        }
    }

    /// With nothing selected the Browser shows the stack alone, without More (⋯).
    var hasMore: Bool { self != .nothingInAppArchive }

    func layout(with settings: NextStepsSettings) -> NextStepsSettings.Layout {
        switch self {
        case .nothingInAppArchive: settings.archiveLayout(installable: Self.entry("Harbor Prototype.app"))
        default: settings.layout(for: entries)
        }
    }

    private var entries: [ArchiveEntry] {
        let paths: [String] = switch self {
        case .photos: ["Photos/Lighthouse.jpg", "Photos/Pier at Dawn.jpg"]
        case .app: ["Harbor Prototype.app"]
        case .fonts: ["Fonts/Harbor Sans.otf", "Fonts/Harbor Serif.ttf"]
        case .installer: ["Harbor Setup.pkg"]
        case .archive: ["Earlier Rounds.zip"]
        case .nothingInAppArchive: []
        }
        return paths.map(Self.entry)
    }

    private static func entry(_ path: String) -> ArchiveEntry {
        ArchiveEntry(path: path, isFolder: false, size: 1, packedSize: 1, modified: .now)
    }
}

/// The stack for one selection: drawn as the Browser shows it, then which menu holds what. More (⋯)
/// leaves out the front action; File › Actions is the complete list.
private struct ActionsExampleRows: View {
    let layout: NextStepsSettings.Layout
    let hasMore: Bool

    var body: some View {
        ActionsStackSketch(layout: layout, hasMore: hasMore)
        LabeledContent("More (⋯)",
                       value: hasMore ? Self.list(layout.more) : String(localized: "Not shown with nothing selected"))
        LabeledContent("File › Actions", value: Self.list([layout.front].compactMap(\.self) + layout.more))
    }

    private static func list(_ steps: [NextStep]) -> String {
        steps.isEmpty ? String(localized: "Nothing") : steps.map(\.title).formatted(.list(type: .and))
    }
}

/// A small drawing of the Browser's Actions stack, folded (the front action, with the edges of the
/// others above it) and fanned out (what pointing at it or clicking the edges shows). Flat and
/// smaller than the real glass buttons, and it takes no clicks: a picture, not a control.
private struct ActionsStackSketch: View {
    let layout: NextStepsSettings.Layout
    let hasMore: Bool
    /// Off with Actions turned off, like the rest of the section.
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(alignment: .bottom, spacing: Space.l) {
            panel(open: false, caption: layout.behind.isEmpty ? String(localized: "Nothing behind it")
                  : String(localized: "At rest"))
            if !layout.behind.isEmpty {
                Image(systemName: "arrow.right")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.tertiary)
                    // Level with the front buttons, above the captions.
                    .padding(.bottom, SketchButton.height / 2 + Self.captionHeight)
                panel(open: true, caption: String(localized: "Pointed at, or edges clicked"))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Space.l)
        .padding(.bottom, Space.xs)
        .opacity(isEnabled ? 1 : 0.4)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
    }

    /// Roughly one caption line plus its spacing, to line the arrow up with the front buttons.
    private static let captionHeight: CGFloat = 22

    private var summary: String {
        let front = layout.front?.title ?? String(localized: "Nothing")
        let behind = layout.behind.isEmpty ? String(localized: "Nothing")
            : layout.behind.map(\.title).formatted(.list(type: .and))
        return String(localized: "In front: \(front). Behind it: \(behind).")
    }

    private func panel(open: Bool, caption: String) -> some View {
        VStack(spacing: Space.s) {
            HStack(alignment: .bottom, spacing: 5) {
                if hasMore { SketchMore() }
                VStack(spacing: 5) {
                    if open {
                        // Nearest the front button at the bottom, as they fan out.
                        ForEach(layout.behind.reversed()) { step in
                            SketchButton(step: step, prominent: false)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    front
                        .background(alignment: .top) {
                            if !open { edges }
                        }
                }
                .fixedSize()
            }
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    /// The front button, as wide as the widest label in the stack (up to a limit), as in the Browser.
    @ViewBuilder private var front: some View {
        if let step = layout.front {
            ZStack {
                ForEach([step] + layout.behind) { SketchButton(step: $0, prominent: false).hidden() }
                    .frame(maxWidth: SketchButton.maxWidth)
                SketchButton(step: step, prominent: true)
                    .frame(maxWidth: .infinity)
            }
        } else {
            Text("Nothing")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(minWidth: SketchButton.minWidth, minHeight: SketchButton.height)
                .padding(.horizontal, Space.m)
                .overlay { Capsule().strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1, dash: [3, 3])) }
        }
    }

    /// The edges of up to two buttons behind the front one, a little narrower each step back.
    private var edges: some View {
        ZStack(alignment: .top) {
            ForEach((0..<min(layout.behind.count, 2)).reversed(), id: \.self) { depth in
                Capsule()
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay { Capsule().fill(Color.accentColor.opacity(depth == 0 ? 0.28 : 0.16)) }
                    .overlay { Capsule().strokeBorder(.primary.opacity(0.14)) }
                    .frame(height: SketchButton.height)
                    .scaleEffect(1 - 0.07 * CGFloat(depth + 1), anchor: .top)
                    .offset(y: -CGFloat(depth + 1) * 4.5)
            }
        }
    }
}

/// One of the sketch's buttons: the accent for the front action, a light capsule for the others.
private struct SketchButton: View {
    static let height: CGFloat = 26
    static let minWidth: CGFloat = 96
    static let maxWidth: CGFloat = 200
    let step: NextStep
    let prominent: Bool

    var body: some View {
        Label(step.title, systemImage: step.symbol)
            .labelStyle(.titleAndIcon)
            .font(.callout.weight(prominent ? .semibold : .medium))
            .lineLimit(1)
            .truncationMode(.middle)
            .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, Space.m)
            .frame(minWidth: Self.minWidth, maxWidth: .infinity, minHeight: Self.height)
            .background {
                if prominent {
                    Capsule().fill(Color.accentColor)
                } else {
                    Capsule().fill(Color(nsColor: .controlBackgroundColor))
                        .stroke(.primary.opacity(0.14), lineWidth: 1)
                }
            }
    }
}

/// The More (⋯) button beside the stack.
private struct SketchMore: View {
    var body: some View {
        Image(systemName: "ellipsis")
            .font(.caption.weight(.bold))
            .foregroundStyle(.primary)
            .frame(width: SketchButton.height, height: SketchButton.height)
            .background {
                Circle().fill(Color(nsColor: .controlBackgroundColor))
                    .overlay { Circle().strokeBorder(.primary.opacity(0.14)) }
            }
    }
}
