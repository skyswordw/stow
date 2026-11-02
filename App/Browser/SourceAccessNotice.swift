import SwiftUI

/// The archive is usable; only saving its folder access failed. No modal or focus takeover.
/// Claude Code owns final visual treatment; this uses existing native notice controls.
struct SourceAccessNotice: View {
    @Bindable var model: BrowserModel

    var body: some View {
        if let notice = model.sourceAccessNotice {
            VStack(alignment: .leading, spacing: Space.s) {
                Text(notice.title).font(.headline)
                Text(notice.advice).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    CopyErrorDetails(report: ErrorReport.Copyable(notice))
                    Spacer()
                    Button("Dismiss") { model.sourceAccessNotice = nil }
                        .controlSize(.small)
                }
            }
            .padding(Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
        }
    }
}
