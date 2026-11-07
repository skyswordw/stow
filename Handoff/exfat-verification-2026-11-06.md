# exFAT verification attempt — 2026-11-06

Status: **blocked by the host filesystem driver, not a reproduced Stow defect**. Do not
claim exFAT extraction or cross-volume Tray export acceptance from this run.

The user authorized validating exFAT extraction before deciding whether implementation is
needed. Only disposable task-created image files were created/formatted; no physical disk was
changed. A read-only disk inventory distinguished the machine's physical disks from the image.

## Image and filesystem evidence

- Created `/tmp/stow-priority-followups/exfat-partitioned.img` with:
  `diskutil image create blank --size 128M --fs ExFAT --volumeName STOW_EXFAT /tmp/stow-priority-followups/exfat-partitioned.img`.
- `diskutil image info` reported a RAW read-write image, 128,000,000 bytes, a GUID partition
  scheme and a Microsoft Basic Data partition named `STOW_EXFAT`.
- `diskutil image attach --noMount --plist` attached this image as `disk20` / `disk20s1`.
  The partition was recognized as ExFAT. `diskutil info /dev/disk20` confirmed **Protocol:
  Disk Image**, **Virtual: Yes**, 128 MB. These device numbers are historical, not commands
  to reuse without verifying a new attachment's identity.
- `/sbin/fsck_exfat -n /dev/rdisk20s1` checked both boot regions, system files, the file-system
  hierarchy and active bitmap, ending with: `The volume STOW_EXFAT appears to be OK.`

## Mount blocker

The intended mount point was inside the test host's sandbox container:
`/Users/skywalker/Library/Containers/app.stow.Stow/Data/tmp/StowExFATVerification`.

Both `hdiutil attach -nobrowse -mountpoint …` and `diskutil image attach --mountOptions nobrowse
--mountPoint …` failed to mount. Separately attaching without mounting and using `diskutil mount`
also failed. Direct `/sbin/mount_exfat` returned the concrete diagnostic:

```text
Executing: /usr/bin/kmutil load -p /System/Library/Extensions/exfat.kext
Insufficient permissions for action: Unable to load 'com.apple.driver.AppleMobileDevice' in unprivileged request.
mount_exfat: exfat filesystem is not available
```

No attempt was made to override system security or load kernel extensions with elevated access.
The image was detached with `hdiutil detach /dev/disk20`; subsequent `diskutil list /dev/disk20`
reported that the disk could not be found. Scratch images remain local evidence, not repository
artifacts. The empty mount-point directory does not establish an exFAT volume.

## Required follow-up on a host with working exFAT support

1. Create a fresh disposable image as above. Attach it at a sandbox-accessible scratch mount
   point, and verify `statfs` / `diskutil info` reports exFAT before running any test.
2. Use `ArchiveEngine.list` and `Extraction.run`, not a command-line-only extraction substitute.
   Include normal text, Unicode paths, `.gitignore`, an app bundle whose resources include
   `desktop.ini`, and AppleDouble metadata. Check exact output bytes and restored metadata
   where exFAT supports its representation.
3. Extract an explicitly selected helper (`Thumbs.db`, `.DS_Store`) and a normal selected folder.
   Confirm helper suppression does not remove selected data or ordinary hidden/package files.
4. Prepopulate conflicts, exercise Keep Both / Skip and cancellation, and verify original target
   bytes remain intact and incomplete work is not reported as complete or eligible for source
   deletion. Inspect destination staging and any system-generated `._` companions.
5. Run `TrayExport.copy` from an owned temporary group on APFS into this exFAT destination;
   verify bytes, destination-side private staging, collision numbering, cancellation cleanup and
   source retention. A same-volume temporary-directory test does not prove this case.
6. Preserve results and detach only the verified disposable image. If a Stow failure reproduces,
   scope a repair around that evidence; otherwise record acceptance without adding a speculative
   exFAT-specific workaround.

Codex / Grok Bot owns functional verification and any demonstrated repair. Claude Code retains
visual/motion ownership. This environment blocker does not change the deferred VoiceOver scope.
