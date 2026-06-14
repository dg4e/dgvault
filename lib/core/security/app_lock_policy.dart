// dgvault — App Lock: delete-all-on-failed-attempts policy (pure logic).
//
// Tracks consecutive failed unlock attempts and, when a configured threshold is
// reached, signals that the local database(s) must be wiped ("App Lock — Delete
// All on Fails"). The counter is held behind a [FailedAttemptStore] so it can be
// persisted (Keychain/Keystore/secure prefs) — critical: the count MUST survive
// app restarts, or an attacker bypasses the limit by relaunching between tries.
//
// Pure and deterministic (no crypto, no I/O of its own); the actual wipe and the
// persistent store are the platform/data layer's job. The policy only decides.

/// Persistent storage for the consecutive-failure counter.
abstract interface class FailedAttemptStore {
  int get failedCount;
  set failedCount(int value);
}

/// Default in-memory store (tests / sessions without persistence). Production
/// must back this with secure, persistent storage.
class InMemoryFailedAttemptStore implements FailedAttemptStore {
  @override
  int failedCount = 0;
}

/// Outcome of an unlock attempt.
class UnlockAttemptResult {
  const UnlockAttemptResult({
    required this.success,
    required this.remainingAttempts,
    required this.shouldWipe,
    required this.lockedOut,
  });

  final bool success;

  /// Attempts left before exhaustion (0 once exhausted).
  final int remainingAttempts;

  /// The caller must irreversibly wipe local data now (threshold reached and
  /// delete-on-fail is enabled).
  final bool shouldWipe;

  /// The attempt limit has been reached (whether or not wiping is enabled).
  final bool lockedOut;
}

class AppLockPolicy {
  AppLockPolicy({
    required this.store,
    this.maxAttempts = 10,
    this.wipeOnExhaustion = true,
  }) : assert(maxAttempts > 0, 'maxAttempts must be positive');

  final FailedAttemptStore store;

  /// Consecutive failures allowed before the limit is hit.
  final int maxAttempts;

  /// When true, reaching the limit signals a destructive wipe; when false the
  /// limit only reports lock-out (e.g. cool-down UX without data destruction).
  final bool wipeOnExhaustion;

  int get failedCount => store.failedCount;

  int get remainingAttempts {
    final r = maxAttempts - store.failedCount;
    return r < 0 ? 0 : r;
  }

  bool get isLockedOut => store.failedCount >= maxAttempts;

  /// Record a wrong master password / PIN. Increments the persistent counter
  /// and reports whether the limit is now exhausted (and a wipe is due).
  UnlockAttemptResult recordFailure() {
    store.failedCount = store.failedCount + 1;
    final exhausted = store.failedCount >= maxAttempts;
    return UnlockAttemptResult(
      success: false,
      remainingAttempts: remainingAttempts,
      shouldWipe: exhausted && wipeOnExhaustion,
      lockedOut: exhausted,
    );
  }

  /// Record a correct unlock. Resets the counter so the budget is restored.
  UnlockAttemptResult recordSuccess() {
    store.failedCount = 0;
    return UnlockAttemptResult(
      success: true,
      remainingAttempts: maxAttempts,
      shouldWipe: false,
      lockedOut: false,
    );
  }

  /// Manually reset the counter (e.g. after a successful recovery flow).
  void reset() => store.failedCount = 0;
}
