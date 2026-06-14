# Composer — Round 13 Cross-Review

**Verdict: APPROVE** Performer (App Lock) with one security note. Overall: NO (concrete crypto
primitives remain the Phase-1 gate).

## What I shipped this round (branch `ensemble/Composer`)
- `lib/core/crypto/key_file.dart` — **KeePass key-file parser**. Detects and converts all four
  forms to 32-byte key material: KeePass-2 XML (v1.0 Base64 / v2.0 hex with first-4-byte SHA-256
  integrity hash), 32 raw bytes, 64 hex chars, and the hashed-arbitrary fallback. SHA-256 is the
  only primitive and is **injected** via `Sha256Hasher` (real impl from a vetted lib at the platform
  layer), so the parser is pure/testable. Feeds `CompositeCredential.keyFile`.
- `test/core/crypto/key_file_test.dart` — all four forms, XML v1/v2, whitespace-in-hex, valid-hash
  pass, wrong-hash reject, malformed-XML reject, missing-`<Data>` reject (with a deterministic fake
  hasher).
- Scope honesty: this is the key-file half of "Key File support + Master Password handling"; the
  password→key hashing + composite-key assembly is crypto-layer work and stays with Performer.

## Performer — App Lock (delete-all-on-fails) — APPROVE (security-sensitive)
- `security/app_lock_policy.dart`: consecutive-failure counter behind a `FailedAttemptStore`
  interface, threshold → `shouldWipe`, `wipeOnExhaustion` toggle separating destructive wipe from a
  non-destructive cool-down. Clean separation: the policy is pure; the wipe + persistence are
  delegated. Good.
- **Security note (per §R5 duress safety):** the entire anti-bypass guarantee rests on the *real*
  `FailedAttemptStore` (a) persisting each failure to durable storage **before** the unlock result
  is returned, and (b) surviving app-kill / reinstall (ideally keystore-backed, not a plain file an
  attacker can delete to reset the count). The in-memory store is test-only. Critic should pin this
  as an acceptance requirement when the persistent store lands — the logic is correct but its
  security is only as strong as that store.

## Honesty note
No Dart/Flutter toolchain → `flutter analyze`/`flutter test` **not executed**. The key-file parser is
pure `dart:convert`/`dart:typed_data` + `package:xml`; I hand-traced format dispatch, the v2 hash
verification, the UTF-8-decode guard that rejects binary as non-XML, and hex/base64 length checks.

## Vote
Key-file support done (parser); App Lock done (logic). But the concrete crypto body (Argon2 / AES /
ChaCha / HMAC) + gzip — the R1/R2 gate that makes a real `.kdbx` readable — remain unbuilt, and
Phases 2 (most)/8 + much of 3/5/6/7 are untouched. **CONSENSUS: NO.**
