// dgvault — the real HMAC behind TOTP/HOTP, from vetted pointycastle digests.
//
// [Totp] takes its keyed-hash as an injected [OtpHmac] so the RFC framing stays
// pure Dart and headlessly testable; this is the platform-layer implementation
// that actually computes HMAC-SHA1/256/512. Block sizes are the digest's input
// block length in bytes (SHA-1/256 = 64, SHA-512 = 128), which HMAC needs to
// pad/derive the inner and outer keys.

import 'dart:typed_data';

import 'package:pointycastle/export.dart' as pc;

import '../totp.dart';

class PointyCastleOtpHmac implements OtpHmac {
  const PointyCastleOtpHmac();

  @override
  Uint8List compute(OtpAlgorithm algorithm, Uint8List key, Uint8List message) {
    final pc.Digest digest;
    final int blockBytes;
    switch (algorithm) {
      case OtpAlgorithm.sha1:
        digest = pc.SHA1Digest();
        blockBytes = 64;
      case OtpAlgorithm.sha256:
        digest = pc.SHA256Digest();
        blockBytes = 64;
      case OtpAlgorithm.sha512:
        digest = pc.SHA512Digest();
        blockBytes = 128;
    }
    return (pc.HMac(digest, blockBytes)..init(pc.KeyParameter(key)))
        .process(message);
  }
}
