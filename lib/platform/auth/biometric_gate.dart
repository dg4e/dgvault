// dgvault — biometric / device-credential gate (local_auth).
//
// Gates release of the PIN-wrapped master key behind Face ID / Touch ID /
// fingerprint. Flow: `authenticate()` → on success the caller reads the wrapped
// key from `SecureStore` and unlocks it via `KeyVault` (the same wrapping used
// by PIN unlock — biometrics only gate the *release*).
//
// PLATFORM-GATED: needs a real device with enrolled biometrics; cannot be
// unit-tested in the headless VM. The unlock *logic* it feeds (KeyVault +
// PinUnlock) is fully tested in core.

import 'package:local_auth/local_auth.dart';

class BiometricGate {
  BiometricGate({LocalAuthentication? auth})
      : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  /// True when the device has biometric hardware (or a device credential) the
  /// app can use.
  Future<bool> get isAvailable async =>
      await _auth.isDeviceSupported() &&
      (await _auth.canCheckBiometrics || await _auth.isDeviceSupported());

  Future<List<BiometricType>> availableBiometrics() =>
      _auth.getAvailableBiometrics();

  /// Prompt the user. Returns true only on a successful biometric/credential
  /// check. [biometricOnly] disables the device-PIN fallback.
  Future<bool> authenticate({
    String reason = 'Unlock your vault',
    bool biometricOnly = false,
  }) {
    return _auth.authenticate(
      localizedReason: reason,
      options: AuthenticationOptions(
        biometricOnly: biometricOnly,
        stickyAuth: true,
      ),
    );
  }
}
