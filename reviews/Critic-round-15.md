# Critic Review — Round 15

**Reviewer:** 🎭 Critic
**Date:** 2026-06-14
**Scope:** Duress PIN policy (R5 security sign-off); rolling-backup rotation
(completes my Phase 5 backup-rotation task).

## Duress PIN — SECURITY SIGN-OFF (R5/§4.5): APPROVE
`DuressPolicy` is a clean pure-routing decision and the indistinguishability
design is correct. I verified the two security-critical invariants exhaustively
across every (trigger × hasDecoy) configuration in
`duress_policy_audit_test.dart`:

1. **Always-wipes** — a duress secret sets `wipeRealData=true` in *every* config
   (openDecoy/silentFail × decoy/no-decoy). A coercer cannot configure the wipe
   away, and the `openDecoy→silentFail` degradation when no decoy exists still
   wipes. Conversely, `real`/`decoy`/`none` matches never wipe.
2. **Indistinguishability** — a duress `signal` is always benign
   (`openedDecoy` or `rejected`) and **never** `openedReal`; it is byte-identical
   to its cover (duress+decoy ≡ a normal decoy unlock; silentFail ≡ a wrong
   secret). `wipeRealData` is correctly excluded from `signal`.

**Caveats for the caller (not defects in this pure module), recorded for the
integration that wires it up:**
- The hidden wipe must not introduce **observable latency** — a decoy that opens
  noticeably slower after a duress wipe would break indistinguishability. Wipe
  async / keep open-timing uniform.
- Credential matching (real vs decoy vs duress vs none) MUST be **constant-time**
  — the module's doc says so and delegates it to the crypto layer; I will verify
  that when the crypto body lands (it's the same constant-time requirement I
  flagged for HMAC/master-key checks in R14).

## Rolling-backup rotation — APPROVE (Phase 5 Critic task now COMPLETE)
`BackupRotator` decides deletion/retention. The right safety bias is present:
**`keepLast` is a hard floor** — the N most recent snapshots survive regardless of
`maxAge`/`maxTotalCount` (the `i < keepLast` guard runs before the cap/age
checks), so even a misconfig or clock skew can't delete the user's last recovery
point. Added `backup_rotation_audit_test.dart`: keepLast-floor-when-all-stale,
maxAge-only-beyond-keepLast, maxTotalCount cap, empty input, and the
sortable-name contract.

**Minor:** `nextBackupName` is second-granularity, so two backups within the same
second mint identical names (silent overwrite). Recommend a sub-second component
or a counter suffix. Pinned as a documented-limitation test.

This closes the "Merge-conflict + backup-rotation unit tests (Critic)" task — both
halves now done.

## Open Critic items
- **App Lock F1 (R14, still open):** `maxAttempts>0` guarded only by a debug-only
  `assert`; a release misconfig wipes on first failure. Asked for `throw
  ArgumentError`. Not yet addressed.

## Honesty note (§0)
Toolchain absent; assertions traced against source by hand. Master suite now ~17
files incl. 13 Critic adversarial suites.

## Consensus
NO. Duress + backups signed off, but the decisive blocker stands: the real
`KdbxBodyCipher` (Argon2id + AES/ChaCha + HMAC + protected-value inner-stream) is
still unbuilt, so encrypted-at-rest, zero-knowledge, and KeePassXC golden interop
(§4.6) remain undemonstrable. App Lock F1 hardening also open. Phases 2(partly)/8
and much of 3/5/6/7 unstarted.
