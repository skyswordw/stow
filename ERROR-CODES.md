# Stow error codes

Every failure Stow explains carries a code like **`EXT-120`**. The code means the same thing in every
language and every version. The failure card, the failed-activity capsule and the batch list (right-click a row)
have **Copy Details**, which puts the code, what people saw, the error's own words and codes, and
the Stow and macOS versions on the clipboard, ready to paste into a bug report.

Codes are `<area>-<reason>`. Numbers are never reused or renumbered; new reasons get new numbers.
`ErrorCodeTests` pins this table.

## Areas — what Stow was doing

| Code | Area |
| --- | --- |
| `OPN` | Opening or listing an archive (including archives inside archives) |
| `EXT` | Extracting |
| `INS` | Installing (apps to Applications, fonts, installers) |
| `PCK` | Packing (creating archives) |
| `CPY` | Copying items out of an archive |
| `GEN` | Not tied to one step (summaries, Stow's own limits) |

## Reasons — why it failed

| Code | Reason | Where it comes from |
| --- | --- | --- |
| `100` | Not an archive Stow can read | engine (`notAnArchive`) |
| `110` | Needs a password | engine (`passwordRequired`) |
| `111` | Wrong password | engine (`wrongPassword`) |
| `120` | Damaged data (a file's data or checksum doesn't match) | 7-Zip "Data Error", "CRC Failed" |
| `121` | Damaged structure (headers, unexpected end of archive) | 7-Zip "Headers Error", "Unexpected end of archive", "Unconfirmed start of archive" |
| `130` | Not enough space | `ENOSPC`, `EDQUOT`, Cocoa out-of-space, 7-Zip's words, or a nearly full destination |
| `140` | Can't write to the destination | `EACCES`, `EPERM`, `EROFS`, Cocoa no-permission, or a folder Stow can't write to |
| `150` | Archive engine missing | engine (`engineMissing`) |
| `151` | Archive engine out of date | engine (`incompatibleVersion`) |
| `152` | Archive engine stopped unexpectedly | engine (`connectionLost`) |
| `160` | Archive changed on disk while being edited | engine (`changedOnDisk`) |
| `170` | Cancelled | engine (`cancelled`); normally not shown |
| `180` | Stow's own limit (e.g. archives nested more than 8 levels deep) | Stow |
| `199` | Anything else | the details hold the error's own words |

The engine's `EngineFailure` raw values (1–9) cross the XPC connection unchanged and map into the
reasons above, so engine, extraction and packing failures share one table.
