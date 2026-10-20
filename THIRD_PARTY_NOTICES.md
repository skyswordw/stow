# Third-party notices

## 7-Zip 26.04 (`7zz`, macOS console build)

Stow's archive engine (`Stow.app/Contents/XPCServices/StowEngine.xpc`) runs the official 7-Zip
console program as a separate, unmodified executable. It is not linked into Stow.

- Copyright © 1999–2026 Igor Pavlov
- Licenses: GNU LGPL 2.1 or later (most code), GNU LGPL with the unRAR license restriction (RAR
  decompression), BSD 3-clause and BSD 2-clause (some code)
- Release: 26.04 (2026-10-05), `7z2604-mac.tar.xz`,
  SHA-256 `bee04358cbcbc7106273cee0e8d72916db2696c48067a3538c34d8cd6fd16578`
- Binary: <https://github.com/ip7z/7zip/releases/tag/26.04>
- Source code: <https://www.7-zip.org/download.html> (`7z2604-src.tar.xz`), also at
  <https://github.com/ip7z/7zip>

The full license text ships inside the app at
`Contents/XPCServices/StowEngine.xpc/Contents/Resources/7-Zip-License.txt`, copied from the
release's `License.txt`. Because 7-Zip is a standalone executable, you can replace it with your own
build of the same or a modified version (re-sign the app afterwards), as the LGPL allows.

`scripts/fetch-7zip.sh` downloads exactly this release and refuses it if the checksum differs.
When updating, change the version, file name and checksum there and here together.

The unRAR restriction: the RAR decompression code may not be used to develop a RAR (WinRAR)
compatible archiver. Stow only extracts RAR archives; it never creates them.
