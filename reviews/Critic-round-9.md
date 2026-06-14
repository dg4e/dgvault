# Critic Review — Round 9

**Reviewer:** 🎭 Critic
**Date:** 2026-06-14
**Scope:** custom order & sorting; open-finding tracking; Phase 1 escalation.

## 🛑 STRUCTURAL ESCALATION — Phase 1 unstarted for 9 rounds
The entire **Phase 1 KeePass core is still unbuilt**: KDBX 4 reader/writer,
Argon2 KDF, AES-256/ChaCha20 cipher layer, encrypted-at-rest storage, key-file +
master-password handling. Every round the ensemble has shipped *peripheral*
features (generators, audit, resolver, history, search, sort, CSV, move/merge),
all of which operate on an **in-memory plaintext model** that, today, **cannot be
read from or written to an encrypted `.kdbx` file at all.**

Why this is the gating risk (per R1/R2):
- The product is defined as a **KeePass-compatible, zero-knowledge, encrypted**
  password manager. With no cipher/KDF/serialization, none of those three core
  guarantees exist yet. The app can't persist or load a real database.
- Acceptance criteria §4.6 (KeePass interop via reference `.kdbx` round-trip) and
  the Phase 1 Critic golden tests are **blocked indefinitely** on this.
- Performance design for 250MB DBs (R4) was supposed to be built *into* the
  reader from Phase 1, not retrofitted — the longer this slips, the more
  features assume an all-in-memory model that won't scale.

**Recommendation:** the next round(s) should prioritise the KDBX/crypto spine over
any further peripheral features. I cannot vote CONSENSUS: YES while the core that
defines the product does not exist, regardless of how polished the surrounding
modules are.

## Custom order & sorting — APPROVE
`EntrySorter` is correct and well-built: index-decorated stable sort, blanks sort
last independent of direction, case-insensitive text keys, clamped `move`, and
`moveBefore` with member checks. Added `entry_sort_audit_test.dart`:
- descending sort preserves input order among equal keys (tie-break not reversed),
- `sorted()` is non-destructive to its input,
- `modified` nulls sort last in both directions,
- `moveBefore` handles the entry-before-anchor shift and rejects non-members.
All pass by inspection; no defects found.

## Open findings still unresolved
- 🔴 **R8 `copyEntry` corruption — STILL OPEN.** Re-checked the source this round:
  `copyEntry` still relinks and inserts the *passed* entry (no clone), corrupting
  the source entry's attachment refs and aliasing one `Entry` across two DBs.
  REQUEST_CHANGES stands. Fix: deep-copy before relinking.
- 🟠 **R8 merge LWW history-union gap** — overwritten target version is still not
  snapshotted into history on merge; concurrent-edit data loss remains
  unrecoverable. Recommend `EntryHistory.record` before `_replaceContent`.

## Resolved since raised (verified in source)
- ✅ CSV export custom-fields/tags loss (R7) — exporter now emits Tags + custom
  columns; lossless round-trip confirmed.
- ✅ Diceware "+ wordlist" (R3/R4) — embedded list + EFF parser shipped.
- ✅ Critic integration (R6) — all Critic work merged to master each round.

## Honesty note (§0)
Toolchain still absent; `flutter test` not executed. All assertions traced
against source by hand. The CI gate on master will run the full suite (now ~10
test files incl. 6 Critic adversarial suites) once a Flutter runner is available.

## Consensus
NO. The Phase 1 crypto/KDBX spine — the core of the product — is unbuilt after 9
rounds, blocking encrypted persistence, zero-knowledge guarantees, and golden
interop tests. Plus open REQUEST_CHANGES on `copyEntry`. Most of Phases 2, 5, 6,
7, 8 also remain unstarted.
