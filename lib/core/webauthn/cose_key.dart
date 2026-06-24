// dgvault — COSE_Key (RFC 8152) parsing + signature verification for WebAuthn.
//
// Supports ES256 (ECDSA P-256 / SHA-256), the algorithm used by Apple's Secure
// Enclave, Windows Hello, and Android platform authenticators — i.e. virtually
// all passkeys. EdDSA (Ed25519) is a follow-up (pointycastle has no Ed25519).
//
// No hand-rolled crypto — verification is pointycastle's ECDSASigner over
// secp256r1; this file owns the COSE map decode + the DER signature parse.

import 'dart:typed_data';

import 'package:pointycastle/export.dart' as pc;

class CoseKeyException implements Exception {
  CoseKeyException(this.message);
  final String message;
  @override
  String toString() => 'CoseKeyException: $message';
}

/// COSE algorithm identifiers (the ones we recognise).
class CoseAlg {
  static const int es256 = -7;
  static const int eddsa = -8;
}

class CredentialPublicKey {
  CredentialPublicKey._(this.alg, this._verifier);

  final int alg;
  final bool Function(Uint8List message, Uint8List signature) _verifier;

  /// Verify [signature] over [signedData] (the raw bytes; hashing is internal).
  bool verify(Uint8List signedData, Uint8List signature) =>
      _verifier(signedData, signature);

  /// Build from a decoded COSE_Key map (int-keyed).
  factory CredentialPublicKey.fromCose(Map<Object?, Object?> cose) {
    final kty = cose[1];
    final alg = cose[3];
    if (alg is! int) throw CoseKeyException('COSE key missing alg (3)');

    if (kty == 2 && alg == CoseAlg.es256) {
      // EC2 / P-256.
      final crv = cose[-1];
      if (crv != 1) throw CoseKeyException('ES256 requires P-256 (crv=1), got $crv');
      final x = cose[-2];
      final y = cose[-3];
      if (x is! Uint8List || y is! Uint8List || x.length != 32 || y.length != 32) {
        throw CoseKeyException('ES256 key needs 32-byte x and y coordinates');
      }
      final domain = pc.ECCurve_secp256r1();
      final point = domain.curve.createPoint(_be(x), _be(y));
      final pub = pc.ECPublicKey(point, domain);
      return CredentialPublicKey._(alg, (msg, sig) {
        final (r, s) = _parseDerEcdsa(sig);
        final signer = pc.ECDSASigner(pc.SHA256Digest())
          ..init(false, pc.PublicKeyParameter<pc.ECPublicKey>(pub));
        return signer.verifySignature(msg, pc.ECSignature(r, s));
      });
    }
    throw CoseKeyException('unsupported COSE key (kty=$kty alg=$alg)');
  }

  static BigInt _be(Uint8List b) {
    var v = BigInt.zero;
    for (final byte in b) {
      v = (v << 8) | BigInt.from(byte);
    }
    return v;
  }
}

/// Parse an ASN.1 DER ECDSA signature: SEQUENCE { INTEGER r, INTEGER s }.
(BigInt, BigInt) _parseDerEcdsa(Uint8List der) {
  var i = 0;
  int u8() {
    if (i >= der.length) throw CoseKeyException('truncated DER signature');
    return der[i++];
  }

  if (u8() != 0x30) throw CoseKeyException('DER signature: expected SEQUENCE');
  u8(); // sequence length (assume short form, sufficient for P-256)
  BigInt readInt() {
    if (u8() != 0x02) throw CoseKeyException('DER signature: expected INTEGER');
    final len = u8();
    var v = BigInt.zero;
    for (var k = 0; k < len; k++) {
      v = (v << 8) | BigInt.from(u8());
    }
    return v;
  }

  final r = readInt();
  final s = readInt();
  return (r, s);
}
