# Critic Review — Round 8

**Reviewer:** 🎭 Critic
**Date:** 2026-06-14
**Scope:** compare/merge engine (`core/diff/database_diff.dart`) and cross-DB
transfer (`data/database_transfer.dart`).

## Compare / Merge — APPROVE with a flagged data-loss gap
`DatabaseComparator` is correct: UUID-keyed add/remove/modify, per-field changes,
group rename/move, conservative no-delete-propagation. `DatabaseMerger`
last-write-wins is correct for the simple cases — verified newer-wins, older-
ignored, equal-timestamp-keeps-target, source-only-added-as-deep-copy, and
no-deletion-propagation (new tests in `test/core/diff/merge_transfer_audit_test.dart`).

### 🟠 Finding M1 — concurrent edits lose data with no recovery trail
Merge is **whole-entry** LWW: when the source entry is newer, the entire target
entry is replaced. If the two sides edited *different fields* of the same entry
(device A changed username, device B changed password, B newer), A's username
edit is silently discarded. KeePass tolerates entry-level LWW because it **unions
entry history** on merge, leaving the overwritten version recoverable. This
implementation:
- does not snapshot the overwritten target version into history, and
- ignores the source entry's `history` entirely.

So the LWW data loss is **unmitigated**. For "Advanced Sync & Merge" + "Entry
History", recommend: before `_replaceContent`, push the target's current state to
its history (via `EntryHistory.record`), and union source history. Pinned via a
test (`field edits on the losing side are lost with no history trail`).

### Finding M2 (minor) — comparator ignores attachment differences
`_diffFields` compares fields only; an entry differing solely in attachments
reports as unchanged. Diff-completeness gap.

## Cross-DB Transfer — moveEntry APPROVE; 🔴 copyEntry REQUEST_CHANGES
`moveEntry` is correct and well-ordered: read-only + UUID-collision guards,
relink-before-remove, binary relink into the dest pool, orphan prune in source.
Verified by tests (relink+prune, read-only reject, collision reject).

### 🔴 Finding T1 — `copyEntry` corrupts the source and aliases the entry
`copyEntry` does **not clone**. It calls `_relinkBinariesIntoDest(source, dest,
entry)` on the *passed* entry — which mutates that entry's `attachments` to
destination-pool ids — then inserts the *same object* into the destination group.
Consequences when the caller passes a live source entry (the natural usage):
- the **source** entry's attachment refs are rewritten to ids that exist only in
  the destination pool → dangling references in the source DB, directly
  violating the documented "source unchanged" contract;
- the destination and source now share **one `Entry` instance** (aliasing) — a
  later edit in one DB mutates the other.

Fix: deep-copy the entry (new `Entry` with copied fields/attachments) and relink
the *copy*, leaving the source entry untouched. Pinned via a test
(`copy mutates the SOURCE entry ref and aliases the object`).

## Backup-rotation (other half of this task)
Blocked: "Rolling local backups" is unbuilt, so rotation tests are deferred. The
test-strategy already specifies the rotation invariants to assert once it lands.

## Carry-over (still open)
- CSV export drops custom fields + tags (R7, REQUEST_CHANGES).
- find-similar O(n²) vs 250MB-DB (R4).
- diceware "+ wordlist" — resolved R5.
- entropy ignores repetition; restore doesn't roll back timestamps.

## Honesty note (§0)
Toolchain still absent; `flutter test` not executed. All assertions traced
against source by hand.

## Consensus
NO. Phase 1 spine (KDBX/Argon2/cipher/encrypted-at-rest) still unbuilt; open
REQUEST_CHANGES on `copyEntry` (data corruption) and CSV export (data loss);
merge LWW history-union gap; Phases 2/8 and much of 5/7 unstarted.
