import AppKit
import SwiftUI

/// Settings › File Types: which archives open with Stow on double-click. Standalone so Settings
/// can host it; also the `associations` demo scene.
struct AssociationsView: View {
    @State var model: Associations

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("File Types")
                    .font(.title3.weight(.semibold))
                Text("Choose which files open in Stow when you double-click them. Stow remembers the app each type used before, so you can always switch back.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.l)

            Form {
                ForEach(ArchiveType.Group.allCases, id: \.self) { group in
                    Section {
                        ForEach(model.rows.filter { $0.type.group == group }) { row in
                            AssociationRow(row: row, appName: model.name(of: row.app), isSelected: selectionBinding(row.id))
                        }
                    } header: {
                        Label(group.title, systemImage: group.symbol)
                    }
                }
            }
            .formStyle(.grouped)

            if let waiting = model.waitingFor {
                Label("Confirm in the macOS dialog: \(waiting)", systemImage: "hand.raised")
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Space.l)
                    .padding(.top, Space.s)
            } else if let report = model.report {
                ReportLine(report: report)
                    .padding(.horizontal, Space.l)
                    .padding(.top, Space.s)
            }

            HStack(spacing: Space.s) {
                Button("Select Suggested") { model.selectSuggested() }
                Spacer()
                Button("Switch Back") { Task { await model.restorePrevious() } }
                    .disabled(model.selection.isEmpty || model.isWorking)
                    .help("Give the selected types back to the app they used before Stow")
                Button("Open with Stow") { Task { await model.makeStowDefault() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.selection.isEmpty || model.isWorking)
            }
            .padding(Space.l)
        }
        .frame(minWidth: 520, minHeight: 520)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refresh() // people may have changed a default in Finder's Get Info meanwhile
        }
    }

    private func selectionBinding(_ id: String) -> Binding<Bool> {
        Binding {
            model.selection.contains(id)
        } set: { isOn in
            if isOn { model.selection.insert(id) } else { model.selection.remove(id) }
        }
    }
}

private struct AssociationRow: View {
    let row: Associations.Row
    let appName: String
    @Binding var isSelected: Bool

    var body: some View {
        Toggle(isOn: $isSelected) {
            HStack(spacing: Space.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.type.name)
                    Text(row.type.extensions.map { "." + $0 }.joined(separator: "  "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: Space.m)
                if row.opensWithStow {
                    Label("Stow", systemImage: "checkmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.callout)
                        .foregroundStyle(.tint)
                } else if let app = row.app {
                    HStack(spacing: Space.xs) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                            .resizable()
                            .frame(width: 16, height: 16)
                        Text(appName)
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                } else {
                    Text("No app")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .toggleStyle(.checkbox)
    }
}

private struct ReportLine: View {
    let report: Associations.Report

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Label(report.summary, systemImage: report.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(report.isSuccess ? Color.green : Color.yellow, .primary)
                .font(.callout.weight(.medium))
            ForEach(report.failed.sorted(by: { $0.key < $1.key }), id: \.key) { name, reason in
                Text("\(name): \(reason)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s)
        .background(.primary.opacity(0.04), in: .rect(cornerRadius: Radius.chip))
    }
}
