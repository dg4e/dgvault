// dgvault — PIN unlock state machine.
//
// Ties [KeyVault] (the PIN-wrapped master key) to [AppLockPolicy] (the
// persistent failed-attempt limit + optional delete-on-fail). A correct PIN
// unwraps and returns the master key and resets the counter; a wrong PIN
// increments the persistent counter and, on exhaustion, reports lock-out and/or
// a due wipe. PIN matching is the AEAD tag inside KeyVault (constant-time; no
// hand-rolled comparison). Biometric unlock can reuse the same flow with a
// device-released secret instead of a typed PIN.
//
// Pure orchestration over injected components — fully unit-testable.

import 'dart:typed_data';

import '../crypto/cipher.dart';
import '../crypto/key_derivation.dart';
import '../crypto/secure_key.dart';
import 'app_lock_policy.dart';
import 'key_vault.dart';

class PinUnlockResult {
  const PinUnlockResult({
    required this.unlocked,
    required this.masterKey,
    required this.remainingAttempts,
    required this.lockedOut,
    required this.shouldWipe,
  });

  final bool unlocked;

  /// The unwrapped master key on success; null otherwise. Caller owns disposal.
  final SecureKey? masterKey;

  /// Attempts left before exhaustion.
  final int remainingAttempts;

  /// The attempt limit has been reached (no more tries allowed).
  final bool lockedOut;

  /// The caller must irreversibly wipe local data now (delete-on-fail tripped).
  final bool shouldWipe;
}

class PinUnlock {
  PinUnlock({required this.vault, required this.lock});

  final KeyVault vault;
  final AppLockPolicy lock;

  /// Whether a PIN has been enrolled (a wrapped key exists).
  Future<bool> get isEnrolled => vault.isEnrolled;

  /// Already locked out before this attempt — surface the wipe-pending state so
  /// an interrupted wipe is retried before anything is opened (Critic R14 F2).
  bool get isLockedOut => lock.isLockedOut;
  bool get isWipePending => lock.isWipePending;

  /// Try [pin]. Does not attempt a derivation when already locked out.
  Future<PinUnlockResult> attempt(Uint8List pin) async {
    if (lock.isLockedOut) {
      return PinUnlockResult(
        unlocked: false,
        masterKey: null,
        remainingAttempts: 0,
        lockedOut: true,
        shouldWipe: lock.isWipePending,
      );
    }

    final secret = CompositeCredential(password: pin);
    try {
      final key = await vault.unlock(secret);
      final r = lock.recordSuccess();
      return PinUnlockResult(
        unlocked: true,
        masterKey: key,
        remainingAttempts: r.remainingAttempts,
        lockedOut: false,
        shouldWipe: false,
      );
    } on CipherAuthenticationException {
      return _onWrongPin();
    } on KeyVaultException {
      // A corrupt/missing blob is not a wrong-PIN guess; surface without
      // consuming an attempt.
      rethrow;
    }
  }

  PinUnlockResult _onWrongPin() {
    final r = lock.recordFailure();
    return PinUnlockResult(
      unlocked: false,
      masterKey: null,
      remainingAttempts: r.remainingAttempts,
      lockedOut: r.lockedOut,
      shouldWipe: r.shouldWipe,
    );
  }
}
