# Critic Review — Round 13

**Reviewer:** 🎭 Critic
**Date:** 2026-06-14
**Scope:** KDBX reader/writer pipeline orchestrator; R12 follow-up.

## R12 follow-up — VERIFIED
Composer added `getInt32/setInt32/getInt64/setInt64` to `VariantDictionary`
(my R12 minor finding). Confirmed in source — Int32/Int64 now have typed
accessors, closing the API asymmetry.

## KDBX pipeline orchestrator — APPROVE
`KdbxCodec` cleanly composes header ⇄ injected body-cipher ⇄ injected compressor
⇄ XML codec ⇄ model. Injecting `KdbxBodyCipher`/`Compressor` keeps it pure and —
importantly — lets the whole read/write flow be exercised end-to-end *now*, before
the real crypto lands. Good architecture: when Argon2/AES drop in as
`KdbxBodyCipher`, the pipeline reads/writes real `.kdbx` with no structural change.

Composer's tests cover round-trip, KDBX magic, body-not-plaintext, compression,
and wrong-credential. I added `kdbx_file_audit_test.dart`:
- **rich database** end-to-end (nested groups, protected custom field + flag,
  entry history, unicode meta name/tags, XML metacharacters, and a
  whitespace-significant password) through encode→compress→encrypt→header
  framing→decrypt→decompress→decode;
- **empty database** round-trips;
- **body framing** — 50 entries (fixed header, growing body) confirms the
  `header.length` split has no fixed-offset assumption.

This is my Phase 1 "golden round-trip" task realised with a stub cipher. The
whitespace-significant-value assertion again rides through `KeePassXml.encode(
pretty: true)`, so it doubles as the R11 pretty-print probe at the pipeline level.

## What remains (the security-critical core)
Only two things now stand between this and a real password manager:
1. **Real `KdbxBodyCipher`** — Argon2id KDF transform + AES-256/ChaCha20 + the
   HMAC-SHA-256 block-stream framing + the protected-value inner-stream cipher
   (my R11 boundary flag). This is the zero-knowledge/encryption guarantee.
2. **Composite key** — master password + key file (+ YubiKey CR).

When (1) lands I will: (a) add KDF/cipher known-answer vectors (R2 — no
hand-rolled primitives, published test vectors only), (b) assert the protected-
value inner-stream boundary, and (c) run the KeePassXC golden fixtures from
`docs/testing-strategy.md` so a dgvault-written file opens in KeePassXC and vice
versa (acceptance §4.6).

## Not reviewed this round
Performer's auto-clear clipboard scheduler (R12) — queued for next round's
adversarial pass (generation-guard supersession, injected-clock timing).

## Honesty note (§0)
Toolchain absent; assertions traced against source by hand. The rich round-trip
relies on `package:xml` preserving text-only element content under pretty-print —
expected, but unexecuted, so it doubles as a bug probe (flagged since R11). Master
suite now ~14 files incl. 10 Critic adversarial suites.

## Consensus
NO. The full structural pipeline now round-trips end-to-end (big milestone), but
the **real crypto body is still unbuilt** — so encrypted-at-rest, zero-knowledge,
and KeePassXC golden interop remain undemonstrable; acceptance §4.6 still blocked.
Phases 2/8 and much of 3/5/6/7 also unstarted.
