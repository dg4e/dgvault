// Critic-owned SECURITY audit for the local-network host classifier.
//
// The "Local Network Only" guard exists so an import/export can never reach the
// public internet. Its dangerous failure direction is a FALSE POSITIVE — calling
// a public host "local" — which lets data leave the device. Composer/Performer
// cover the dotted-IP and FQDN cases; this targets the dotless-integer encoding.
//
// Toolchain not installed here; assertions traced against source by hand
// (see reviews/Critic-round-20.md).

import 'package:dgvault/core/net/network_import.dart';
import 'package:test/test.dart';

void main() {
  group('baseline classification is correct', () {
    test('loopback/private local; dotted public not local', () {
      expect(HostClassifier.isLocal('127.0.0.1'), isTrue);
      expect(HostClassifier.isLocal('192.168.1.5'), isTrue);
      expect(HostClassifier.isLocal('::1'), isTrue);
      expect(HostClassifier.isLocal('8.8.8.8'), isFalse);
      expect(HostClassifier.isLocal('example.com'), isFalse);
    });
  });

  // ---- ✅ SECURITY FINDING FIXED (R20 REQUEST_CHANGES → regression guard) ----
  // Was: a dotless integer-encoded public IP hit the single-label-LAN rule and
  // was classified local, so local-only ALLOWED a fetch to the public internet.
  // Fix: a pure-integer / 0x-hex / 0-octal host is parsed as a 32-bit IPv4 and
  // range-checked (never blanket-local). Assertions flipped to the safe outcome.
  group('SECURITY: dotless integer-encoded public IP is NOT local', () {
    test('134744072 (== 8.8.8.8) classifies as non-local', () {
      expect(HostClassifier.isLocal('134744072'), isFalse,
          reason: 'decimal-int public IP must be range-checked, not auto-local',);
    });

    test('0x-hex / 0-octal public-IP encodings are non-local too', () {
      expect(HostClassifier.isLocal('0x08080808'), isFalse); // hex 8.8.8.8
      expect(HostClassifier.isLocal('0x8080808'), isFalse);
      // 01002004010 (octal) == 134744072 == 8.8.8.8
      expect(HostClassifier.isLocal('01002004010'), isFalse);
    });

    test('out-of-range / overflow integer hosts fail safe (non-local)', () {
      expect(HostClassifier.isLocal('9999999999'), isFalse); // > 2^32-1
    });

    test('genuine local integer-IP encodings still classify local', () {
      // 2130706433 == 0x7F000001 == 127.0.0.1 loopback
      expect(HostClassifier.isLocal('2130706433'), isTrue);
      expect(HostClassifier.isLocal('0x7f000001'), isTrue);
      // 3232235777 == 192.168.1.1
      expect(HostClassifier.isLocal('3232235777'), isTrue);
    });

    test('non-numeric single-label LAN names are still local', () {
      expect(HostClassifier.isLocal('nas'), isTrue);
      expect(HostClassifier.isLocal('my-server'), isTrue);
    });

    test('end-to-end: local-only policy DENIES the integer-IP public host', () {
      const p = LocalOnlyPolicy(enabled: true);
      expect(p.allows('http://134744072/'), isFalse,
          reason: 'bypass closed — resolves to public 8.8.8.8, must be denied',);
      expect(p.allows('http://0x08080808/'), isFalse);
      // A normal public host is denied, confirming the guard otherwise works.
      expect(p.allows('https://example.com'), isFalse);
      // Genuine LAN hosts (dotted and integer-encoded loopback) are allowed.
      expect(p.allows('http://192.168.1.10/db.kdbx'), isTrue);
      expect(p.allows('http://2130706433/'), isTrue);
    });
  });
}
