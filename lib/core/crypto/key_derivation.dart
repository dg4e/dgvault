import 'dart:typed_data';

import '../model/kdf_params.dart';
import 'secure_key.dart';

/// The composite credential used to unlock a database. Any combination may be
/// present (master password, key file, YubiKey challenge-response). At least
/// one factor is required.
class CompositeCredential {
  CompositeCredential({
    this.password,
    this.keyFile,
    this.challengeResponse,
  });

  /// UTF-8 master password bytes (caller wipes after use).
  final Uint8List? password;

  /// Raw key-file contents (or its parsed 32-byte key for XML key files).
  final Uint8List? keyFile;

  /// YubiKey HMAC-SHA1 challenge-response output, when a hardware factor is set.
  final Uint8List? challengeResponse;

  bool get hasAnyFactor =>
      password != null || keyFile != null || challengeResponse != null;
}

/// Derives a [SecureKey] from a [CompositeCredential] using [KdfParams].
/// Implementations MUST use vetted Argon2/AES-KDF primitives only.
abstract interface class KeyDerivation {
  /// True if this implementation can service the given [params.algorithm].
  bool supports(KdfAlgorithm algorithm);

  /// Derive the master key. Throws [ArgumentError] on invalid params or when
  /// the credential carries no factors.
  Future<SecureKey> deriveKey(
    CompositeCredential credential,
    KdfParams params,
    Uint8List salt,
  );
}
