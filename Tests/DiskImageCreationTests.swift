import DSStore
import Foundation
import Testing
@testable import Stow

/// Issue #23 / #77: packing as a DMG for Macs.
@MainActor
struct DiskImageCreationTests {
    private func item(_ path: String) -> TreeStream.Item {
        TreeStream.Item(source: URL(filePath: "/tmp/src/" + path), path: path)
    }

    @Test func oneFolderPutsItsContentsAtTheTop() {
        let folder = DiskImageCreation.layout([item("Project"), item("Project/a.txt"), item("Project/Docs"), item("Project/Docs/b.txt")])
        #expect(folder.map(\.path) == ["a.txt", "Docs", "Docs/b.txt"])
        #expect(folder.first?.item.path == "Project/a.txt")
        // Several items, or one file: each keeps its own name on the disk.
        #expect(DiskImageCreation.layout([item("Report.pdf"), item("Notes"), item("Notes/x.txt")]).map(\.path)
                == ["Report.pdf", "Notes", "Notes/x.txt"])
        #expect(DiskImageCreation.layout([item("Report.pdf")]).map(\.path) == ["Report.pdf"])
        #expect(DiskImageCreation.layout([item("Empty")]).map(\.path) == ["Empty"])
    }

    @Test func levelsPickTheImageFormat() {
        #expect(DiskImageCreation.imageFormat(for: .store) == ["-format", "UDRO"])
        #expect(DiskImageCreation.imageFormat(for: .fastest) == ["-format", "UDZO", "-imagekey", "zlib-level=1"])
        #expect(DiskImageCreation.imageFormat(for: .balanced) == ["-format", "UDZO"])
        #expect(DiskImageCreation.imageFormat(for: .maximum) == ["-format", "ULFO"])
        #expect(DiskImageCreation.imageFormat(for: .smallest) == ["-format", "ULMO"])
        #expect(DiskImageCreation.volumeName(for: "Q3: Final") == "Q3- Final")
        #expect(DiskImageCreation.volumeName(for: "  ") == "Disk Image")
    }

    @Test func dmgIsForMacsClearsPasswordAndAlwaysOneFile() {
        #expect(Audience.mac.formats == [.zip, .sevenZip, .dmg])
        #expect(Audience.allCases.filter { $0.formats.contains(.dmg) } == [.mac])
        #expect(PackFormat.dmg.fileExtension == "dmg" && PackFormat.dmg.displayName == "DMG")
        #expect(!PackFormat.dmg.supportsSplit && !PackFormat.dmg.supportsPassword && PackFormat.dmg.isCompressed)

        var options = PackOptions()
        options.setAudience(.mac)
        options.usesPassword = true
        options.split = .mb100
        options.diskImageFilesystem = .apfs
        options.diskImageApplicationsLink = true
        options.setFormat(.dmg)
        #expect(options.split == .none)
        #expect(!options.usesPassword) // AES DMG packing deferred (sandbox)
        #expect(options.diskImageFilesystem == .apfs && options.diskImageApplicationsLink)
        // Back to Windows: DMG isn't offered there, so ZIP; DMG-only options clear.
        options.setAudience(.windows)
        #expect(options.format == .zip)
        #expect(options.diskImageFilesystem == .hfsPlus && !options.diskImageApplicationsLink)
        // The engine is never asked to make one.
        let request = CreateRequest(operationID: "x", archiveName: "P", format: .dmg)
        #expect(SevenZip.createSteps(for: request, archive: URL(filePath: "/tmp/P.dmg"), input: URL(filePath: "/tmp/in"),
                                     work: URL(filePath: "/tmp/work")).isEmpty)
    }

    @Test func applicationsShortcutSkipsWhenNameTaken() {
        #expect(!DiskImageCreation.applicationsNameTaken(in: ["README.md", "Docs/a.txt"]))
        #expect(DiskImageCreation.applicationsNameTaken(in: ["Applications"]))
        #expect(DiskImageCreation.applicationsNameTaken(in: ["README.md", "Applications"]))
        #expect(!DiskImageCreation.applicationsNameTaken(in: ["Apps/Applications"]))
        #expect(!DiskImageCreation.applicationsNameTaken(in: ["Applications/nested"]))
    }

    @Test func filesystemTitlesAndDetails() {
        #expect(DiskImageFilesystem.hfsPlus.title == "HFS+")
        #expect(DiskImageFilesystem.apfs.title == "APFS")
        #expect(!DiskImageFilesystem.hfsPlus.detail.isEmpty)
        #expect(DiskImageFilesystem.apfs.detail.contains("HFS+"))
    }
}


/// #85: Finder chrome is generated before image creation, with no mounted volume.
@MainActor
struct DiskImageChromeTests {
    @Test func writesFinderRecords() throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        try FileManager.default.createDirectory(at: folder.url.appending(path: "Foo.app"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: folder.url.appending(path: "Applications").path,
                                                  withDestinationPath: "/Applications")
        try Data().write(to: folder.url.appending(path: "Readme.txt"))
        try FileManager.default.createDirectory(at: folder.url.appending(path: ".background"), withIntermediateDirectories: false)
        try DiskImageChrome.apply(to: folder.url)
        let store = try DSStore.read(from: folder.url.appending(path: ".DS_Store"))
        #expect(store.viewStyle() == .iconView)
        #expect(store.windowBounds()?.width == 620)
        #expect(store.windowBounds()?.height == 400)
        #expect(store.background() == .color(red: 0.96, green: 0.96, blue: 0.96))
        #expect(store.iconPosition(for: "Foo.app")?.x == 140)
        #expect(store.iconPosition(for: "Foo.app")?.y == 180)
        #expect(store.iconPosition(for: "Applications")?.x == 480)
        #expect(store.iconPosition(for: "Readme.txt")?.y == 300)
        #expect(store.iconPosition(for: ".DS_Store") == nil)
        #expect(store.iconPosition(for: ".background") == nil)
    }

    @Test func worksWithoutAnAppOrShortcut() throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        try Data().write(to: folder.url.appending(path: "Notes.txt"))
        try DiskImageChrome.apply(to: folder.url)
        let store = try DSStore.read(from: folder.url.appending(path: ".DS_Store"))
        #expect(store.iconPosition(for: "Notes.txt")?.x == 100)
        #expect(store.iconPosition(for: "Applications") == nil)
        #expect(!FileManager.default.fileExists(atPath: folder.url.appending(path: ".VolumeIcon.icns").path))
    }

    @Test func replacesMetadataSymlinkWithoutWritingOutsideStaging() throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let volume = folder.url.appending(path: "Volume")
        try FileManager.default.createDirectory(at: volume, withIntermediateDirectories: false)
        let outside = folder.url.appending(path: "outside")
        let original = Data("unchanged".utf8)
        try original.write(to: outside)
        try FileManager.default.createSymbolicLink(atPath: volume.appending(path: ".DS_Store").path,
                                                  withDestinationPath: outside.path)
        try DiskImageChrome.apply(to: volume)
        #expect(try Data(contentsOf: outside) == original)
        #expect(try DSStore.read(from: volume.appending(path: ".DS_Store")).viewStyle() == .iconView)
    }

    @Test func metadataFailureSurfacesAsEngineError() throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        #expect(throws: EngineError.self) {
            try DiskImageChrome.apply(to: folder.url.appending(path: "missing"))
        }
    }

    @Test func copiesVolumeIconAndSetsFinderFlag() throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let resources = folder.url.appending(path: "Foo.app/Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let icon = Data([0x69, 0x63, 0x6e, 0x73, 0, 0, 0, 8])
        try icon.write(to: resources.appending(path: "Foo.icns"))
        try DiskImageChrome.apply(to: folder.url)
        #expect(try Data(contentsOf: folder.url.appending(path: ".VolumeIcon.icns")) == icon)
        var info = [UInt8](repeating: 0, count: 32)
        #expect(getxattr(folder.url.path, "com.apple.FinderInfo", &info, info.count, 0, 0) == 32)
        #expect(info[8] & 0x04 != 0)
    }

    @Test func volumeIconDoesNotFollowResourcesOutsideStaging() throws {
        let folder = try TemporaryFolder()
        defer { folder.cleanUp() }
        let volume = folder.url.appending(path: "Volume")
        let contents = volume.appending(path: "Foo.app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let outside = folder.url.appending(path: "Outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        try Data("outside icon".utf8).write(to: outside.appending(path: "Foo.icns"))
        try FileManager.default.createSymbolicLink(atPath: contents.appending(path: "Resources").path,
                                                  withDestinationPath: outside.path)
        try DiskImageChrome.apply(to: volume)
        #expect(!FileManager.default.fileExists(atPath: volume.appending(path: ".VolumeIcon.icns").path))
        #expect(try DSStore.read(from: volume.appending(path: ".DS_Store")).viewStyle() == .iconView)
    }

    @Test func chromeResetsWithFormatAudienceAndPurpose() {
        var options = PackOptions()
        #expect(!options.diskImageFinderChrome)
        options.setAudience(.mac)
        options.setFormat(.dmg)
        options.diskImageFinderChrome = true
        options.setFormat(.zip)
        #expect(!options.diskImageFinderChrome)
        options.setFormat(.dmg)
        options.diskImageFinderChrome = true
        options.setAudience(.windows)
        #expect(!options.diskImageFinderChrome)
        options.setAudience(.mac)
        options.setFormat(.dmg)
        options.diskImageFinderChrome = true
        options.resetToPurposeDefaults()
        #expect(!options.diskImageFinderChrome)
    }

    @Test func createRequestPreservesChromeThroughEncoding() throws {
        let defaults = CreateRequest(operationID: "test", archiveName: "Foo", format: .dmg)
        #expect(!defaults.diskImageFinderChrome)
        var request = defaults
        request.diskImageFinderChrome = true
        let decoded = try JSONDecoder().decode(CreateRequest.self, from: JSONEncoder().encode(request))
        #expect(decoded.diskImageFinderChrome)
    }
}
