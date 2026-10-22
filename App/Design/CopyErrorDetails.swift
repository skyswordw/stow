import SwiftUI

/// A failure's code, quiet beside the buttons, and the button that copies everything a bug report
/// needs. Says "Copied" for a moment; no animation, it's a frequent little thing.
struct CopyErrorDetails: View {
    @Environment(\.colorSchemeContrast) private var contrast
    private var contrastStyle: ContrastStyle { .resolve(contrast) }
    let report: ErrorReport.Copyable
    @State private var copied = false

    var body: some View {
        HStack(spacing: Space.s) {
            Button {
                report.copy()
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    copied = false
                }
            } label: {
                Label(copied ? String(localized: "Copied") : String(localized: "Copy Details"),
                      systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Copy the error code and details for a bug report")
            Text(report.code)
                .font(.caption.monospaced())
                .foregroundStyle(contrastStyle.metadata)
                .textSelection(.enabled)
                .accessibilityLabel(String(localized: "Error code \(report.code)"))
        }
        .font(.caption)
    }
}
