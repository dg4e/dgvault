import 'dart:typed_data';

import 'package:dgvault/core/core.dart';
import 'package:test/test.dart';

Uint8List _hex(String h) => Uint8List.fromList([
      for (var i = 0; i < h.length; i += 2)
        int.parse(h.substring(i, i + 2), radix: 16),
    ]);

/// Returns the documented RFC 4226 Appendix-D HMAC-SHA1 digests, keyed by the
/// counter encoded in the 8-byte message. Lets us validate the pure truncation
/// + encoding without a real HMAC.
class _RfcVectorHmac implements OtpHmac {
  const _RfcVectorHmac();
  static const _digests = <int, String>{
    0: 'cc93cf18508d94934c64b65d8ba7667fb7cde4b0',
    1: '75a48a19d4cbe100644e8ac1397eea747a2d33ab',
    2: '0bacb7fa082fef30782211938bc1c5e70416ff44',
  };
  @override
  Uint8List compute(OtpAlgorithm algorithm, Uint8List key, Uint8List message) {
    final counter = ByteData.sublistView(message).getUint64(0, Endian.big);
    return _hex(_digests[counter]!);
  }
}

void main() {
  final secret = asciiSecret('12345678901234567890');
  const totp = Totp(_RfcVectorHmac());

  group('HOTP — RFC 4226 vectors', () {
    final cfg = OtpConfig(secret: secret);
    test('counter 0 → 755224', () {
      expect(totp.generateHotp(cfg, 0), '755224');
    });
    test('counter 1 → 287082', () {
      expect(totp.generateHotp(cfg, 1), '287082');
    });
    test('counter 2 → 359152', () {
      expect(totp.generateHotp(cfg, 2), '359152');
    });
  });

  group('TOTP — time stepping', () {
    final cfg = OtpConfig(secret: secret); // period 30
    test('derives the counter from unix time', () {
      // unix 30..59 → counter 1
      final now = DateTime.fromMillisecondsSinceEpoch(30000, isUtc: true);
      expect(totp.generate(cfg, now), '287082');
    });
    test('remainingSeconds counts down within the window', () {
      final now = DateTime.fromMillisecondsSinceEpoch(45000, isUtc: true);
      expect(totp.remainingSeconds(cfg, now), 15);
    });
  });

  group('Steam variant', () {
    test('5-char code from the Steam alphabet', () {
      final cfg = OtpConfig(
        secret: secret,
        digits: 5,
        encoding: OtpEncoding.steam,
      );
      // truncate(count0 digest) = 1284755224 → Steam "GG5F5".
      expect(totp.generateHotp(cfg, 0), 'GG5F5');
    });
  });

  group('Base32', () {
    test('RFC 4648 vector MY====== → "f"', () {
      expect(base32Decode('MY======'), [0x66]);
    });
    test('round-trips arbitrary bytes', () {
      final data = Uint8List.fromList([1, 2, 3, 4, 5, 250, 0, 99]);
      expect(base32Decode(base32Encode(data)), data);
    });
    test('rejects invalid characters', () {
      expect(() => base32Decode('!!!!'), throwsFormatException);
    });
  });

  group('otpauth:// URI', () {
    test('parses label, issuer, algorithm, digits, period', () {
      final cfg = OtpConfig.fromUri(
        'otpauth://totp/ACME%20Co:john@example.com'
        '?secret=JBSWY3DPEHPK3PXP&issuer=ACME%20Co&algorithm=SHA256'
        '&digits=8&period=60',
      );
      expect(cfg.issuer, 'ACME Co');
      expect(cfg.account, 'john@example.com');
      expect(cfg.algorithm, OtpAlgorithm.sha256);
      expect(cfg.digits, 8);
      expect(cfg.period, 60);
      expect(cfg.encoding, OtpEncoding.decimal);
      expect(cfg.secret, base32Decode('JBSWY3DPEHPK3PXP'));
    });

    test('Steam issuer forces 5-digit Steam encoding', () {
      final cfg =
          OtpConfig.fromUri('otpauth://totp/Steam:user?secret=MFRGGZDF&issuer=Steam');
      expect(cfg.encoding, OtpEncoding.steam);
      expect(cfg.digits, 5);
    });

    test('rejects a non-otpauth URI', () {
      expect(() => OtpConfig.fromUri('https://example.com'),
          throwsFormatException);
    });

    test('rejects a missing secret', () {
      expect(() => OtpConfig.fromUri('otpauth://totp/x?issuer=y'),
          throwsFormatException);
    });
  });
}
