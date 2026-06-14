# Composer — Round 8 Cross-Review

**Verdict: APPROVE** Critic and Performer's compare/merge. **One BLOCKING bug stands (Critic-found
CSV export data loss). Diceware "+ wordlist" REQUEST_CHANGES still open.** Overall: NO.

## What I shipped this round (branch `ensemble/Composer`)
- `lib/core/sort/entry_sort.dart` — **Custom order & sorting**: stable column sort (title/username/
  url/created/modified, asc/desc) with **null/blank keys pinned last in both directions** (fixed a
  bug in my own first cut where descending flipped blanks to the top); recursive `sortTree` (child
  groups by name); and manual-order primitives `move` (index-clamped) + `moveBefore(anchor|null)`
  for drag-and-drop. Stability via index-decorated sort.
- `test/core/sort/entry_sort_test.dart` — asc/desc, case-insensitivity, null-last both directions,
  stability, date sort, move/clamp, moveBefore(anchor & null), recursive tree sort.

## Critic — merged at last; adversarial suites land — APPROVE (high value)
- CI gate, test strategy, and four adversarial suites (generator, resolver, entry-history, CSV
  round-trip) are now on master. The integration blocker I escalated R6/R7 is resolved.
- `csv_roundtrip_audit_test.dart` is a model finding: it notes Performer's own round-trip starts
  from a CSV that never had custom fields/tags, so it *structurally cannot* see export-side loss,
  then tests the integrity-critical direction (live Entry → export → import). **Confirmed real:
  export drops custom fields & tags = silent data loss.** This is correct and important.

## Performer — `lib/core/diff/database_diff.dart` (compare + merge) — APPROVE with note
- Compare-databases + merge landed with tests. Pending deeper review next round, but structure is
  sound. **Note (R5 acceptance):** plan calls for **3-way / advanced** merge; current is described
  as last-write-wins. LWW can silently lose a concurrent edit — fine as a first cut, but the
  "Advanced Sync & Merge" feature needs ancestor-aware 3-way before that box is truly done.

## Blocking items before any CONSENSUS: YES
1. **CSV export data loss** (custom fields + tags) — Performer must fix; Critic's audit will verify.
2. **Diceware "+ wordlist"** — no EFF asset/loader ships; REQUEST_CHANGES open since R3.
3. Vast remainder of Phase 1 crypto/KDBX spine + auth/lock + platform + sync still `[ ]`.

## Honesty note
No Dart/Flutter toolchain → not executed. Sort service is pure-Dart stdlib + core model; every
case hand-traced. Used Dart-3 record destructuring + covariant `Comparable<Object>?` keys (valid on
SDK >=3.3).

## Vote
Real defects are open (export data loss, missing wordlist) and the crypto/KDBX spine — the gate for
everything per R1/R2 — remains entirely unimplemented. **CONSENSUS: NO.**
