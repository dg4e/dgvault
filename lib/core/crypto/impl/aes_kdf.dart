// dgvault — AES-KDF key derivation (legacy KDBX, vetted primitive: pointycastle).
//
// KeePass's pre-Argon2 KDF. Transforms the composite key by encrypting it with
// AES-256 (ECB, the transform seed as the key) for `rounds` iterations, then
// SHA-256:
//
//   t = compositeKey                       (32 bytes = two AES blocks)
//   repeat `rounds` times: t = AES256-ECB-encrypt(key=transformSeed, t)
//   transformedKey = SHA-256(t)
//
// Provided for reading legacy databases; Argon2 is the default for new ones.
// No hand-rolled crypto — the block transform is pointycastle's AESEngine.

import 'dart:typed_data';

import 'package:pointycastle/export.dart' as pc;

import '../../model/kdf_params.dart';
import '../key_derivation.dart';
import '../secure_key.dart';
import 'composite_key.dart';

class AesKdfKeyDerivation implements KeyDerivation {
  const AesKdfKeyDerivation();

  @override
  bool supports(KdfAlgorithm algorithm) => algorithm == KdfAlgorithm.aesKdf;

  @override
  Future<SecureKey> deriveKey(
    CompositeCredential credential,
    KdfParams params,
    Uint8List salt,
  ) async {
    if (!supports(params.algorithm)) {
      throw ArgumentError('unsupported KDF algorithm ${params.algorithm}');
    }
    if (params.iterations < 1) {
      throw ArgumentError('AES-KDF rounds must be >= 1');
    }
    if (salt.length != 32) {
      throw ArgumentError('AES-KDF transform seed must be 32 bytes');
    }

    final t = keepassCompositeKey(credential); // 32 bytes (two 16-byte blocks)
    // AES-256-ECB with the transform seed as the key; encrypt both blocks in
    // place each round (ECB ⇒ one stateless engine reused across rounds).
    final aes = pc.AESEngine()..init(true, pc.KeyParameter(salt));
    final block = Uint8List(16);
    for (var r = 0; r < params.iterations; r++) {
      for (var off = 0; off < 32; off += 16) {
        aes.processBlock(t, off, block, 0);
        t.setRange(off, off + 16, block);
      }
    }
    // SHA-256 yields the 32-byte transformed key (the KDBX master-key input).
    return HeapSecureKey(pc.SHA256Digest().process(t));
  }
}
