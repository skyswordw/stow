#!/bin/zsh
# Prints which bundle declares each type ArchiveTypes.swift leaves to macOS (system: true), from
# Launch Services' database. Diagnostic only: run on a clean Mac (or CI) to see that the declarer
# is macOS itself, not some app that happens to be installed.
set -euo pipefail
cd "${0:a:h}/.."
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
ids=$(grep -E '^\s*ArchiveType\("' Shared/ArchiveTypes.swift | grep -v 'system: false' | sed -E 's/^[^"]*"([^"]+)".*/\1/')
"$lsregister" -dump 2>/dev/null | python3 -c '
import re, sys
ids = sys.argv[1].split()
found = {i: set() for i in ids}
for block in re.split(r"\n-{20,}\n", sys.stdin.read()):
    m = re.search(r"^type id:\s+(\S+)", block, re.M)
    if not m or m.group(1) not in found: continue
    b = re.search(r"^bundle:\s+(.+?)\s+\(0x", block, re.M)
    flags = re.search(r"^flags:\s+(.+?)\s+\(", block, re.M)
    name = b.group(1) if b else "?"
    flag = flags.group(1) if flags else ""
    found[m.group(1)].add(name + " [" + flag + "]")
for i in ids:
    print(f"{i}: " + ("; ".join(sorted(found[i])) or "NOT DECLARED"))
' "$ids"
