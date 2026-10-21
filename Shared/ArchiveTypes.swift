import Foundation

/// Every file type Stow registers for: what Finder opens with it, what its Quick Look extension
/// previews, and what Settings › File Types offers. The app's and the extension's Info.plists list
/// the same identifiers (project.yml); a test keeps them in step with this catalog.
nonisolated struct ArchiveType: Identifiable, Hashable, Sendable {
    enum Group: String, CaseIterable, Sendable {
        case everyday = "Everyday archives"
        case unix = "Compressed files"
        case comics = "Comic books"
        case diskImages = "Disk images"
        case installers = "Installers & packages"

        var symbol: String {
            switch self {
            case .everyday: "doc.zipper"
            case .unix: "archivebox"
            case .comics: "book.closed"
            case .diskImages: "externaldrive"
            case .installers: "shippingbox"
            }
        }
    }

    /// The Uniform Type Identifier.
    let id: String
    let name: String
    let extensions: [String]
    let group: Group
    /// macOS declares it already; otherwise Stow imports a declaration (app.stow.* and RAR).
    let isSystemDeclared: Bool
    /// Suggested when people first choose which types open with Stow. Disk images, installers
    /// and executables have better homes (DiskImageMounter, Installer), so they're opt-in.
    let suggested: Bool

    init(_ id: String, _ name: String, _ extensions: [String], _ group: Group,
         system: Bool = true, suggested: Bool = true) {
        self.id = id
        self.name = name
        self.extensions = extensions
        self.group = group
        isSystemDeclared = system
        self.suggested = suggested
    }
}

nonisolated enum ArchiveTypes {
    static let all: [ArchiveType] = [
        ArchiveType("public.zip-archive", "ZIP archive", ["zip"], .everyday),
        ArchiveType("com.winzip.zipx-archive", "ZIPX archive", ["zipx"], .everyday, system: false),
        ArchiveType("org.7-zip.7-zip-archive", "7-Zip archive", ["7z"], .everyday),
        // RAR, ZIPX, LZMA, LZIP, LHA, RPM and APK aren't declared by macOS: Stow imports them (project.yml).
        ArchiveType("com.rarlab.rar-archive", "RAR archive", ["rar"], .everyday, system: false),
        ArchiveType("app.stow.split-archive", "Split archive part", ["001"], .everyday, system: false),
        ArchiveType("public.tar-archive", "TAR archive", ["tar"], .unix),
        ArchiveType("org.gnu.gnu-zip-tar-archive", "TAR.GZ archive", ["tgz"], .unix),
        ArchiveType("public.tar-bzip2-archive", "TAR.BZ2 archive", ["tbz", "tbz2"], .unix),
        ArchiveType("org.tukaani.tar-xz-archive", "TAR.XZ archive", ["txz"], .unix),
        ArchiveType("org.gnu.gnu-zip-archive", "GZIP file", ["gz"], .unix),
        ArchiveType("public.bzip2-archive", "BZIP2 file", ["bz2"], .unix),
        ArchiveType("org.tukaani.xz-archive", "XZ file", ["xz"], .unix),
        ArchiveType("org.tukaani.lzma-archive", "LZMA file", ["lzma"], .unix, system: false),
        ArchiveType("public.lzip-archive", "LZIP file", ["lz"], .unix, system: false),
        ArchiveType("public.z-archive", "Unix compress file", ["z"], .unix),
        ArchiveType("app.stow.zstd-archive", "Zstandard file", ["zst", "tzst"], .unix, system: false),
        ArchiveType("public.cpio-archive", "CPIO archive", ["cpio"], .unix),
        ArchiveType("com.microsoft.cab", "Cabinet archive", ["cab"], .everyday),
        ArchiveType("app.stow.arj-archive", "ARJ archive", ["arj"], .everyday, system: false),
        ArchiveType("cx.c3.lha-archive", "LHA archive", ["lha", "lzh"], .everyday, system: false),
        ArchiveType("app.stow.cbz-archive", "Comic book (ZIP)", ["cbz"], .comics, system: false),
        ArchiveType("app.stow.cbr-archive", "Comic book (RAR)", ["cbr"], .comics, system: false),
        ArchiveType("app.stow.cb7-archive", "Comic book (7Z)", ["cb7"], .comics, system: false),
        ArchiveType("com.apple.disk-image-udif", "Disk image", ["dmg"], .diskImages, suggested: false),
        ArchiveType("public.iso-image", "ISO image", ["iso"], .diskImages, suggested: false),
        ArchiveType("app.stow.wim-image", "Windows image", ["wim"], .diskImages, system: false, suggested: false),
        ArchiveType("app.stow.vhd-image", "Virtual hard disk", ["vhd"], .diskImages, system: false, suggested: false),
        ArchiveType("com.apple.xar-archive", "XAR archive", ["xar"], .installers, suggested: false),
        ArchiveType("com.apple.installer-package-archive", "Installer package", ["pkg"], .installers, suggested: false),
        ArchiveType("com.redhat.rpm-archive", "RPM package", ["rpm"], .installers, system: false, suggested: false),
        ArchiveType("app.stow.deb-archive", "Debian package", ["deb"], .installers, system: false, suggested: false),
        ArchiveType("app.stow.msi-installer", "Windows installer", ["msi"], .installers, system: false, suggested: false),
        ArchiveType("com.sun.java-archive", "Java archive", ["jar"], .installers, suggested: false),
        ArchiveType("public.archive.apk", "Android package", ["apk"], .installers, system: false, suggested: false),
    ]

    static func type(withIdentifier identifier: String) -> ArchiveType? {
        all.first { $0.id == identifier }
    }

    /// By extension; ".tar.gz" resolves through its last component like Finder does.
    static func type(forFileName name: String) -> ArchiveType? {
        let ext = (name as NSString).pathExtension.lowercased()
        return all.first { $0.extensions.contains(ext) }
    }
}
