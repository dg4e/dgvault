# Critic Review — Round 14

**Reviewer:** 🎭 Critic
**Date:** 2026-06-14
**Scope:** the two security-sensitive features that landed — App Lock
(delete-all-on-fails) and the key-file parser. Both require Critic sign-off
(§4.5; App Lock also R5 duress).

## App Lock delete-all-on-fails — SIGN-OFF: APPROVE logic, 🟠 two hardening asks
Logic is correct: persistent counter behind `FailedAttemptStore`, exhaustion at
`failedCount >= maxAttempts`, `shouldWipe = exhausted && wipeOnExhaustion`,
success resets. Persistence is the right call and is documented (an in-memory
counter would let an attacker relaunch between tries). Performer's tests cover
budget/decrement/wipe-at-exhaustion/cool-down/persistence/clamp. I added
`app_lock_policy_audit_test.dart` (interrupted-wipe re-fire, exhausted-store
rebuild, exact-threshold, success-restores-budget).

**🟠 F1 (hardening REQUEST_CHANGES) — `maxAttempts > 0` is a debug-only `assert`.**
Dart strips `assert` in release builds. So a release build constructed with
`maxAttempts <= 0` is NOT rejected — `recordFailure()` then wipes on the FIRST
failure (`1 >= 0`). For an irreversible "delete all data" trigger this is the
exact accidental-fire R5 warns against. The existing test even encodes reliance on
the assert (`throwsA(isA<AssertionError>())`). Fix: replace the assert with an
always-on guard — `if (maxAttempts <= 0) throw ArgumentError.value(...)`.

**🟠 F2 (hardening) — no wipe-pending signal at startup.** `shouldWipe` is only
returned from `recordFailure()`. If the threshold is reached and the wipe is
signalled but the app is killed before the platform layer completes it, a relaunch
leaves the database intact; the wipe only re-fires on the *next* failed attempt.
An attacker who can read the on-disk (still-encrypted) file in that window gains
nothing it didn't already have, but defence-in-depth says: expose a
`wipePending` getter (`isLockedOut && wipeOnExhaustion`) so startup completes an
interrupted wipe immediately. Pinned current behaviour in a test.

## Key-file parser — SIGN-OFF: APPROVE
- Detection order correct (XML → 32-raw → 64-hex → SHA-256 fallback), matching
  KeePass/KeePassXC.
- **Integrity:** v2.0 XML verifies the `Hash` attribute against
  `SHA-256(key)[:n]` and **throws on mismatch** — tampered/corrupt key files are
  rejected (Performer tests the wrong-hash path).
- SHA-256 is **injected** (`Sha256Hasher`) — no hand-rolled crypto (R2 satisfied);
  digest length validated; hex/base64 length-checked to 32 bytes.
- Minor: `_bytesEqual` is not constant-time. Acceptable here — the compared value
  is an integrity hash of a file the attacker already possesses, not a secret to
  guess. (Constant-time comparison WILL matter for the master-key/HMAC checks in
  the upcoming crypto body; I'll require it there.)

## Phase 1 — one piece from a real password manager
With the key-file parser, App Lock, pipeline, codecs, and header all in place, the
**only** remaining core piece is the injected `KdbxBodyCipher` (Argon2id KDF +
AES-256/ChaCha20 + HMAC framing + protected-value inner-stream) and wiring the
composite key. When it lands I will: KDF/cipher known-answer vectors (R2),
constant-time HMAC/key comparisons, the protected-value inner-stream boundary
(R11), and the KeePassXC golden round-trip (§4.6).

## Honesty note (§0)
Toolchain absent; assertions traced against source by hand. Master suite now ~15
files incl. 11 Critic adversarial suites.

## Consensus
NO. Two open hardening asks on the App Lock duress trigger (F1 is release-safety
relevant), and — still decisive — the real crypto body is unbuilt, so
encrypted-at-rest / zero-knowledge / KeePassXC golden interop remain
undemonstrable (§4.6). Phases 2 (mostly)/8 and much of 3/5/6/7 unstarted.
