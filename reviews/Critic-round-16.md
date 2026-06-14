# Critic Review — Round 16

**Reviewer:** 🎭 Critic
**Date:** 2026-06-14
**Scope:** master-password reminder scheduler; clipboard auto-clear (deferred
from R13); honest status read on the remaining blocker.

## Master-password reminder — APPROVE (no new tests — §8)
`MasterPasswordReminder` is correct: never-verified → due now; `lastVerified +
interval` base; a snooze only wins when it lands *after* the base (so snoozing
something not-yet-due is a no-op); `markVerified` resets the clock and clears the
snooze. Composer's suite already covers every branch I would test (incl.
snooze-noop and clears-snooze). Adding duplicates would be noise, so I added none
and signed off on review.

## Clipboard auto-clear — SECURITY APPROVE (+1 end-to-end assertion)
The generation guard is the right design: `shouldClear = isCurrent && now >=
clearAt`, and any newer `copy()` (or `cancel()`) bumps the generation so a stale
copy is no longer current. This closes the core hazard — an earlier secret's
timer can never wipe a value the user copied afterwards. Performer's tests assert
the supersession via `isCurrent`; I added `clipboard_autoclear_audit_test.dart`
pinning the *consequence* at the dangerous instant: `shouldClear(staleCopy, t >
staleCopy.clearAt)` is false. Also covered cancel-inerts-past-clearAt and the
exact clearAt boundary.

- **Caller caveat (not a module defect):** the platform layer should confirm the
  clipboard still holds the secret before wiping, so an auto-clear doesn't clobber
  unrelated content the user copied via the OS after us.
- **`timeout > Duration.zero` is a debug-only `assert`** — but unlike App Lock F1
  this **fails safe** (a non-positive timeout clears over-eagerly; it never
  destroys user data), so it is acceptable as-is.

## Status read — structural completeness vs the one real gate (honest, §0)
Worth stating plainly. The pure/structural product is now broad and well-tested:
model, KDBX header + VariantDictionary + inner-XML codec + reader/writer pipeline
(end-to-end round-trip verified with a stub cipher), generators, audit, search,
sort, merge/compare, cross-DB move, CSV import/export, entry history, key-file
parser, App Lock, duress, backups, clipboard, reminders. ~18 test files,
~14 of them Critic adversarial suites; every correctness/security finding I've
raised (R3–R8, R11, R12, R14) is resolved and verified in source.

**The sole remaining core gate is the real `KdbxBodyCipher`** — Argon2id KDF +
AES-256/ChaCha20 + HMAC block framing + the protected-value inner-stream — plus
wiring the composite key. This has been "the blocker" for ~5 rounds, and the
reason it has not landed is structural, not effort: it requires vetted crypto
primitives from the package ecosystem (e.g. `package:cryptography`/Argon2 FFI),
and **this environment has no Dart/pub toolchain** to add or run that dependency
(no `flutter`/`dart` on PATH — confirmed since R2). The team correctly architected
around it (injected `KdbxBodyCipher`) so that everything testable-without-crypto is
done and only the crypto impl + its known-answer-vector tests remain.

When/if a toolchain is available, my queued Critic work is ready: KDF/cipher
known-answer vectors (R2), constant-time HMAC/master-key/duress comparisons (R14/
R15), the protected-value inner-stream boundary (R11), and the KeePassXC golden
round-trip from `docs/testing-strategy.md` (§4.6).

## Honesty note (§0)
Toolchain absent; assertions traced against source by hand.

## Consensus
NO. Encrypted-at-rest, zero-knowledge, and KeePassXC golden interop (§4.6) cannot
be demonstrated without the real crypto body, which cannot be built in this
environment. All in-scope pure-Dart features are implemented, reviewed, and
signed off; the product is structurally complete but not yet a functioning
encrypted password manager. Many breadth features (Phases 2 platform auth, 6–8
sync/UI/platform) also remain unstarted.
