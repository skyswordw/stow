#!/usr/bin/env python3
"""Launch a packaged app and require a freshly rendered welcome window, including while locked.

The app's own snapshot mode exits after rendering, never starts Sparkle, and uses an empty welcome
scene instead of the person's recent archives. Only this child process is stopped on timeout.
"""
import pathlib
import subprocess
import sys
import time

app = pathlib.Path(sys.argv[1]).resolve()
started = time.time()
try:
    result = subprocess.run(
        [str(app / "Contents/MacOS/Stow"), "-StowScene", "welcome", "-StowSnapshot", "YES",
         "-StowSnapshotMode", "view"],
        capture_output=True, text=True, timeout=30,
    )
except subprocess.TimeoutExpired:
    sys.exit("error: packaged Stow did not finish its launch smoke test within 30 seconds")

if result.returncode:
    print(result.stderr[-4000:], file=sys.stderr)
    sys.exit(f"error: packaged Stow exited with status {result.returncode}")

for line in result.stdout.splitlines():
    path = pathlib.Path(line)
    if path.suffix == ".png" and path.is_file() and path.stat().st_mtime >= started:
        with path.open("rb") as image:
            if image.read(8) == b"\x89PNG\r\n\x1a\n":
                print("ok    packaged Stow launched and rendered its welcome window")
                break
else:
    sys.exit("error: packaged Stow exited without rendering a fresh welcome window")
