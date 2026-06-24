// dgvault — hardware challenge-response (YubiKey HMAC-SHA1) factor.
//
// A YubiKey configured for HMAC-SHA1 challenge-response computes
// HMAC-SHA1(secret, challenge) on the token; the 20-byte response is mixed into
// the composite key, so the database cannot be opened without the physical key.
//
// This file owns the pure computation + the factor interface. The real token is
// a device-gated transport (USB/NFC) implementing [ChallengeResponse]; the
// software impl here computes the same HMAC for tests and for "Secret Unlock"
// (emergency) flows where the secret is held in escrow.
//
// No hand-rolled crypto — HMAC-SHA1 is pointycastle.

import 'dart:typed_data';

import 'package:pointycastle/export.dart' as pc;

/// A challenge-response factor (a YubiKey, or a software stand-in).
abstract interface class ChallengeResponse {
  /// Compute the response for [challenge] (≤ 64 bytes for HMAC-SHA1).
  Future<Uint8List> respond(Uint8List challenge);
}

/// Software HMAC-SHA1 challenge-response. Holds the shared secret in memory —
/// use for tests and escrowed Secret-Unlock; a real YubiKey keeps the secret on
/// the token and is reached via a platform transport.
class SoftwareChallengeResponse implements ChallengeResponse {
  SoftwareChallengeResponse(Uint8List secret)
      : _secret = Uint8List.fromList(secret);

  final Uint8List _secret;

  @override
  Future<Uint8List> respond(Uint8List challenge) async =>
      hmacSha1(_secret, challenge);
}

/// HMAC-SHA1(key, data) — the exact operation a YubiKey performs in HMAC-SHA1
/// challenge-response mode. Returns the 20-byte MAC.
Uint8List hmacSha1(Uint8List key, Uint8List data) =>
    (pc.HMac(pc.SHA1Digest(), 64)..init(pc.KeyParameter(key))).process(data);
