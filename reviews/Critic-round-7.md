# Critic Review — Round 7

**Reviewer:** 🎭 Critic
**Date:** 2026-06-14
**Scope:** CSV/1Password import-export + the integration fix.

## ✅ Integration blocker RESOLVED
The 3-round "Critic-unmerged" gap is fixed. I integrated `ensemble/Critic` into
`master` directly from the master worktree (`git -C <main> merge --ff-only
ensemble/Critic`) after syncing latest master into my branch. All Critic
deliverables are now on `master`, verified file-by-file: `.github/workflows/ci.yml`
(the gate), `docs/testing-strategy.md`, `test/golden/fixtures/README.md`, and the
four adversarial suites (generator, resolver, audit, entry-history). The CI gate
the score claimed in Phase 0 now actually exists on the integration branch.

Process note for the orchestrator: Critic runs in a linked worktree and cannot
`checkout master`, so each round its branch must be merged into master (it is kept
as a clean superset, so this is normally a fast-forward).

## Import/Export review — CSV codec: APPROVE
`CsvCodec` is correct RFC 4180: quoted fields, doubled-quote escaping, embedded
commas/newlines, CRLF/LF/lone-CR, and trailing-newline phantom-record suppression.
Standard-field values (including comma / embedded quote+newline / unicode)
round-trip losslessly through a live-tree export→import — covered by new tests in
`test/data/import_export/csv_roundtrip_audit_test.dart`. Group nesting and TOTP
seeds also round-trip.

## 🔴 REQUEST_CHANGES — export silently drops custom fields and tags
The importer deliberately preserves unmapped columns as **custom fields** and
parses a **Tags** column, but `CsvExporter.export` emits only 7 fixed columns
(`Group,Title,Username,Password,URL,Notes,TOTP`). Consequences on a real
export→import (e.g. CSV backup or app migration):
- **All custom fields are lost** — including security questions, recovery codes,
  secondary secrets. For a password manager this is silent loss of secret data.
- **All tags are lost.**

Performer's existing round-trip test runs import→export→import starting from a CSV
that never had custom fields, so it cannot observe this. My new tests pin the loss
explicitly (`export drops non-column data`).

Recommendation: either (a) export custom fields as extra columns (union of all
custom keys across entries) and add a `Tags` column — the symmetric, lossless
option — or (b) if CSV is intentionally lossy, emit an explicit `warnings`/UI
notice on export listing dropped data, and document it. Silent loss is the only
unacceptable outcome. (Encrypted/native export in later phases should be lossless
regardless.)

## Carry-over (still open, non-blocking)
- find-similar O(n²) vs 250MB-DB requirement (R4) — Phase 5.
- entropy estimate ignores repetition/sequences — documented limitation.
- `EntryHistory.restore` does not roll back timestamps — KeePass fidelity gap.

## Honesty note (§0)
Toolchain still absent; `flutter test` not executed. All assertions traced
against source by hand.

## Consensus
NO. The Phase 1 KDBX core / Argon2 / cipher / encrypted-at-rest spine remains
unbuilt (golden interop tests still blocked on it); Phases 5 (mostly), 8, and much
of Phase 2 are unstarted; and CSV export has an open data-loss REQUEST_CHANGES.
