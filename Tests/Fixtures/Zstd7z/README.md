# Zstd-coded 7Z compatibility fixtures

Generated for #316 on 2026-11-06 from this synthetic UTF-8 payload:

```python
("Stow Zstd-in-7Z verification — 中文\n" * 500).encode()
```

The uncompressed file is `payload.txt`, 20,000 bytes, SHA-256
`478007740bc18d4c4194865ad9944f46e82904030c69fda4a5e20a9ff145926a`.
No user data or real password is included.

- `plain.7z` and `encrypted.7z`: py7zr 1.1.4 with `FILTER_ZSTD`, followed by
  `FILTER_CRYPTO_AES256_SHA256` for encryption and header encryption enabled.
  Synthetic password: `stow-fixture-only`.
- `delta-zstd.7z`, `split-zstd.7z.*`, `encrypted-split-zstd.7z.*`:
  [7-Zip-zstd](https://github.com/mcmilk/7-Zip-zstd/tree/bc1fb8a66d4ef549b6ac9bbc1bd660fecd2a572f)
  at `bc1fb8a66d4ef549b6ac9bbc1bd660fecd2a572f`, compiled locally for arm64 solely
  as an independent fixture producer. Creation flags respectively:
  `-m0=Delta:1 -m1=ZSTD`; `-m0=ZSTD -v100b`;
  `-m0=ZSTD -pfixture-only -mhe=on -v100b`.

Each producing implementation extracted its output and matched the payload exactly.
Stow's stock 7-Zip 26.04 lists all five cases with the correct password but cannot
read/test/extract their payload (`Unsupported Method`, status 2). Tests explicitly
pin that known safe failure; they do not claim decoder parity. The alternate engine
is not bundled with Stow. Future decoder work should replace those failure
expectations with payload equality and additional solid/multi-file/corrupt fixtures.
