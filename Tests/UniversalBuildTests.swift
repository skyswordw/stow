import Foundation
import Testing
@testable import Stow

/// Stow ships as Universal 2 (#33). Debug test builds only compile the active architecture, so the
/// Release slices are checked by scripts/check-universal.sh in CI; here we pin what doesn't depend on
/// the build configuration: the bundled 7zz and the error report's architecture line.
@Suite("Universal build")
struct UniversalBuildTests {
    /// CPU types from <mach/machine.h>.
    private static let cpuNames: [Int32: String] = [0x0100_0007: "x86_64", 0x0100_000C: "arm64"]

    /// Architectures of a Mach-O file: every slice of a fat (universal) binary, or the one of a thin one.
    static func architectures(of url: URL) throws -> Set<String> {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let header = try handle.read(upToCount: 8 + 20 * 8) ?? Data()
        func big(_ offset: Int) -> UInt32 {
            header[header.startIndex + offset ..< header.startIndex + offset + 4].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        }
        func little(_ offset: Int) -> UInt32 { big(offset).byteSwapped }
        guard header.count >= 8 else { return [] }
        switch big(0) {
        case 0xCAFE_BABE, 0xCAFE_BABF: // FAT_MAGIC, FAT_MAGIC_64
            let count = Int(big(4))
            let stride = big(0) == 0xCAFE_BABE ? 20 : 32
            return Set((0 ..< count).compactMap { index in
                let offset = 8 + index * stride
                guard offset + 4 <= header.count else { return nil }
                return cpuNames[Int32(bitPattern: big(offset))] ?? "cpu \(big(offset))"
            })
        case 0xCFFA_EDFE: // MH_CIGAM_64: a thin 64-bit Mach-O read big-endian
            return [cpuNames[Int32(bitPattern: little(4))] ?? "cpu \(little(4))"]
        default:
            return []
        }
    }

    @Test func bundled7zzIsUniversal() throws {
        let sevenZip = Bundle.main.bundleURL
            .appending(path: "Contents/XPCServices/StowEngine.xpc/Contents/MacOS/7zz")
        #expect(FileManager.default.isExecutableFile(atPath: sevenZip.path))
        #expect(try Self.architectures(of: sevenZip).isSuperset(of: ["arm64", "x86_64"]))
    }

    @Test func reportNamesTheArchitecture() {
        #expect(ErrorReport.Environment.architectureName(arm64: true, translated: false) == "Apple silicon")
        #expect(ErrorReport.Environment.architectureName(arm64: false, translated: false) == "Intel")
        #expect(ErrorReport.Environment.architectureName(arm64: false, translated: true) == "Apple silicon (Rosetta)")
        #if arch(arm64)
        #expect(ErrorReport.Environment.current.architecture == "Apple silicon")
        #else
        #expect(ErrorReport.Environment.current.architecture != "Apple silicon")
        #endif
    }
}
