// dgvault — Argon2 key derivation (vetted primitive: pointycastle).
//
// Implements [KeyDerivation] for KDBX4's Argon2d / Argon2id KDFs. No hand-rolled
// crypto: the Argon2 core is pointycastle's `Argon2BytesGenerator`; this file
// only builds the KeePass composite key and maps [KdfParams] onto Argon2's
// parameters.
//
// Composite key (KeePass 2.x / KDBX):
//   each present factor contributes a 32-byte value —
//     password           → SHA-256(passwordBytes)
//     key file           → its 32-byte key (already hashed by the key-file
//                          parser; SHA-256'd here only if it isn't 32 bytes)
//     challenge-response → SHA-256(response)
//   compositeKey = SHA-256(concat of the factor values, in the order above)
// The Argon2 transform is then applied to `compositeKey` with the header salt,
// yielding the 32-byte transformed key. (The masterSeed mixing that produces the
// actual cipher/HMAC keys is the KDBX body cipher's job — see kdbx4_body_cipher.)

import 'dart:typed_data';

import 'package:pointycastle/export.dart' as pc;

import '../../model/kdf_params.dart';
import '../key_derivation.dart';
import '../secure_key.dart';
import 'composite_key.dart';

class Argon2KeyDerivation implements KeyDerivation {
  const Argon2KeyDerivation({this.keyLength = 32});

  /// Derived-key length in bytes (32 for AES-256 / ChaCha20).
  final int keyLength;

  @override
  bool supports(KdfAlgorithm algorithm) =>
      algorithm == KdfAlgorithm.argon2d || algorithm == KdfAlgorithm.argon2id;

  @override
  Future<SecureKey> deriveKey(
    CompositeCredential credential,
    KdfParams params,
    Uint8List salt,
  ) async {
    if (!credential.hasAnyFactor) {
      throw ArgumentError('credential carries no factors');
    }
    if (!supports(params.algorithm)) {
      throw ArgumentError('unsupported KDF algorithm ${params.algorithm}');
    }
    if (!params.isValid) {
      // Rejected BEFORE allocating Argon2's memory blocks: a hostile header can
      // otherwise demand multi-GiB memory / pathological passes to OOM on open.
      throw ArgumentError(
        'rejected KDF parameters: out of accepted bounds '
        '(memory <= ${KdfParams.maxMemoryKib} KiB, '
        'Argon2 passes <= ${KdfParams.maxArgon2Iterations}, '
        'lanes <= ${KdfParams.maxParallelism})',
      );
    }

    final composite = keepassCompositeKey(credential);

    final type = params.algorithm == KdfAlgorithm.argon2d
        ? pc.Argon2Parameters.ARGON2_d
        : pc.Argon2Parameters.ARGON2_id;
    final argonParams = pc.Argon2Parameters(
      type,
      salt,
      desiredKeyLength: keyLength,
      iterations: params.iterations,
      memory: params.memoryKib, // KiB blocks (matches pointycastle's `memory`)
      lanes: params.parallelism ?? 1,
      version: params.version,
    );

    final gen = pc.Argon2BytesGenerator()..init(argonParams);
    final out = Uint8List(keyLength);
    gen.deriveKey(composite, 0, out, 0);
    return HeapSecureKey(out);
  }
}
