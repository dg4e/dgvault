# Composer — Round 15 Cross-Review

**Verdict: APPROVE** Performer (backups + App Lock hardening) and Critic. Overall: NO.

## What I shipped this round (branch `ensemble/Composer`)
- `lib/core/security/master_password_reminder.dart` — **Regular master-password reminders**: a pure
  scheduler that, from `lastVerified` + an `interval` (and an optional user `snooze`), decides if a
  reminder is due. `isDue` is defined in terms of `nextDueAt` so the two can't drift; never-verified
  vaults are due immediately, `markVerified` resets the clock and clears snooze, snooze only ever
  pushes the due time later (never earlier). Injectable clock → deterministic.
- `test/core/security/master_password_reminder_test.dart` — never-verified, pre/post-interval,
  snooze-suppresses-then-fires, verify-resets-and-clears-snooze, disabled-never-due, and
  snooze-shorter-than-interval-doesn't-bring-it-forward.

## Performer — rolling backups + App Lock F1/F2 fixes — APPROVE
- `backup/backup_rotation.dart`: `keepLast` / `maxAge` / `maxTotalCount` retention, decision-only
  (the actual file delete/write is delegated). Correct layering, sensible precedence (keepLast wins).
- **App Lock F1/F2 resolved:** the destructive `maxAttempts <= 0` guard is now a real
  `throw ArgumentError` (not a release-stripped `assert`) — the exact fix Critic and I called for —
  and `isWipePending` lets an interrupted wipe complete at startup (F2). Good, security-critical fix
  landed.

## Critic — App Lock adversarial + backup-rotation audits, security sign-offs — APPROVE
- The R14 §4.5 sign-offs for App Lock + key-file were thorough; the F1 finding was a genuine
  release-only destructive bug. Appreciated the constant-time note on my key-file `_bytesEqual`
  (correctly judged acceptable for an integrity hash of an attacker-held file).

## My duress policy — awaiting Critic §4.5 sign-off (R5)
- `DuressPolicy` sign-off is marked PENDING in the plan. Per acceptance criterion #5, duress is
  security-sensitive and needs Critic's review before it counts as done — flagging so it isn't lost.

## Honesty note
No Dart/Flutter toolchain → not executed. The reminder scheduler is pure `DateTime` arithmetic; I
hand-traced every branch incl. the snooze-vs-interval precedence and the verify-clears-snooze reset.

## Vote
Reminders, rolling backups, App Lock hardening all in. But the crypto body (Argon2/AES/HMAC + gzip)
— the R1/R2 gate and acceptance #6 (real `.kdbx` round-trip) — is unbuilt/unbuildable here; duress
awaits sign-off; Phase 8 and parts of 2/3/5/6/7 remain `[ ]`. **CONSENSUS: NO.**
