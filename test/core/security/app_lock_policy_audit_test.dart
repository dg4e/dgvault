// Critic-owned security audit for the App Lock delete-all-on-fails policy.
//
// This is a DURESS / destructive trigger (R5 — Critic sign-off required). Performer's
// suite covers budget/decrement/wipe-at-exhaustion/cool-down/persistence/clamp/
// reject-non-positive. These add the interrupted-wipe edges: a wipe signalled but
// not completed (app killed) must still fire, and a policy reconstructed over an
// already-exhausted persistent store must report locked-out.
//
// Toolchain not installed here; assertions traced against source by hand
// (see reviews/Critic-round-14.md).

import 'package:dgvault/core/security/app_lock_policy.dart';
import 'package:test/test.dart';

void main() {
  group('interrupted-wipe resilience', () {
    test('wipe re-fires on the next failure when already past exhaustion', () {
      // Simulates: threshold reached, wipe signalled, app killed before wiping,
      // attacker relaunches and tries again — the next failure must re-signal.
      final store = InMemoryFailedAttemptStore()..failedCount = 10;
      final policy = AppLockPolicy(store: store); // maxAttempts 10, wipe on
      final r = policy.recordFailure();
      expect(r.shouldWipe, isTrue, reason: 'wipe must re-signal past exhaustion');
      expect(r.lockedOut, isTrue);
    });

    test('a policy rebuilt over an exhausted store reports locked-out', () {
      // F2 note: there is no standalone wipe-pending signal at startup; the
      // caller must derive "wipe now" from isLockedOut && wipeOnExhaustion. This
      // pins the current behaviour so the gap is visible (see review).
      final store = InMemoryFailedAttemptStore()..failedCount = 12;
      final policy = AppLockPolicy(store: store, maxAttempts: 10);
      expect(policy.isLockedOut, isTrue);
      expect(policy.remainingAttempts, 0);
    });
  });

  group('threshold edge', () {
    test('the wipe fires exactly at the configured attempt, not before', () {
      final policy =
          AppLockPolicy(store: InMemoryFailedAttemptStore(), maxAttempts: 3);
      expect(policy.recordFailure().shouldWipe, isFalse); // 1
      expect(policy.recordFailure().shouldWipe, isFalse); // 2
      final third = policy.recordFailure(); // 3 == maxAttempts
      expect(third.shouldWipe, isTrue);
      expect(third.remainingAttempts, 0);
    });

    test('a success before exhaustion fully restores the budget', () {
      final policy =
          AppLockPolicy(store: InMemoryFailedAttemptStore(), maxAttempts: 3);
      policy.recordFailure();
      policy.recordFailure();
      policy.recordSuccess();
      // back to full — two more failures must NOT wipe.
      expect(policy.recordFailure().shouldWipe, isFalse);
      expect(policy.recordFailure().shouldWipe, isFalse);
      expect(policy.remainingAttempts, 1);
    });
  });
}
