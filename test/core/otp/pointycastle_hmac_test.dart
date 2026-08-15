// The real HMAC behind TOTP must reproduce the RFC 6238 Appendix-B test
// vectors end-to-end (secret "12345678901234567890", SHA-1, 8 digits).

import 'package:dgvault/core/core.dart';
import 'package:dgvault/core/otp/impl/pointycastle_hmac.dart';
import 'package:test/test.dart';

void main() {
  const totp = Totp(PointyCastleOtpHmac());
  final secret = asciiSecret('12345678901234567890');

  // RFC 6238 Appendix B (SHA-1, 8 digits): unix time → expected TOTP.
  const vectors = <int, String>{
    59: '94287082',
    1111111109: '07081804',
    1111111111: '14050471',
    1234567890: '89005924',
    2000000000: '69279037',
  };

  group('RFC 6238 SHA-1 vectors (real HMAC)', () {
    for (final entry in vectors.entries) {
      test('t=${entry.key} → ${entry.value}', () {
        final cfg = OtpConfig(secret: secret, digits: 8);
        final now = DateTime.fromMillisecondsSinceEpoch(
          entry.key * 1000,
          isUtc: true,
        );
        expect(totp.generate(cfg, now), entry.value);
      });
    }
  });

  test('6-digit default matches the truncated 8-digit code', () {
    final now = DateTime.fromMillisecondsSinceEpoch(59000, isUtc: true);
    final six = totp.generate(OtpConfig(secret: secret), now);
    expect(six, '287082'); // low 6 of 94287082
  });
}
