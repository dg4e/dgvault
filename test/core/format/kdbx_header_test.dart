import 'dart:typed_data';

import 'package:dgvault/core/format/kdbx_header.dart';
import 'package:test/test.dart';

Uint8List _bytes(int n, [int fill = 0]) =>
    Uint8List.fromList(List<int>.filled(n, fill));

void main() {
  group('VariantDictionary', () {
    test('round-trips a realistic Argon2 KDF parameter set', () {
      final vd = VariantDictionary()
        ..['\$UUID'] = VdValue.bytes(_bytes(16, 7))
        ..['V'] = VdValue.uint32(0x13)
        ..['I'] = VdValue.uint64(10) // iterations
        ..['M'] = VdValue.uint64(67108864) // 64 MiB
        ..['P'] = VdValue.uint32(4) // parallelism
        ..['S'] = VdValue.bytes(_bytes(32, 9)); // salt

      final decoded = VariantDictionary.decode(vd.encode());
      expect(decoded['V']!.asInt, 0x13);
      expect(decoded['I']!.asInt, 10);
      expect(decoded['M']!.asInt, 67108864);
      expect(decoded['P']!.asInt, 4);
      expect(decoded['S']!.asBytes, _bytes(32, 9));
      expect(decoded['\$UUID']!.type, VdType.bytes);
      // types preserved exactly
      expect(decoded['I']!.type, VdType.uint64);
      expect(decoded['P']!.type, VdType.uint32);
    });

    test('version header is 0x0100 (little-endian)', () {
      final enc = VariantDictionary().encode();
      expect([enc[0], enc[1]], [0x00, 0x01]);
      expect(enc.last, 0x00, reason: 'end marker');
    });

    test('preserves bool and string types', () {
      final vd = VariantDictionary()
        ..['flag'] = VdValue.boolean(true)
        ..['name'] = VdValue.string('héllo');
      final d = VariantDictionary.decode(vd.encode());
      expect(d['flag']!.asBool, isTrue);
      expect(d['name']!.asString, 'héllo');
    });
  });

  group('KdbxHeader', () {
    KdbxHeader sample() {
      final h = KdbxHeader()
        ..fields[KdbxHeaderField.cipherId] = _bytes(16, 1)
        ..fields[KdbxHeaderField.masterSeed] = _bytes(32, 2)
        ..fields[KdbxHeaderField.encryptionIv] = _bytes(12, 3);
      h.setCompressionFlags(KdbxCompression.gzip);
      h.setKdfParameters(VariantDictionary()
        ..['I'] = VdValue.uint64(10)
        ..['S'] = VdValue.bytes(_bytes(32, 5)));
      return h;
    }

    test('encode → parse round-trips signatures, version, and fields', () {
      final h = sample();
      final encoded = h.encode();
      final result = KdbxHeader.parse(encoded);
      final p = result.header;

      expect(p.signature1, kKdbxSignature1);
      expect(p.signature2, kKdbxSignature2);
      expect(p.versionMajor, 4);
      expect(p.isKdbx4, isTrue);
      expect(p.cipherId, _bytes(16, 1));
      expect(p.masterSeed, _bytes(32, 2));
      expect(p.encryptionIv, _bytes(12, 3));
      expect(p.compressionFlags, KdbxCompression.gzip);
      expect(p.kdfParameters!['I']!.asInt, 10);
      expect(p.kdfParameters!['S']!.asBytes, _bytes(32, 5));
    });

    test('headerLength points just past the end-of-header field', () {
      final encoded = sample().encode();
      final result = KdbxHeader.parse(encoded);
      expect(result.headerLength, encoded.length,
          reason: 'crypto/integrity block would begin here');
    });

    test('signature constant is written little-endian', () {
      final encoded = sample().encode();
      final sig1 = ByteData.sublistView(encoded).getUint32(0, Endian.little);
      expect(sig1, kKdbxSignature1);
    });

    test('parse rejects a non-KDBX signature', () {
      final bad = _bytes(32);
      expect(() => KdbxHeader.parse(bad), throwsA(isA<KdbxFormatException>()));
    });

    test('parse rejects unsupported major version', () {
      final h = sample()..versionMajor = 3;
      expect(() => KdbxHeader.parse(h.encode()),
          throwsA(isA<KdbxFormatException>()));
    });
  });
}
