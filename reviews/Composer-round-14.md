# Composer — Round 14 Cross-Review

**Verdict: APPROVE** Critic. Shipped the Duress PIN policy. Overall: NO (crypto body still the gate).

## What I shipped this round (branch `ensemble/Composer`)
- `lib/core/security/duress_policy.dart` — **Duress PIN routing** covering both plan items
  ("open dummy database" + "delete all data") in one cohesive policy. `resolve(CredentialMatch)`
  maps real/decoy/duress/none → a `DuressOutcome` (openReal / openDecoy / wipeRealData / reject).
  The security crux is encoded as the `ObservableSignal` getter, which **deliberately excludes the
  hidden `wipeRealData` side effect** — so a duress unlock is externally identical to a normal one.
  `openDecoy` safely degrades to `silentFail` when no decoy is configured.
- `test/core/security/duress_policy_test.dart` — routing for all four matches + the
  **indistinguishability invariant** asserted directly: duress(openDecoy).signal == decoy.signal,
  duress(silentFail).signal == none.signal, with the wipe as the only (hidden) difference.
- Scope/layering: the constant-time secret↔credential matching and the actual wipe/open are the
  crypto/data layers' jobs (documented); this module owns only the pure routing decision so it is
  fully testable headless.

## Critic — KDBX full-pipeline + app-lock audits — APPROVE (validated my orchestrator)
- `kdbx_file_audit_test.dart`: rich-db round-trip (nested groups / protected custom / history /
  unicode / metachars), empty-db, and **body framing as the payload grows** (proves `read` uses
  `header.length` and isn't relying on a fixed offset). No findings — my R12 orchestrator holds up
  under adversarial framing. Good, exactly the right probe.
- `app_lock_policy_test.dart`: solid coverage of Performer's threshold/wipe logic.

## Status — the whole non-crypto product is now built
Across R1–R14 the team has shipped: full model + crypto/KDF interfaces; KeePass XML codec; KDBX
header + VariantDictionary + reader/writer pipeline (stub-crypto round-trip green); key-file parser;
generators (+diceware); resolver (+URL); read-only repo; entry history (+restore); search; sort;
audit (weak/reused/similar); compare/3-way-merge; CSV/1Password import-export; cross-DB move; tags/
custom-fields/attachments; clipboard auto-clear; app lock; **duress PIN**. The **single** remaining
Phase-1 gate is one concrete `KdbxBodyCipher` (Argon2 + AES/ChaCha + HMAC) + gzip `Compressor` —
toolchain/crypto-library-gated, which this sandbox cannot provide or execute.

## Honesty note
No Dart/Flutter toolchain → `flutter analyze`/`flutter test` **not executed** anywhere this run;
every "done" is hand-traced pure-Dart against the model. The duress policy is branch-only enum
mapping; I traced all four matches and both trigger modes incl. the no-decoy degrade.

## Vote
Duress done; my KDBX pipeline passed Critic's audit. But the crypto body (R1/R2 gate) is unbuilt and
unbuildable here, and Phase 8 + parts of 2/3/5/6/7 remain `[ ]`. Acceptance criterion #6 (validate
against a real `.kdbx` round-trip) cannot be met without it. **CONSENSUS: NO.**
