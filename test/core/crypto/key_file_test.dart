import 'dart:convert';
import 'dart:typed_data';

import 'package:dgvault/core/core.dart';
import 'package:test/test.dart';

/// Deterministic stand-in for SHA-256 (NOT a real hash) — enough to test the
/// parser's dispatch and the XML hash-verification path.
class _FakeSha256 implements Sha256Hasher {
  const _FakeSha256();
  @override
  Uint8List hash(Uint8List data) {
    final sum = data.fold<int>(0, (a, b) => (a + b) & 0xFFFFFFFF);
    return Uint8List.fromList([for (var i = 0; i < 32; i++) (sum + i) & 0xFF]);
  }
}

String _hex(Iterable<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

const _keyFile = KeyFile(_FakeSha256());

void main() {
  group('raw forms', () {
    test('32 raw bytes are used verbatim', () {
      final bytes = Uint8List.fromList(List<int>.generate(32, (i) => i * 7 % 256));
      final r = _keyFile.parse(bytes);
      expect(r.format, KeyFileFormat.binary32);
      expect(r.key, bytes);
    });

    test('64 hex characters decode to 32 bytes', () {
      final hexStr = _hex(List<int>.generate(32, (i) => i));
      final r = _keyFile.parse(Uint8List.fromList(ascii.encode(hexStr)));
      expect(r.format, KeyFileFormat.hex64);
      expect(r.key, List<int>.generate(32, (i) => i));
    });

    test('arbitrary content falls back to SHA-256 of the file', () {
      final bytes = Uint8List.fromList(ascii.encode('an arbitrary key file body'));
      final r = _keyFile.parse(bytes);
      expect(r.format, KeyFileFormat.hashed);
      expect(r.key, const _FakeSha256().hash(bytes));
    });
  });

  group('KeePass 2.x XML key files', () {
    final key = Uint8List.fromList(List<int>.generate(32, (i) => i));

    test('v1.0 Base64 data', () {
      final xml = '<KeyFile><Meta><Version>1.0</Version></Meta>'
          '<Key><Data>${base64.encode(key)}</Data></Key></KeyFile>';
      final r = _keyFile.parse(Uint8List.fromList(utf8.encode(xml)));
      expect(r.format, KeyFileFormat.keepass2Xml);
      expect(r.key, key);
    });

    test('v2.0 hex data with a valid hash', () {
      final hashHex = _hex(const _FakeSha256().hash(key).sublist(0, 4));
      final xml = '<KeyFile><Meta><Version>2.0</Version></Meta>'
          '<Key><Data Hash="$hashHex">${_hex(key)}</Data></Key></KeyFile>';
      final r = _keyFile.parse(Uint8List.fromList(utf8.encode(xml)));
      expect(r.format, KeyFileFormat.keepass2Xml);
      expect(r.key, key);
    });

    test('v2.0 strips whitespace inside hex data', () {
      final spaced = '${_hex(key.sublist(0, 16))}\n  ${_hex(key.sublist(16))}';
      final xml = '<KeyFile><Meta><Version>2.0</Version></Meta>'
          '<Key><Data>$spaced</Data></Key></KeyFile>';
      expect(_keyFile.parse(Uint8List.fromList(utf8.encode(xml))).key, key);
    });

    test('v2.0 with a WRONG hash throws', () {
      final xml = '<KeyFile><Meta><Version>2.0</Version></Meta>'
          '<Key><Data Hash="deadbeef">${_hex(key)}</Data></Key></KeyFile>';
      expect(() => _keyFile.parse(Uint8List.fromList(utf8.encode(xml))),
          throwsA(isA<KeyFileException>()));
    });

    test('malformed XML key file throws', () {
      final xml = '<KeyFile><Key><Data>oops';
      expect(() => _keyFile.parse(Uint8List.fromList(utf8.encode(xml))),
          throwsA(isA<KeyFileException>()));
    });

    test('XML key file without <Data> throws', () {
      final xml = '<KeyFile><Key></Key></KeyFile>';
      expect(() => _keyFile.parse(Uint8List.fromList(utf8.encode(xml))),
          throwsA(isA<KeyFileException>()));
    });
  });
}
