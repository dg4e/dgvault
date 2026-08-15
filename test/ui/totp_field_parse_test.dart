// The stored-TOTP parser accepts both an otpauth:// URI and a bare Base32
// secret, and rejects junk (so the detail view shows "invalid" instead of
// crashing or displaying a bogus code).

import 'package:dgvault/ui/widgets/totp_field.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses an otpauth:// URI', () {
    final cfg = parseStoredTotp(
      'otpauth://totp/ACME:alice?secret=JBSWY3DPEHPK3PXP&issuer=ACME&period=30',
    );
    expect(cfg, isNotNull);
    expect(cfg!.period, 30);
    expect(cfg.issuer, 'ACME');
    expect(cfg.secret, isNotEmpty);
  });

  test('parses a bare Base32 secret with default params', () {
    final cfg = parseStoredTotp('JBSWY3DPEHPK3PXP');
    expect(cfg, isNotNull);
    expect(cfg!.period, 30);
    expect(cfg.digits, 6);
  });

  test('tolerates spaced/lowercase Base32', () {
    expect(parseStoredTotp('jbsw y3dp ehpk 3pxp'), isNotNull);
  });

  test('rejects empty and junk', () {
    expect(parseStoredTotp(''), isNull);
    expect(parseStoredTotp('   '), isNull);
    expect(parseStoredTotp('not!valid!base32!!!'), isNull);
    expect(parseStoredTotp('otpauth://totp/x?issuer=y'), isNull); // no secret
  });
}
