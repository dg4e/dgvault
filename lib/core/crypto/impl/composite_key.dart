// dgvault — KeePass composite-key construction (shared by the KDFs).
//
// compositeKey = SHA-256(concat of the per-factor 32-byte values, in order):
//   password           → SHA-256(passwordBytes)
//   key file           → its 32-byte key verbatim (SHA-256'd only if not 32 B)
//   challenge-response → SHA-256(response)
// This is the input the KDF (Argon2 / AES-KDF) transforms.

import 'dart:typed_data';

import 'package:pointycastle/export.dart' as pc;

import '../key_derivation.dart';

Uint8List keepassCompositeKey(CompositeCredential c) {
  if (!c.hasAnyFactor) {
    throw ArgumentError('credential carries no factors');
  }
  final parts = BytesBuilder();
  if (c.password != null) parts.add(_sha256(c.password!));
  if (c.keyFile != null) {
    parts.add(c.keyFile!.length == 32 ? c.keyFile! : _sha256(c.keyFile!));
  }
  if (c.challengeResponse != null) parts.add(_sha256(c.challengeResponse!));
  return _sha256(parts.toBytes());
}

Uint8List _sha256(Uint8List data) => pc.SHA256Digest().process(data);
