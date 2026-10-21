import SwiftUI

/// Shown while a cloud placeholder downloads before it opens: what's happening, how far along,
/// and Cancel (Escape). The bar moves on its own while the system doesn't say how far it is.
struct CloudDownloadCard: View {
    let download: CloudDownload
    let cancel: () -> Void

    var body: some View {
        PromptCard(symbol: download.isICloud ? "icloud.and.arrow.down" : "arrow.down.circle",
                   title: download.title, message: download.message) {
            HStack(spacing: Space.s) {
                if let fraction = download.fraction {
                    ProgressView(value: fraction)
                        .accessibilityValue(AccessibilityText.progress(fraction))
                        .accessibilityLabel(download.title)
                    Text(fraction, format: .percent.precision(.fractionLength(0)))
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 40, alignment: .trailing)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .accessibilityLabel(download.title)
                }
            }
        } buttons: {
            Button("Cancel", role: .cancel, action: cancel)
                .keyboardShortcut(.cancelAction)
        }
    }
}

extension View {
    /// The download card as a sheet over this window; dismissing it (Escape) cancels.
    func cloudDownloadSheet(_ app: AppState, isActive: Bool = true) -> some View {
        sheet(item: Binding(get: { isActive ? app.cloudDownload : nil },
                            set: { if $0 == nil { app.cancelCloudDownload() } })) { download in
            CloudDownloadCard(download: download) { app.cancelCloudDownload() }
        }
    }
}
