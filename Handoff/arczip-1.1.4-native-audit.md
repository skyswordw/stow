# ArcZip 1.1.4 native comparison — 2026-10-23

This records native observations, not a claim that every supported format, machine, or ArcZip Pro
feature passed. It supersedes contradictory implementation-status claims in the older static
[parity matrix](../PARITY.md). The remaining release matrix stays open in
[#38](https://github.com/skyswordw/stow/issues/38).

## Build identity and method

- ArcZip: `/Applications/ArcZip.app`, **1.1.4 (255)**, Pro inactive.
- Stow: universal CI artifact for **`4fc9dd3171272f3874dc1f4065f00c8c7ddba5e2`**, successful
  [run 40049510208](https://github.com/skyswordw/stow/actions/runs/40049510208).
  Launched from `/tmp/stow-parity-4fc9dd3/Stow.app`; process path verified after quitting the old
  verification build. Deep/strict code-signature verification passed before launch.
- The installed signed release, **0.1.1 (279)**, predates recent fixes and was not substituted for
  this current-main audit. CI's shallow-history build number is insufficient to identify code.
- Host: Apple silicon, **macOS 27.2 (26B118)**. Remote main was checked again after the native
  audit and was still `4fc9dd3`.
- Native actions used Computer Use. Output bytes, archive integrity, hashes, crash signatures and
  source paths were checked separately with file/CLI tools. Model tests were not counted as native
  verification. All writes used generated scratch fixtures; preview PDF/PNG assets came from the
  repository's real sample resources.

## Results

| Workflow | Stow observation | ArcZip comparison / evidence limit |
| --- | --- | --- |
| Real archive browsing | Grid/List, folders, path bar, ordinary names and Unicode entries displayed | Same parent/nested fixture opened in ArcZip List view |
| Real previews | Six-page PDF thumbnail, inspector and Space Quick Look showed real content; ordinary text preview worked | ArcZip previewed the real text inside the nested ZIP |
| Filename search | Deep ordinary filename found; nested filename missing / loading then no match | ArcZip search is Pro-gated; no paid-search parity claim |
| Nested ZIP | Failed with internal input-open EPERM, misclassified as destination write denial; full-browser AX observation also crashed | ArcZip entered the same ZIP and previewed its child; [#112](https://github.com/skyswordw/stow/issues/112) |
| Extract All | Every fixture entry matched source bytes, including empty folder, dotfiles, Unicode names, PDF/PNG and nested ZIP | Ordinary extraction controls available in ArcZip; no all-format parity claim |
| Extract selected | Selected ordinary text extracted with exact bytes and no unrelated entries | ArcZip explicitly extracted a selected helper, below |
| File conflicts | Stop preserved original; Keep Both created correct `old 2.txt`; Skip added nothing; Replace installed correct bytes and preserved original in Trash | Stow output and recoverability verified directly |
| Folder conflicts | Merge at wrapper and child-folder levels retained existing child and added archive entries | Stow output verified directly |
| Batch extraction | Two ZIPs got independent output folders; every archive entry matched source bytes | ArcZip batch/Flow behavior not exercised under inactive Pro |
| Invalid input | OPN-100 with format/download advice | Not a cross-app error-copy equivalence claim |
| Damaged input | CRC mismatch reported the damaged file as EXT-120; no corrupt output remained | CRC validity established independently |
| Explicit helpers | `.DS_Store` and `Thumbs.db` selection failed with EXT-199 and misleading damage advice | ArcZip extracted the same selected `Thumbs.db` with exact 27 bytes; [#109](https://github.com/skyswordw/stow/issues/109) |
| App bundle helpers | Bundle containing only a `desktop.ini` resource disappeared until helpers were shown, then read zero bytes | ArcZip kept the app visible at its correct 27 bytes; included in #109 |
| ZIP creation | Verify passed; all output bytes matched; Windows preflight renamed reserved/punctuation names without changing originals | ArcZip free General/Balanced ZIP creation passed CRC and exact-byte checks; Windows audience is Pro-gated |
| TAR.GZ creation | Linux audience retained names; verified output matched every input byte | ArcZip TAR and audience options are Pro-gated |
| Read-only format | Compressed TAR rejected editing with an explicit explanation; Extract and Repack produced a verified 7Z with exact original text | Advanced ArcZip editing is Pro-gated |
| Split encrypted creation | Created two valid 100 MB / remainder 7Z volumes from a 105 MB synthetic file; independent 7-Zip test and streamed SHA-256 matched source | ArcZip requests password, unlocks, and lists the same Stow-created split archive |
| Split archive reopening | Stow rejected its own valid first volume as OPN-100 before requesting a password | Direct parity failure; [#116](https://github.com/skyswordw/stow/issues/116) |
| Packing cancellation | Stopped a running 105 MB ZIP job; no final or hidden partial output remained | Native Stow cancellation and filesystem cleanup checked |
| Staged editing | Rename/add/replace/delete updated listing and preview; original hash stayed unchanged before Save; Revert restored the original plan | ArcZip native editing comparison is license-limited |
| Save edited ZIP | Failed with EPERM for `.stow-saving`; original hash unchanged, edit plan retained, staging cleaned | [#114](https://github.com/skyswordw/stow/issues/114); likely related input access needs investigation |
| Undo | Disabled after a real rename; repeated with coordinate mouse focus on the list before Command-Z | [#113](https://github.com/skyswordw/stow/issues/113); no claim that ArcZip Undo was tested |
| Glance | Full → Glance → folder navigation → text selection → full retained folder, selection and usable back history | ArcZip exposes its Mini switch; full cross-app pin/multidisplay comparison remains |
| Tray | Added a scratch fixture folder, browsed children, selected text by mouse and read actual Quick Look content; inspected actions and cleared test references | ArcZip File Box/Flows not operationally compared in this run; no share action was sent |
| Settings | Viewed General, Extraction, Installing, Packing, Next Steps, Previews, Passwords, File Types, Integration and Advanced | No destructive reset, association change, Keychain enablement or permission grant performed |
| Size statistics | 155-byte TAR.GZ reported 512 bytes packed / 1,500% larger | Incorrect compressed-size semantics; [#115](https://github.com/skyswordw/stow/issues/115) |
| Singular counts | Single-file sidebar/search incorrectly used `files` | [#117](https://github.com/skyswordw/stow/issues/117); fixed by preserving numeric interpolation and catalog plural rules |
| Accessibility stability | Additional recursion crashes with nested-archive/error paths on current main, including List with inspector hidden | Extended [#93](https://github.com/skyswordw/stow/issues/93); a following AX query is part of the sequence, so mouse causality is not isolated |

## Remaining work and concrete limits

- **Functional blockers:** investigate #93, #109, #112–#116. Re-run native Save/reopen, nested
  encrypted search/navigation and explicit helper/app-bundle cases after fixes. Failure-state AX
  rendering may connect several crash sequences; do not assume separate root causes.
- **ArcZip Pro:** search, advanced compression/levels/password creation, audience presets, editing,
  and Flows are explicitly license-gated in the installed app. No trial, purchase or activation was
  performed. A licensed comparison session is needed for those operational matches.
- **Signed integration:** current-main Finder menu reported off. The separately installed signed
  release and its registered extensions are older. Current-main signed Finder/Services/Quick Look
  handoff, real Finder drag-in/out and live Sparkle updates still need a matched signed build and
  the intended extension configuration. They were not marked passed from source or old binaries.
- **Installation:** settings and access explanation were reviewed, but real app/font/PKG installs,
  replacement/running-app checks and quarantine outcomes still need an isolated test account or
  VM. No software was installed into the user's Applications/Fonts folders and no new security
  permission was granted in this audit.
- **Additional release matrix:** macOS 26, Intel/Rosetta, clean account, iCloud placeholders, SMB/NAS,
  external-volume semantics, huge archives, broad legacy encodings, VoiceOver/Accessibility
  Inspector, Reduce Motion/Transparency and multiple displays remain separate #38 checks.
- **Safe scope:** maintenance reset/clear, real user file associations and licensing were inspected
  only as applicable. Test changes to Windows compression level, packing audience and post-pack
  verification were restored to the observed original values (Balanced, Windows PCs, verification
  off). Scratch data remains available locally for reproducing the issues.

## Ownership and handoff

Codex owns engine/state/errors/security/cancellation, undo wiring, numeric/localization correctness
and tests. **Claude Code owns visual design and motion** under [AGENTS.md](../AGENTS.md) and
[#104](https://github.com/skyswordw/stow/issues/104). Error read/write context, locating volume parts,
helper visibility/counts and unavailable compressed-size states need functional contracts before
visual treatment. This report does not claim Claude Code has started or reviewed the work.

The existing Chinese issue titles/bodies and Chinese comments were migrated to English in this
session: 13 issues and 10 comments, with states, evidence, code blocks and checkbox counts preserved;
#104 and its comments had already been translated. Legitimate localized examples were retained.
