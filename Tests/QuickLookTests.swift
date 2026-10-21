import Foundation
import Testing
@testable import Stow

@Suite("Quick Look preview")
struct QuickLookPreviewTests {
    private func archive(_ paths: [(String, Int64)], checkup: [CheckupFinding] = []) -> Archive {
        let files = paths.map {
            ArchiveEntry(path: $0.0, isFolder: false, size: $0.1, packedSize: $0.1 / 2, modified: .now)
        }
        return Archive(name: "t.zip", format: .zip, files: files, checkup: checkup)
    }

    @Test func rowsAreDepthFirstFoldersFirst() {
        let model = ArchivePreviewModel(archive: archive([
            ("b.txt", 1), ("Docs/z.txt", 2), ("Docs/Sub/a.txt", 3), ("a.txt", 4),
        ]))
        #expect(model.rows.map(\.id) == ["Docs", "Docs/Sub", "Docs/Sub/a.txt", "Docs/z.txt", "a.txt", "b.txt"])
        #expect(model.rows.map(\.depth) == [0, 1, 2, 1, 0, 0])
        #expect(model.fileCount == 4)
        #expect(model.folderCount == 2)
        #expect(model.hiddenRowCount == 0)
    }

    @Test func hugeArchivesAreCapped() {
        let model = ArchivePreviewModel(archive: archive((0..<50).map { ("f\($0).txt", 1) }), rowLimit: 10)
        #expect(model.rows.count == 10)
        #expect(model.hiddenRowCount == 40)
    }

    @Test func headlinePrefersCautionThenHandled() {
        let fine = CheckupFinding(severity: .fine, title: "fine", detail: "")
        let handled = CheckupFinding(severity: .handled, title: "handled", detail: "")
        let caution = CheckupFinding(severity: .caution, title: "caution", detail: "")
        #expect(ArchivePreviewModel.headline(of: [fine, handled, caution]).title == "caution")
        #expect(ArchivePreviewModel.headline(of: [fine, handled]).title == "handled")
        #expect(ArchivePreviewModel.headline(of: []).severity == .fine)
    }

    @Test func slowListingFallsBackInTime() async {
        let start = ContinuousClock.now
        let content = await ArchivePreviewLoader.load(URL(filePath: "/nonexistent/big.tar.xz"), timeout: .milliseconds(100)) { _ in
            try await Task.sleep(for: .seconds(30))
            throw EngineError(.failed)
        }
        #expect(ContinuousClock.now - start < .seconds(2))
        guard case .fallback(let fallback) = content else { Issue.record("expected a fallback"); return }
        #expect(fallback.reason == .tooSlow)
        #expect(fallback.format == .tarXz)
    }

    @Test func encryptedNamesFallBack() async {
        let content = await ArchivePreviewLoader.load(URL(filePath: "/x/secret.7z")) { _ in
            throw EngineError(.passwordRequired)
        }
        guard case .fallback(let fallback) = content else { Issue.record("expected a fallback"); return }
        #expect(fallback.reason == .encrypted)
    }

    @Test func realArchiveListsThroughTheEngine() async throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let zip = folder.url.appending(path: "t.zip")
        try ZipFixture(entries: [.file("Docs/a.txt", "hi"), .file("b.txt", "yo")]).write(to: zip)
        let content = await ArchivePreviewLoader.load(zip) { try await ArchiveEngine.shared.list($0) }
        guard case .listed(let model) = content else { Issue.record("expected a listing, got \(content)"); return }
        #expect(model.rows.map(\.id) == ["Docs", "Docs/a.txt", "b.txt"])
        #expect(model.headline.severity == .fine)
    }

    @Test(arguments: [("logs.tar.xz", "logs.tar"), ("a.tgz", "a.tar"), ("notes.txt.gz", "notes.txt"), ("x.bz2", "x")])
    func compressedStreamsGetTheirInnerName(archive: String, inner: String) {
        #expect(SevenZip.innerName(of: archive) == inner)
    }

    @Test func unnamedStreamIsListedUnderItsInnerName() throws {
        let output = """
        --
        Path = logs.tar.xz
        Type = xz
        Physical Size = 552

        ----------
        Size = 12288
        Packed Size = 552

        """
        let listing = try #require(SevenZip.parseListing(output))
        #expect(listing.entries.map(\.path) == ["logs.tar"])
        #expect(listing.entries.first?.size == 12288)
    }
}

@Suite("Registered file types")
struct RegisteredTypesTests {
    private func plist(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    private var app: Bundle {
        // The test host is Stow.app.
        Bundle.main
    }

    @Test func documentTypesCoverTheCatalog() throws {
        let types = try #require(app.infoDictionary?["CFBundleDocumentTypes"] as? [[String: Any]])
        let declared = Set(types.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] })
        #expect(declared == Set(ArchiveTypes.all.map(\.id)))
        let alternate = types.first { $0["LSHandlerRank"] as? String == "Alternate" }?["LSItemContentTypes"] as? [String]
        #expect(Set(alternate ?? []) == Set(ArchiveTypes.all.filter { !$0.suggested }.map(\.id)))
    }

    @Test func ownTypesAreImportedWithTheirExtensions() throws {
        let imported = try #require(app.infoDictionary?["UTImportedTypeDeclarations"] as? [[String: Any]])
        var byID: [String: [String]] = [:]
        for declaration in imported {
            let tags = declaration["UTTypeTagSpecification"] as? [String: Any]
            byID[declaration["UTTypeIdentifier"] as? String ?? ""] = tags?["public.filename-extension"] as? [String]
        }
        for type in ArchiveTypes.all where !type.isSystemDeclared {
            #expect(byID[type.id] == type.extensions, "\(type.id)")
        }
        #expect(Set(byID.keys) == Set(ArchiveTypes.all.filter { !$0.isSystemDeclared }.map(\.id)))
    }

    @Test func quickLookPreviewsEveryType() throws {
        let appex = try #require(app.builtInPlugInsURL?.appending(path: "StowQuickLook.appex/Contents/Info.plist"))
        let info = try plist(appex)
        let attributes = (info["NSExtension"] as? [String: Any])?["NSExtensionAttributes"] as? [String: Any]
        let supported = attributes?["QLSupportedContentTypes"] as? [String] ?? []
        #expect(Set(supported) == Set(ArchiveTypes.all.map(\.id)))
    }

    @Test func everyExtensionResolvesToItsType() {
        for type in ArchiveTypes.all {
            for ext in type.extensions {
                #expect(ArchiveTypes.type(forFileName: "x.\(ext)")?.id == type.id, "\(ext)")
            }
        }
        #expect(ArchiveTypes.type(forFileName: "logs.tar.xz")?.id == "org.tukaani.xz-archive")
    }
}
