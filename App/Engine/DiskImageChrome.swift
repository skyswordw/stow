import Darwin
import DSStore
import Foundation

/// Finder metadata written to the staging directory, never an attached image (#85).
/// Picture backgrounds are excluded: their Carbon Alias must be made on the mounted volume.
nonisolated enum DiskImageChrome {
    static func apply(to volume: URL) throws(EngineError) {
        let manager = FileManager.default
        do {
            let names = try manager.contentsOfDirectory(atPath: volume.path).sorted()
            let visible = names.filter { !$0.hasPrefix(".") && !DiskImageLayout.extraNames.contains($0) }
            let app = visible.first { name in
                guard name.lowercased().hasSuffix(".app"),
                      let values = try? volume.appending(path: name).resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                else { return false }
                return values.isDirectory == true && values.isSymbolicLink != true
            }
            var store = DSStore()
            store.setViewStyle(.iconView)
            try store.setWindowBounds(top: 100, left: 100, bottom: 500, right: 720)
            store.setBackground(.color(red: 0.96, green: 0.96, blue: 0.96))
            if let app { try store.setIconPosition(for: app, x: 140, y: 180) }
            if visible.contains("Applications") {
                try store.setIconPosition(for: "Applications", x: 480, y: 180)
            }
            for (index, name) in visible.filter({ $0 != app && $0 != "Applications" }).enumerated() {
                try store.setIconPosition(for: name, x: 100 + (index % 4) * 140, y: 300 + (index / 4) * 120)
            }
            // Replace existing metadata, including a staged symlink, without following its target.
            let target = volume.appending(path: ".DS_Store")
            if names.contains(".DS_Store") { try manager.removeItem(at: target) }
            try store.write(to: target)
            if let app { try? copyVolumeIcon(from: volume.appending(path: app), to: volume) }
        } catch {
            throw EngineError(.failed, error.localizedDescription)
        }
    }

    /// No icon or unsupported extended attributes must not prevent a successful pack.
    private static func copyVolumeIcon(from app: URL, to volume: URL) throws {
        let manager = FileManager.default
        let resources = app.appending(path: "Contents/Resources")
        let root = volume.resolvingSymlinksInPath().path + "/"
        guard resources.resolvingSymlinksInPath().path.hasPrefix(root) else { return }
        let icons = try manager.contentsOfDirectory(at: resources, includingPropertiesForKeys: [.isRegularFileKey])
            .filter { $0.pathExtension.lowercased() == "icns" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard let icon = icons.first(where: {
            $0.resolvingSymlinksInPath().path.hasPrefix(root)
                && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }) else { return }
        let target = volume.appending(path: ".VolumeIcon.icns")
        if try manager.contentsOfDirectory(atPath: volume.path).contains(".VolumeIcon.icns") {
            try manager.removeItem(at: target)
        }
        // Copy bytes rather than preserving a resource symlink in the resulting image.
        try Data(contentsOf: icon).write(to: target, options: .atomic)
        var info = [UInt8](repeating: 0, count: 32)
        _ = getxattr(volume.path, "com.apple.FinderInfo", &info, info.count, 0, 0)
        // Finder flags are big endian at bytes 8–9; kHasCustomIcon = 0x0400.
        info[8] |= 0x04
        _ = setxattr(volume.path, "com.apple.FinderInfo", info, info.count, 0, 0)
    }
}
