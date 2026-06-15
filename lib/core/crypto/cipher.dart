import 'dart:typed_data';

import '../model/database.dart';
import 'secure_key.dart';

/// Thrown by [Cipher.decrypt] when authentication fails — a wrong key or any
/// tampering. Defined on the interface so callers can catch it without
/// depending on a concrete cipher implementation.
class CipherAuthenticationException implements Exception {
  CipherAuthenticationException(this.message);
  final String message;
  @override
  String toString() => 'CipherAuthenticationException: $message';
}

/// Authenticated/streamed symmetric cipher for the outer database payload.
///
/// Implementations wrap vetted AES-256 (CBC+HMAC per KDBX) and ChaCha20
/// primitives. The streaming API supports large databases (R4) without holding
/// the whole plaintext in memory.
abstract interface class Cipher {
  DatabaseCipher get algorithm;

  /// Required IV/nonce length in bytes.
  int get ivLength;

  /// Encrypt [plaintext] under [key] with [iv]. Returns the ciphertext.
  Future<Uint8List> encrypt({
    required SecureKey key,
    required Uint8List iv,
    required Uint8List plaintext,
  });

  /// Decrypt [ciphertext]. Throws on authentication failure.
  Future<Uint8List> decrypt({
    required SecureKey key,
    required Uint8List iv,
    required Uint8List ciphertext,
  });

  /// Streaming decrypt over chunks for 250MB+ databases. Yields plaintext
  /// chunks as they are produced.
  Stream<Uint8List> decryptStream({
    required SecureKey key,
    required Uint8List iv,
    required Stream<List<int>> ciphertext,
  });
}

/// Resolves the concrete [Cipher] for a database's declared algorithm.
abstract interface class CipherRegistry {
  Cipher forAlgorithm(DatabaseCipher algorithm);
}
