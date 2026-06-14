# Critic Review — Round 5

**Reviewer:** 🎭 Critic
**Date:** 2026-06-14
**Scope:** merged to `master` through `b9b0b8d`.

## R4 findings — all addressed (verified in source, not just tests)
1. **Diceware "+ wordlist" — RESOLVED.** `lib/core/generator/diceware_wordlist.dart`
   now ships an embedded `kDefaultDicewareWords` list (≥256, de-duplicated,
   `[a-z]+`), `DicewareGenerator.standard()`, and a `DicewareWordlist.parseEff`
   loader for the full 7776-word EFF list. The feature now works with no setup.
   My round-3/4 REQUEST_CHANGES is **cleared**.
2. **Empty REF search text — RESOLVED.** `placeholder_resolver.dart:108`
   `if (text.isEmpty) return m.group(0)!;` — empty search text is now left
   verbatim instead of leaking the first entry's field. Verified the guard is in
   the implementation, not only asserted by a test. I updated my round-4 audit
   test (which pinned the old behaviour) to guard the fix.
3. **`{S:Name}` case-insensitivity — RESOLVED.** `_customFieldCi` fallback
   (`:126`/`:176`) matches custom-string names case-insensitively, per KeePass.
4. **Test-package mix — RESOLVED.** Generator tests migrated to `package:test`;
   core suite is now consistent.

Good responsiveness — the ensemble is converging on Critic feedback.

## New work reviewed
- **Performer**: password audit engine (`password_audit.dart`) — weak/empty,
  reused, find-similar (Levenshtein), old; plus `{URL:component}` resolver
  placeholders. **APPROVE** (correct, deterministic, `now` injectable).
- **Composer**: read-only write-guard repository (`database_repository.dart`) +
  tests. **APPROVE** on interface; full security sign-off deferred until it is
  wired to the (not-yet-built) encrypted storage layer.

## Critic additions this round
- `test/core/audit/password_audit_audit_test.dart` — adversarial coverage:
  entropy repetition blind-spot, empty≠reused, find-similar **cluster**
  related-uuid wiring, age boundary determinism.

## Findings (non-blocking)
1. **find-similar is O(n²) Levenshtein** — every pair, full edit distance. This
   directly tensions with "Handle Large Databases Effortlessly (250MB+)": on a DB
   with thousands of entries this is quadratic in entries × quadratic in password
   length. Recommend length/prefix bucketing or a candidate cap before Phase 5's
   large-DB work, and a `log()`-style note if results are truncated. Tracked
   against R4 (large-DB performance).
2. **Entropy estimate ignores repetition & sequences.** `length*log2(pool)` rates
   `aaaaaaaaaaaaaa` and `1234567890ab` as non-weak. Acceptable as a documented
   upper bound for now, but a real "Find Weaknesses" feature should add a
   pattern/zxcvbn pass. Pinned via test so the limitation is explicit.

## Honesty note (§0)
Flutter/Dart toolchain still absent; `flutter test` not executed. All new and
amended assertions traced against implementation source by hand. CI runs them
when a Flutter runner exists.

## Consensus
NO. Phase 1's KDBX reader/writer, Argon2/cipher layer, and encrypted-at-rest
storage — the spine of a password manager and the gate for golden interop tests —
remain unbuilt. Phases 5–8 and most of Phase 2 are unstarted. Strong progress on
generators/audit/resolver, but the product is far from shippable.
