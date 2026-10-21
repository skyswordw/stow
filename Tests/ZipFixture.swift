import Foundation

/// Writes small stored (uncompressed) ZIP files byte by byte, so tests can include entries no
/// well-behaved archiver would produce: `../` names, absolute paths, links pointing outside.
struct ZipFixture {
    struct Entry {
        var name: String
        var data: Data
        /// Unix mode including the file type bits.
        var mode: UInt32
        /// Stored name bytes in an older encoding, without the UTF-8 flag (overrides `name`).
        var rawName: Data?

        static func legacy(_ name: String, encoding: String.Encoding, _ text: String) -> Entry {
            Entry(name: name, data: Data(text.utf8), mode: 0o100644, rawName: name.data(using: encoding))
        }

        static func file(_ name: String, _ text: String) -> Entry {
            Entry(name: name, data: Data(text.utf8), mode: 0o100644)
        }

        static func folder(_ name: String) -> Entry {
            Entry(name: name.hasSuffix("/") ? name : name + "/", data: Data(), mode: 0o040755)
        }

        static func symlink(_ name: String, to target: String) -> Entry {
            Entry(name: name, data: Data(target.utf8), mode: 0o120755)
        }
    }

    var entries: [Entry]

    func write(to url: URL) throws {
        var body = Data()
        var directory = Data()
        for entry in entries {
            let name = entry.rawName ?? Data(entry.name.utf8)
            let flags: UInt16 = entry.rawName == nil ? 0x0800 : 0
            let crc = Self.crc32(entry.data)
            let offset = UInt32(body.count)
            // DOS time 12:00, date 2026-10-20.
            let time: UInt16 = 12 << 11
            let date: UInt16 = UInt16((2026 - 1980) << 9 | 10 << 5 | 20)

            body.append(le: UInt32(0x0403_4b50))
            body.append(le: UInt16(10)); body.append(le: flags); body.append(le: UInt16(0))
            body.append(le: time); body.append(le: date)
            body.append(le: crc); body.append(le: UInt32(entry.data.count)); body.append(le: UInt32(entry.data.count))
            body.append(le: UInt16(name.count)); body.append(le: UInt16(0))
            body.append(name); body.append(entry.data)

            directory.append(le: UInt32(0x0201_4b50))
            directory.append(le: UInt16(3 << 8 | 20)) // made by Unix, so the mode is honoured
            directory.append(le: UInt16(10)); directory.append(le: flags); directory.append(le: UInt16(0))
            directory.append(le: time); directory.append(le: date)
            directory.append(le: crc); directory.append(le: UInt32(entry.data.count)); directory.append(le: UInt32(entry.data.count))
            directory.append(le: UInt16(name.count)); directory.append(le: UInt16(0)); directory.append(le: UInt16(0))
            directory.append(le: UInt16(0)); directory.append(le: UInt16(0))
            directory.append(le: entry.mode << 16 | (entry.mode & 0o040000 != 0 ? 0x10 : 0))
            directory.append(le: offset)
            directory.append(name)
        }
        var end = Data()
        end.append(le: UInt32(0x0605_4b50))
        end.append(le: UInt16(0)); end.append(le: UInt16(0))
        end.append(le: UInt16(entries.count)); end.append(le: UInt16(entries.count))
        end.append(le: UInt32(directory.count)); end.append(le: UInt32(body.count))
        end.append(le: UInt16(0))
        try (body + directory + end).write(to: url)
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
        }
        return ~crc
    }
}

private extension Data {
    mutating func append<T: FixedWidthInteger>(le value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}

/// A fresh directory in the (sandboxed) temporary folder, removed by `cleanUp()`.
struct TemporaryFolder {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "StowTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: url)
    }

    /// Every path below the folder, relative, sorted — links not followed.
    func contents() -> [String] {
        let walker = FileManager.default.enumerator(atPath: url.path)
        return (walker?.allObjects as? [String] ?? []).sorted()
    }
}
