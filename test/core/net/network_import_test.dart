import 'package:dgvault/core/net/network_import.dart';
import 'package:test/test.dart';

void main() {
  group('HostClassifier.isLocal', () {
    test('loopback / private / link-local IPv4 are local', () {
      for (final h in [
        '127.0.0.1', '10.1.2.3', '192.168.1.5',
        '172.16.0.1', '172.31.255.255', '169.254.10.10',
      ]) {
        expect(HostClassifier.isLocal(h), isTrue, reason: h);
      }
    });

    test('public IPv4 (incl. 172.15/172.32 edges) is not local', () {
      for (final h in ['8.8.8.8', '1.2.3.4', '172.15.0.1', '172.32.0.1']) {
        expect(HostClassifier.isLocal(h), isFalse, reason: h);
      }
    });

    test('malformed IPv4 octet is not local', () {
      expect(HostClassifier.isLocal('999.1.1.1'), isFalse);
    });

    test('IPv6 loopback / link-local / ULA are local; GUA is not', () {
      expect(HostClassifier.isLocal('::1'), isTrue);
      expect(HostClassifier.isLocal('[::1]'), isTrue); // bracketed literal
      expect(HostClassifier.isLocal('fe80::1'), isTrue);
      expect(HostClassifier.isLocal('fd00::1'), isTrue);
      expect(HostClassifier.isLocal('fc00::1'), isTrue);
      expect(HostClassifier.isLocal('2001:4860:4860::8888'), isFalse);
    });

    test('hostnames: localhost/.local/single-label local, public FQDN not', () {
      expect(HostClassifier.isLocal('localhost'), isTrue);
      expect(HostClassifier.isLocal('nas.local'), isTrue);
      expect(HostClassifier.isLocal('printer'), isTrue); // single-label LAN
      expect(HostClassifier.isLocal('example.com'), isFalse);
      expect(HostClassifier.isLocal('sub.example.com'), isFalse);
    });
  });

  group('LocalOnlyPolicy', () {
    test('disabled allows anything', () {
      const p = LocalOnlyPolicy(enabled: false);
      expect(p.allows('https://example.com/x'), isTrue);
    });

    test('enabled permits local, denies public', () {
      const p = LocalOnlyPolicy(enabled: true);
      expect(p.allows('https://192.168.1.10/backup'), isTrue);
      expect(p.allows('http://nas.local/x'), isTrue);
      expect(p.allows('https://example.com/x'), isFalse);
      expect(() => p.enforce('https://example.com/x'),
          throwsA(isA<LocalNetworkViolation>()),);
    });

    test('bare host (no scheme) is classified', () {
      const p = LocalOnlyPolicy(enabled: true);
      expect(p.allows('192.168.0.1'), isTrue);
    });
  });

  group('DirectImportUrl.validate', () {
    test('accepts allowed schemes with host', () {
      expect(DirectImportUrl.validate('https://x.io/a.csv').scheme, 'https');
      expect(DirectImportUrl.validate('file:///path/v.kdbx').scheme, 'file');
    });

    test('rejects disallowed scheme, missing scheme, missing host', () {
      expect(() => DirectImportUrl.validate('ftp://x/a'),
          throwsA(isA<DirectImportException>()),);
      expect(() => DirectImportUrl.validate('notaurl'),
          throwsA(isA<DirectImportException>()),);
      expect(() => DirectImportUrl.validate('https://'),
          throwsA(isA<DirectImportException>()),);
    });
  });

  group('DirectImportUrl.detectFormat', () {
    test('by content-type then by extension', () {
      expect(DirectImportUrl.detectFormat(contentType: 'text/csv'), ImportFormat.csv);
      expect(DirectImportUrl.detectFormat(path: 'backup.CSV'), ImportFormat.csv);
      expect(DirectImportUrl.detectFormat(path: 'data.1pux'), ImportFormat.onePassword);
      expect(DirectImportUrl.detectFormat(path: 'vault.kdbx'), ImportFormat.kdbx);
      expect(DirectImportUrl.detectFormat(path: 'x.bin'), ImportFormat.unknown);
    });
  });
}
