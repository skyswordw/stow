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

    @Test func dmgIsForMacsSupportsPasswordAndAlwaysOneFile() {
        #expect(Audience.mac.formats == [.zip, .sevenZip, .dmg])
        #expect(Audience.allCases.filter { $0.formats.contains(.dmg) } == [.mac])
        #expect(PackFormat.dmg.fileExtension == "dmg" && PackFormat.dmg.displayName == "DMG")
        #expect(!PackFormat.dmg.supportsSplit && PackFormat.dmg.supportsPassword && PackFormat.dmg.isCompressed)

        var options = PackOptions()
        options.setAudience(.mac)
        options.usesPassword = true
        options.split = .mb100
        options.diskImageFilesystem = .apfs
        options.diskImageApplicationsLink = true
        options.setFormat(.dmg)
        #expect(options.split == .none)
        #expect(options.usesPassword)
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
