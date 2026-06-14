import 'package:dgvault/core/security/app_lock_policy.dart';
import 'package:test/test.dart';

void main() {
  group('AppLockPolicy', () {
    test('fresh policy has full budget and is not locked out', () {
      final p = AppLockPolicy(store: InMemoryFailedAttemptStore(), maxAttempts: 3);
      expect(p.remainingAttempts, 3);
      expect(p.isLockedOut, isFalse);
    });

    test('each failure decrements remaining; wipe only at exhaustion', () {
      final p = AppLockPolicy(store: InMemoryFailedAttemptStore(), maxAttempts: 3);
      final r1 = p.recordFailure();
      expect(r1.remainingAttempts, 2);
      expect(r1.shouldWipe, isFalse);
      expect(r1.lockedOut, isFalse);

      final r2 = p.recordFailure();
      expect(r2.remainingAttempts, 1);
      expect(r2.shouldWipe, isFalse);

      final r3 = p.recordFailure();
      expect(r3.remainingAttempts, 0);
      expect(r3.lockedOut, isTrue);
      expect(r3.shouldWipe, isTrue, reason: 'threshold reached → wipe');
    });

    test('wipeOnExhaustion=false locks out without signalling a wipe', () {
      final p = AppLockPolicy(
        store: InMemoryFailedAttemptStore(),
        maxAttempts: 2,
        wipeOnExhaustion: false,
      );
      p.recordFailure();
      final r = p.recordFailure();
      expect(r.lockedOut, isTrue);
      expect(r.shouldWipe, isFalse);
    });

    test('success resets the counter and restores the budget', () {
      final p = AppLockPolicy(store: InMemoryFailedAttemptStore(), maxAttempts: 3);
      p.recordFailure();
      p.recordFailure();
      final ok = p.recordSuccess();
      expect(ok.success, isTrue);
      expect(ok.remainingAttempts, 3);
      expect(p.failedCount, 0);
    });

    test('counter persists across policy instances (simulated restart)', () {
      final store = InMemoryFailedAttemptStore();
      AppLockPolicy(store: store, maxAttempts: 3).recordFailure();
      AppLockPolicy(store: store, maxAttempts: 3).recordFailure();
      // A fresh policy over the same (persistent) store sees the accrued count —
      // an attacker cannot reset the budget by relaunching the app.
      final p3 = AppLockPolicy(store: store, maxAttempts: 3);
      expect(p3.failedCount, 2);
      expect(p3.remainingAttempts, 1);
      expect(p3.recordFailure().shouldWipe, isTrue);
    });

    test('remaining clamps at zero past the limit', () {
      final p = AppLockPolicy(store: InMemoryFailedAttemptStore(), maxAttempts: 1);
      p.recordFailure();
      p.recordFailure(); // beyond limit
      expect(p.remainingAttempts, 0);
      expect(p.isLockedOut, isTrue);
    });

    test('rejects non-positive maxAttempts with a real throw (not debug assert)', () {
      // Must throw in release too — maxAttempts<=0 would wipe on first failure.
      expect(() => AppLockPolicy(store: InMemoryFailedAttemptStore(), maxAttempts: 0),
          throwsA(isA<ArgumentError>()));
      expect(() => AppLockPolicy(store: InMemoryFailedAttemptStore(), maxAttempts: -1),
          throwsA(isA<ArgumentError>()));
    });

    group('isWipePending (interrupted-wipe recovery)', () {
      test('true once the persisted counter has reached the limit', () {
        final store = InMemoryFailedAttemptStore();
        final p = AppLockPolicy(store: store, maxAttempts: 3);
        expect(p.isWipePending, isFalse);
        p.recordFailure();
        p.recordFailure();
        expect(p.isWipePending, isFalse);
        p.recordFailure(); // exhausts
        expect(p.isWipePending, isTrue);
        // Survives a restart: a fresh policy over the same store still owes the wipe.
        expect(AppLockPolicy(store: store, maxAttempts: 3).isWipePending, isTrue);
      });

      test('false when delete-on-fail is disabled', () {
        final store = InMemoryFailedAttemptStore()..failedCount = 99;
        final p = AppLockPolicy(
            store: store, maxAttempts: 3, wipeOnExhaustion: false);
        expect(p.isWipePending, isFalse);
      });

      test('cleared after a successful unlock resets the counter', () {
        final store = InMemoryFailedAttemptStore();
        final p = AppLockPolicy(store: store, maxAttempts: 1);
        p.recordFailure();
        expect(p.isWipePending, isTrue);
        p.recordSuccess();
        expect(p.isWipePending, isFalse);
      });
    });
  });
}
