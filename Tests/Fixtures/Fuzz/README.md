# Fuzz corpus (Tests/FuzzTests.swift)

- `seed-*.rar`: well-formed RAR 4 and RAR 5 archives to mutate (7-Zip can read RAR but not write it).
- `bad-*.rar`: malformed RARs that once crashed or hung a RAR reader; tested as they are.

Both come from libarchive's test suite (`libarchive/test/test_read_format_rar*.rar.uu`, decoded),
© Tim Kientzle and libarchive contributors, BSD 2-Clause licence. Test data only; not shipped in Stow.

The ZIP, 7Z, TAR (.gz/.bz2/.xz) seeds are made by the bundled 7zz at test time, plus a hand-written
ZIP with `../`, absolute and outward-link entries; the DMG seeds are `../Fixture-HFS.dmg` and
`../Fixture-APFS.dmg`.
