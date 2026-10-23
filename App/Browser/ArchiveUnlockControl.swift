import SwiftUI

/// The title bar's password entry stays available when the sidebar or inspector is hidden.
struct ArchiveUnlockControl: View {
    let model: BrowserModel

    var body: some View {
        if model.archive.isEncrypted {
            if model.isUnlocking {
                Button("Cancel Unlocking", systemImage: "stop.circle") { model.cancelUnlocking() }
                    .help("Checking the password — click to cancel")
            } else {
                Button(model.level.password == nil ? String(localized: "Unlock Archive…") : String(localized: "Password Available"),
                       systemImage: model.level.password == nil ? "lock.fill" : "lock.open.fill") {
                    model.unlockArchive()
                }
                .help(model.level.password == nil ? String(localized: "Enter the archive’s password to preview or extract files")
                      : String(localized: "A password is available for this archive. Individual files may still ask for a different password."))
                .disabled(model.isListing)
            }
        }
    }
}
