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

  // ---- 🔴 SECURITY FINDING (REQUEST_CHANGES) — pinned current behaviour ----
  group('SECURITY: dotless integer-encoded public IP bypasses the guard', () {
    test('134744072 (== 8.8.8.8) is mis-classified as LOCAL', () {
      // No dots → isLocal()'s single-label-hostname rule returns true. But HTTP
      // stacks (curl, many libs) resolve an all-integer host as an IP, so
      // http://134744072/ reaches the PUBLIC 8.8.8.8 while the guard thinks it's
      // a LAN name. REQUEST_CHANGES: a pure-integer host (and 0x.../0-prefixed
      // forms) must be parsed as an int IP and range-checked, or denied — never
      // auto-classified local.
      expect(HostClassifier.isLocal('134744072'), isTrue,
          reason: 'CURRENT UNSAFE behaviour pinned; must become non-local after fix');
    });

    test('end-to-end: local-only policy ALLOWS the decimal-IP public host', () {
      const p = LocalOnlyPolicy(enabled: true);
      expect(p.allows('http://134744072/'), isTrue,
          reason: 'pinned bypass — local-only should DENY (resolves to public 8.8.8.8)');
      // A normal public host is correctly denied, confirming the guard otherwise works.
      expect(p.allows('https://example.com'), isFalse);
      // And a genuine LAN host is allowed.
      expect(p.allows('http://192.168.1.10/db.kdbx'), isTrue);
    });
  });
}
