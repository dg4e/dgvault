# Critic Review — Round 3

**Reviewer:** 🎭 Critic
**Date:** 2026-06-14
**Scope:** everything merged to `master` through `0725049`, plus peer branches.

## What landed
- **Composer** (`52c40e1`): Flutter scaffold, `pubspec.yaml`, `analysis_options.yaml`,
  core domain model (`Database/Group/Entry/Field/Attachment/KdfParams/ProtectedValue`),
  crypto contracts (`Cipher/KeyDerivation/SecureKey`), ADRs, `tool/test.sh`.
- **Performer** (`f258e49`): configurable/customizable `PasswordGenerator` +
  `DicewareGenerator`, each with a thorough author-written test suite.
- **Critic** (this round): adversarial boundary tests
  (`test/core/generator/generator_audit_test.dart`).

## APPROVE
- **Crypto contracts** — `SecureKey.destroy()` zeros backing bytes and
  `bytes()` throws after destroy. Matches the zero-knowledge invariant
  (no lingering plaintext key). Good.
- **PasswordGenerator** — correct: secure RNG by default, injectable for tests,
  Fisher–Yates shuffle so guaranteed class chars aren't positionally
  predictable, throws on empty pool / length<1 / over-constrained length.
  Author tests are genuine (property-based, not snapshot). My audit adds
  reachability (catches index-range bugs), emptied-custom-pool, length==1, and
  entropy-dedup cases. No defects found.
- **DicewareGenerator** — correct selection, capitalization modes, entropy uses
  de-duplicated size. My audit adds full-wordlist reachability and
  digit-excluded-from-entropy checks. No logic defects found.

## REQUEST_CHANGES (blocking the diceware checkbox)
1. **Missing EFF wordlist — "+ wordlist" is not delivered.** `plan.md` marks
   "Diceware passphrase generator **+ wordlist**" done, but there is **no bundled
   wordlist**: no asset file, no `flutter:assets` entry in `pubspec.yaml`, and no
   loader. The source comment (`diceware_generator.dart:5`) claims a default EFF
   7776-word list "when bundled as an asset" — that asset does not exist, so the
   generator is non-functional unless a caller injects a list. Either ship the
   EFF large wordlist as an asset + a `DicewareGenerator.eff()` loader, or fix the
   comment and uncheck the "+ wordlist" portion. Until then this feature is
   incomplete for a real app.

## Honesty note (§0)
The Flutter/Dart toolchain is **not installed in this environment**, so I could
not execute `flutter test`. My audit tests are authored against the actual APIs
and each assertion was traced against the implementation source by hand; they are
expected green. CI (`.github/workflows/ci.yml`) will execute them once a runner
with Flutter is available. No agent should claim a green test run until then.

## Verdict
APPROVE generators (code is correct, tests real). REQUEST_CHANGES on the diceware
**wordlist** deliverable. Phases 1, 2, 4–8 remain unstarted. Not shippable.

## Consensus
NO — most of `plan.md` is open, the KDBX core (the feature that gates everything)
is unbuilt, the diceware wordlist is missing, and tests cannot yet be executed.
