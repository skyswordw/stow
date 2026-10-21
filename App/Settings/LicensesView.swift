import SwiftUI

struct LicensesView: View {
    private enum Document: String, CaseIterable, Identifiable {
        case stow = "Stow (GPL-3.0)", sevenZip = "7-Zip", notices = "Third-party notices"
        var id: Self { self }
        var title: String {
            switch self {
            case .stow: "Stow (GPL-3.0)"
            case .sevenZip: "7-Zip"
            case .notices: String(localized: "Third-party notices")
            }
        }
        var url: URL? {
            switch self {
            case .stow: Bundle.main.url(forResource: "LICENSE", withExtension: nil)
            case .notices: Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "md")
            case .sevenZip:
                Bundle.main.bundleURL.appending(path: "Contents/XPCServices/StowEngine.xpc/Contents/Resources/7-Zip-License.txt")
            }
        }
        var text: String {
            guard let url, let contents = try? String(contentsOf: url, encoding: .utf8) else {
                return String(localized: "The license text is unavailable in this build. 7-Zip’s license is included with the embedded Stow Engine service in distributed builds.")
            }
            return contents
        }
    }
    @State private var document = Document.stow
    var body: some View {
        Form {
            Picker("License", selection: $document) {
                ForEach(Document.allCases) { item in Text(item.title).tag(item) }
            }
            ScrollView([.horizontal, .vertical]) {
                Text(document.text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Space.s)
            }
            .frame(minHeight: 320)
        }
        .formStyle(.grouped)
    }
}
