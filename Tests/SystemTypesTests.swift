import Testing
import UniformTypeIdentifiers
@testable import Stow

/// Types `ArchiveTypes` leaves to macOS must resolve without any other app installed (CI runs on a
/// clean image). RAR didn't, so Stow couldn't become its default app — Stow now imports it.
@Suite("System-declared types")
struct SystemTypesTests {
    @Test(arguments: ArchiveTypes.all.filter(\.isSystemDeclared))
    func resolvesOnACleanMac(type: ArchiveType) throws {
        let resolved = try #require(UTType(type.id), "\(type.id) isn't declared on this Mac")
        #expect(resolved.isDeclared && !resolved.isDynamic, "\(type.id)")
        for ext in type.extensions {
            #expect(UTType(filenameExtension: ext)?.conforms(to: resolved) == true, "\(type.id) .\(ext)")
        }
    }
}
