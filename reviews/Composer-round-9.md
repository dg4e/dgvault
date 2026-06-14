# Composer — Round 9 Cross-Review

**Verdict:** Fixed my own Critic-confirmed bug. **APPROVE** Critic's audit work. **One open finding
left for Performer (M1, LWW history-union).** Overall: NO.

## What I did this round (branch `ensemble/Composer`)
- **Fixed Critic R8 Finding T1** — `DatabaseTransfer.copyEntry` corrupted the source. Root cause: it
  added the *same* `Entry` object to the destination and `_relinkBinariesIntoDest` rewrote that
  shared object's attachment ids, mutating the source. Fix: `copyEntry` now **deep-clones** the
  entry (fresh fields/values, copied attachment refs, tags, recursively cloned history) before
  relinking + inserting. Source is untouched; the two databases hold distinct objects.
- Updated my `database_transfer_test.dart` with a regression test (source ref stays `b1`, dest gets
  the minted id, objects not `identical`).
- Updated Critic's `merge_transfer_audit_test.dart` T1 group from "CORRUPTION (flagged)" — which
  pinned the buggy behaviour — to assert the **fixed** behaviour (source intact, no aliasing). This
  keeps Critic's adversarial suite green and turns the bug-pin into a regression guard.

## Critic — adversarial merge/transfer audits — APPROVE (caught a real bug in my code)
- Finding T1 was correct and well-constructed (id-collision forces the mint that exposed the shared
  mutation). Exactly the kind of cross-DB aliasing bug unit-by-happy-path testing misses. Credit.
- Finding M1 (below) is also correct.

## Performer — `core/diff/database_diff.dart` merge — OPEN: Finding M1 (history-union)
- Merge is whole-entry last-write-wins. KeePass tolerates entry-level LWW **only because it unions
  the loser into the entry's history**, so the discarded edit stays recoverable. Current impl drops
  the older version entirely → silent, unrecoverable data loss on concurrent edits.
- **Recommended fix (Performer):** when LWW replaces target with the newer source entry, push the
  displaced target state into the merged entry's `history` (reuse `EntryHistory.record`/`snapshotOf`
  from my history module), then de-dup. This makes "Advanced Sync & Merge" safe and satisfies the
  3-way intent. Until then the Phase-5 merge box should not be considered acceptance-complete.

## Honesty note
No Dart/Flutter toolchain → not executed. The clone + tests are pure-Dart stdlib + core model;
traced the id-collision/alias paths by hand. Cross-edited Critic's audit test only to flip a
bug-pinning assertion into a fix-asserting one (same scenario, corrected expectations).

## Vote
T1 (data corruption) is fixed. M1 (merge data loss) is open, and the Phase-1 crypto/KDBX spine plus
all of auth/lock, native sync, platform, and most UI remain `[ ]`. Nothing test-executed.
**CONSENSUS: NO.**
