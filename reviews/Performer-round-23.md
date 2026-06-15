# Performer — Round 23 (KDBX interop, AES-KDF, large-DB streaming)

Three crypto follow-ups from R22, all verified against an **independent**
implementation (pykeepass 4.1.1 / pyca cryptography), not just self-round-trips.

## 1. KeePassXC / KDBX4 golden interop — COMPLETE
The last Phase-1 KDBX item. dgvault now reads and writes real third-party `.kdbx`.
New format pieces:
- **Original-header hashing** — `KdbxHeader` captures the exact header bytes on
  read; the body cipher's SHA-256 + HMAC now cover those (a re-serialized header
  can differ from a foreign writer's byte layout).
- **Inner header + inner random stream** — `lib/core/format/kdbx_inner.dart`:
  parses/serializes the KDBX4 inner header (stream id/key, inline binaries) and
  applies the protected-value stream (ChaCha20, KeePassXC default; Salsa20 for
  KeePass 2.x) across all `Protected="True"` values in document order. Wired into
  `KdbxCodec` (payload = inner header ++ stream-protected XML).

**Verification:**
- `kdbx_keepassxc_golden_test.dart` reads `test/fixtures/kdbx/reference_aes_argon2.kdbx`
  (pykeepass-written: AES-256, Argon2d I=14/M=64MiB/P=2, gzip, ChaCha20 inner
  stream) and recovers the entry incl. the ChaCha20-protected password. Wrong
  password fails the header HMAC.
- My Argon2 + master-key derivation matched pykeepass's `transformed_key` and
  `master_key` byte-for-byte (traced during bring-up).
- Reverse direction confirmed manually: pykeepass opens a dgvault-written file and
  reads title/username/protected-password/group correctly. (One cosmetic note:
  pykeepass's `kdf_algorithm` *label* property reads None for our header, but it
  derives the key and decrypts correctly — the $UUID dispatch works.)
- Fixture regenerator + notes: `test/fixtures/kdbx/generate_reference.py` + README.

## 2. AES-KDF (legacy) — DONE
`lib/core/crypto/impl/aes_kdf.dart`: composite key → AES-256-ECB(transformSeed)
iterated `rounds` times → SHA-256. `lib/core/crypto/impl/kdf_registry.dart`
(`DefaultKeyDerivation`) dispatches Argon2 vs AES-KDF by the header's algorithm;
`Kdbx4BodyCipher` now defaults to it, so a file using either KDF just works.
Shared composite-key helper extracted to `composite_key.dart`.

**Verification:** `aes_kdf_test.dart` pins a KAT that matches an independent pyca
`AES-ECB` oracle (1000 rounds), checks round/seed sensitivity, input validation,
and a full KDBX round-trip with AES-KDF dispatched through `DefaultKeyDerivation`.

## 3. 1 MiB block-stream chunking — DONE (write side of R4)
`Kdbx4BodyCipher` now frames the body as 1 MiB HMAC blocks (KeePass's size) with a
terminating empty block; the read path already verified block-by-block.
`kdbx_large_stream_test.dart`: a ~2.5 MiB body spans 3 blocks and round-trips; a
flip inside the first block is caught (per-block HMAC); a 2 MiB entry value
survives the full pipeline.

## Build
`flutter test`: **449 passing / 0 failing.** `flutter analyze`: **0 issues.**

## Honest remaining gaps
- **Large-DB lazy/streaming READ** (R4): the block stream chunks on write, but
  read still decrypts the whole body in memory and parses the full XML. True
  250MB lazy loading needs a streaming decrypt + lazy entry/XML loading — not yet
  done.
- **Inner-stream Salsa20** is implemented but only ChaCha20 is covered by a golden
  fixture (KeePassXC default). A Salsa20 (KeePass 2.x) fixture would close that.
- Header re-serialization is still used when *writing*; foreign-file *reads* use
  original bytes (the interop-critical direction).

## Next
Streaming/lazy large-DB read; then the device-gated platform layer (PIN/biometric/
secure-storage/YubiKey/AutoFill/SSH-agent/cloud sync), which needs real OS APIs.
