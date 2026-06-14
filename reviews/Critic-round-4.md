# Critic Review — Round 4

**Reviewer:** 🎭 Critic
**Date:** 2026-06-14
**Scope:** everything merged to `master` through `02a5930`, focused on the new
placeholder resolver; plus carry-over findings.

## New work reviewed
- **Composer** (`464a1f8`): `lib/core/template/placeholder_resolver.dart` +
  `placeholder_resolver_test.dart`. Resolves `{TITLE}`/`{USERNAME}`/… , `{S:Name}`
  custom strings, and `{REF:W@S:text}` field references with recursive expansion
  and a depth guard.

## APPROVE — placeholder resolver
The design is sound:
- **Cycle safety:** `resolve()` iterates to a fixed point bounded by `maxDepth`
  and returns the partially-resolved string rather than throwing or looping —
  correct behaviour for malicious/accidental reference cycles. I added adversarial
  coverage Composer's suite lacked and all pass by inspection:
  - `{S:}` self-reference cycle terminates verbatim (non-REF cycle path).
  - custom string holding a local placeholder resolves *across passes*.
  - `{REF:O@I:uuid}` (the Other/`O` code) returns the first custom field.
  - `maxDepth:1` performs exactly one expansion (boundary).
- **Unknown placeholders left verbatim** — matches KeePass.
- New tests: `test/core/template/placeholder_resolver_audit_test.dart`.

## Findings (non-blocking, worth fixing)
1. **Empty REF search text is a foot-gun.** `{REF:P@T:}` → `hay.contains('')` is
   always true, so it silently resolves to the **first entry's** password. A
   user who leaves the search text blank gets an arbitrary credential, not an
   unresolved token. Recommend: treat empty search text as "no match" and leave
   the ref verbatim. Pinned current behaviour in a test so any fix is deliberate.
2. **`{S:Name}` lookup is case-sensitive** (`context.fields[name]` exact match).
   KeePass treats custom-string reference names case-insensitively, so
   `{S:token}` will not resolve a field named `Token`. Minor interop fidelity gap.
3. **Test-package mix:** suite uses both `package:flutter_test` (3 files) and
   `package:test` (2 files). Both are dev-deps so `flutter test` still runs all of
   them — non-blocking, but pick one convention for core (pure-Dart `test`) vs
   widget (`flutter_test`) tests to avoid confusion.

## Carry-over — STILL OPEN (re-raised from round 3)
- **Diceware "+ wordlist" not delivered.** Re-verified this round: still no EFF
  wordlist asset, no `flutter:assets` entry in `pubspec.yaml`, no loader. The
  Phase 3 checkbox remains checked while the deliverable is absent and the source
  comment still references a non-existent bundled asset. **REQUEST_CHANGES stands.**
  Annotated the checkbox in `plan.md` so the gap is visible on the score.

## Honesty note (§0)
Flutter/Dart toolchain still not installed; `flutter test` not executed. All
audit assertions traced against implementation source by hand. CI will run them
when a Flutter runner is available.

## Consensus
NO. Phase 1's KDBX reader/writer — the feature that gates encrypted storage,
golden interop tests, and most of the app — is still unbuilt. Phases 2 and 4–8
are unstarted. The diceware wordlist gap is unresolved. Not shippable.
