# Composer — Round 11 Cross-Review

**Verdict: APPROVE** Performer + Critic. Continued attacking the spine: KDBX4 header +
VariantDictionary now done. Overall: NO (actual crypto block stream still pending).

## What I shipped this round (branch `ensemble/Composer`)
- `lib/core/format/variant_dictionary.dart` — **KDBX4 VariantDictionary** binary codec: typed
  key/values (UInt32/64, Int32/64, Bool, String, ByteArray), insertion-order preserving, version
  guard. Pure binary, no crypto. (Caught + fixed a real bug pre-merge: `0xDEADBEEF` as UInt32 needs
  unsigned read/write — signed `setInt32`/`getInt32` corrupted high-bit values.)
- `lib/core/format/kdbx_header.dart` — **KDBX4 outer-header codec**: magic/version validation, TLV
  header fields (CipherID, Compression, MasterSeed, EncryptionIV, KdfParameters, PublicCustomData),
  well-known cipher/KDF UUIDs, and **`KdfParameters ⇄ KdfParams`** (incl. KeePass storing memory in
  BYTES vs my model's KiB). Exposes `header.length` so the crypto layer hashes exactly the header
  bytes. Crypto deliberately delegated (header SHA-256/HMAC + encrypted block stream).
- Tests: VariantDictionary all-types round-trip + order + version guard; header AES/ChaCha round-trip,
  KDF mapping (argon2id + aes-kdf), bad-magic + bad-version rejection.

**Spine status after R10+R11:** the *format envelope* is now scaffolded end-to-end —
`KdbxHeader` (outer) → [crypto block: Argon2 + AES/ChaCha + HMAC, Performer] → gzip →
`KeePassXml` (inner) → model. The remaining Phase-1 work is purely the **crypto block** wiring
against my `KeyDerivation`/`Cipher` interfaces. That is now the only thing between us and a real
`.kdbx` read/write.

## Performer — Tags + Custom Fields + Attachments services — APPROVE
- `tags/tag_index.dart`: counts, sorted distinct tags, entries-by-tag, and bulk rename (with
  collapse-on-duplicate) / remove. Clean, model-only, exact/case-sensitive per KeePass. Good.
- `entry/entry_services.dart`: custom-field + attachment-pool helpers — consistent with the model.

## Critic — search adversarial audit (R10) — APPROVE
- Verified my search engine's protected name-vs-value handling and AND×protection matrix. Holds.

## Honesty note
No Dart/Flutter toolchain → `flutter analyze`/`flutter test` **not executed**. Both codecs are pure
`dart:typed_data`; I hand-traced LE int signedness (the UInt32 fix), the VariantDictionary terminator
loop, header TLV offsets, and the bytes==BYTES KDF memory conversion. Fixed a `$UUID` string-interp
trap in a test name (raw string).

## Vote
Format envelope is essentially complete; the crypto block stream (Argon2/AES/ChaCha/HMAC/gzip) — the
R1/R2 gate — remains unbuilt, and Phases 2/8 + much of 3/5/6/7 are untouched. **CONSENSUS: NO.**
