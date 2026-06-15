// dgvault — authenticated symmetric ciphers (vetted primitives: pointycastle).
//
// Implements the [Cipher] contract with AEAD constructions, so a wrong key or
// any tampering fails as an authentication error (never silently-wrong
// plaintext). Used by dgvault's own encrypted containers (encrypted CSV,
// encrypted-at-rest). No hand-rolled crypto — AES-256-GCM is
// `GCMBlockCipher(AESEngine())`; ChaCha20-Poly1305 is the pointycastle AEAD.
//
// NOTE on KDBX interop: the KDBX *file* body uses AES-256-CBC / ChaCha20 with a
// separate HMAC-SHA-256 block stream — that construction lives in the KDBX body
// cipher, not here. These AEAD ciphers are dgvault-container ciphers; the
// [DatabaseCipher] label only names the underlying block/stream primitive.

import 'dart:typed_data';

import 'package:pointycastle/export.dart' as pc;

import '../../model/database.dart';
import '../cipher.dart';
import '../secure_key.dart';

/// Thrown when authenticated decryption fails (wrong key or tampered input).
class CipherAuthenticationException implements Exception {
  CipherAuthenticationException(this.message);
  final String message;
  @override
  String toString() => 'CipherAuthenticationException: $message';
}

/// Shared AEAD orchestration over a pointycastle [pc.AEADCipher].
abstract class _AeadCipher implements Cipher {
  static const int _macBits = 128; // 16-byte tag, appended to the ciphertext.

  /// A fresh, uninitialised AEAD cipher instance per call (they are stateful).
  /// Typed `dynamic` because pointycastle's `GCMBlockCipher` (an
  /// `AEADBlockCipher`) and `ChaCha20Poly1305` (an `AEADCipher`) share the
  /// init/getOutputSize/processBytes/doFinal shape but no common supertype.
  dynamic _newCipher();

  @override
  int get ivLength => 12; // 96-bit nonce (GCM / RFC 8439 standard).

  @override
  Future<Uint8List> encrypt({
    required SecureKey key,
    required Uint8List iv,
    required Uint8List plaintext,
  }) async =>
      _run(forEncryption: true, key: key, iv: iv, input: plaintext);

  @override
  Future<Uint8List> decrypt({
    required SecureKey key,
    required Uint8List iv,
    required Uint8List ciphertext,
  }) async =>
      _run(forEncryption: false, key: key, iv: iv, input: ciphertext);

  @override
  Stream<Uint8List> decryptStream({
    required SecureKey key,
    required Uint8List iv,
    required Stream<List<int>> ciphertext,
  }) async* {
    // Buffering decrypt: AEAD authenticates the whole message, so it cannot be
    // emitted incrementally without a chunked framing (that is the KDBX block
    // stream's role). For 250MB+ DBs, prefer the KDBX block cipher.
    final buf = BytesBuilder();
    await for (final chunk in ciphertext) {
      buf.add(chunk);
    }
    yield await decrypt(key: key, iv: iv, ciphertext: buf.toBytes());
  }

  Uint8List _run({
    required bool forEncryption,
    required SecureKey key,
    required Uint8List iv,
    required Uint8List input,
  }) {
    if (iv.length != ivLength) {
      throw ArgumentError('iv must be $ivLength bytes, got ${iv.length}');
    }
    final cipher = _newCipher()
      ..init(
        forEncryption,
        pc.AEADParameters(
          pc.KeyParameter(key.bytes()),
          _macBits,
          iv,
          Uint8List(0), // no associated data
        ),
      );
    final out = Uint8List(cipher.getOutputSize(input.length) as int);
    try {
      var len = cipher.processBytes(input, 0, input.length, out, 0) as int;
      len += cipher.doFinal(out, len) as int;
      return Uint8List.sublistView(out, 0, len);
    } on pc.InvalidCipherTextException catch (e) {
      // GCM signals a bad tag this way.
      throw CipherAuthenticationException(e.message);
    } on ArgumentError catch (e) {
      // ChaCha20-Poly1305 signals a failed MAC / truncated input as an
      // ArgumentError ('mac check ... failed', 'data too short'). On the decrypt
      // path these are authentication failures, not programming errors.
      if (!forEncryption) {
        throw CipherAuthenticationException('authentication failed: ${e.message}');
      }
      rethrow;
    }
  }
}

/// AES-256 in GCM mode (authenticated). Key must be 32 bytes.
class AesGcmCipher extends _AeadCipher {
  @override
  DatabaseCipher get algorithm => DatabaseCipher.aes256;

  @override
  dynamic _newCipher() => pc.GCMBlockCipher(pc.AESEngine());
}

/// ChaCha20-Poly1305 (RFC 8439, authenticated). Key must be 32 bytes.
class ChaCha20Poly1305Cipher extends _AeadCipher {
  @override
  DatabaseCipher get algorithm => DatabaseCipher.chacha20;

  @override
  dynamic _newCipher() =>
      pc.ChaCha20Poly1305(pc.ChaCha7539Engine(), pc.Poly1305());
}
