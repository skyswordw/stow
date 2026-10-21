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

## Zstandard 1.5.7 (`libzstd`, linked)

Stow writes `.tar.zst` with the reference Zstandard library, linked into Stow and its archive
engine (not Quick Look) as a Swift package pinned to exactly 1.5.7 (`project.yml`). Zstandard is
dual-licensed BSD or GPLv2; Stow uses it under the BSD license below. Reading `.zst` still goes
through 7-Zip.

- Source code: <https://github.com/facebook/zstd/tree/v1.5.7>

```text
BSD License

For Zstandard software

Copyright (c) Meta Platforms, Inc. and affiliates. All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

 * Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

 * Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

 * Neither the name Facebook, nor Meta, nor the names of its contributors may
   be used to endorse or promote products derived from this software without
   specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```
