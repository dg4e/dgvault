// Critic-owned supplemental TOTP audit (Phase 3 Critic task: RFC vectors).
//
// Composer's suite is thorough (RFC 4226 Appendix-D counters 0–2, time-stepping,
// an exact Steam value, base32, otpauth). Per §8 this does NOT duplicate it; it
// adds the one independent known-answer it stops short of: the RFC 4226 §5.4
// canonical dynamic-truncation example (→ 872921), whose HMAC truncates at
// OFFSET 10 — exercising the non-zero-offset path that Appendix-D counter 0
// (offset 0) does not. Plus an exact-multiple base32 boundary (no padding).
//
// Truncation math verified by hand: digest[19]=0x5A & 0x0F = 10; bytes[10..13] =
// 50 ef 7f 19 with the high bit masked → 0x50EF7F19 = 1357872921; % 1e6 = 872921.
//
// Toolchain not installed here; assertions traced against source + the RFC.

import 'dart:typed_data';

import 'package:dgvault/core/otp/totp.dart';
import 'package:test/test.dart';

Uint8List _hex(String h) => Uint8List.fromList(
    [for (var i = 0; i < h.length; i += 2) int.parse(h.substring(i, i + 2), radix: 16)]);

/// Returns a fixed digest regardless of inputs — lets us drive the pure
/// truncation/encoding path with a published HMAC value (no real HMAC needed).
class _FixedHmac implements OtpHmac {
  _FixedHmac(this.digest);
  final Uint8List digest;
  @override
  Uint8List compute(OtpAlgorithm a, Uint8List k, Uint8List m) => digest;
}

void main() {
  test('RFC 4226 §5.4 canonical example → 872921 (offset-10 truncation path)', () {
    final hmac = _FixedHmac(_hex('1f8698690e02ca16618550ef7f19da8e945b555a'));
    final cfg = OtpConfig(secret: asciiSecret('12345678901234567890'), digits: 6);
    // Counter is irrelevant here (fixed digest) — this isolates truncate+decimal.
    expect(Totp(hmac).generateHotp(cfg, 0), '872921');
  });

  test('a different digit count slices the same binary correctly', () {
    final hmac = _FixedHmac(_hex('1f8698690e02ca16618550ef7f19da8e945b555a'));
    final base = OtpConfig(secret: asciiSecret('x'));
    // 1357872921 → last 8 digits, and last 4 digits.
    expect(Totp(hmac).generateHotp(base.copyDigits(8), 0), '57872921');
    expect(Totp(hmac).generateHotp(base.copyDigits(4), 0), '2921');
  });

  group('base32 exact-multiple boundary (no padding)', () {
    test('JBSWY3DP → "Hello" (5 bytes = 8 chars, clean boundary)', () {
      expect(base32Decode('JBSWY3DP'), asciiSecret('Hello'));
    });
    test('lowercase is tolerated', () {
      expect(base32Decode('jbswy3dp'), asciiSecret('Hello'));
    });
  });
}

extension on OtpConfig {
  OtpConfig copyDigits(int d) => OtpConfig(
        secret: secret,
        digits: d,
        period: period,
        algorithm: algorithm,
        encoding: encoding,
      );
}
