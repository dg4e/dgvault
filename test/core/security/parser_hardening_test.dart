// Hardening tests: untrusted, pre-authentication parsers must reject malformed
// input with a typed exception instead of crashing with RangeError /
// FormatException / StackOverflow / OOM.

import 'dart:typed_data';

import 'package:dgvault/core/core.dart';
import 'package:dgvault/core/crypto/impl/kdbx3_reader.dart';
import 'package:dgvault/data/format/gzip_compressor.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _b(List<int> xs) => Uint8List.fromList(xs);

/// sig1 9AA2D903, sig2 B54BFB67, minor, major — little-endian.
Uint8List _kdbxMagic(int major) {
  final bd = ByteData(12)
    ..setUint32(0, 0x9AA2D903, Endian.little)
    ..setUint32(4, 0xB54BFB67, Endian.little)
    ..setUint16(8, 1, Endian.little)
    ..setUint16(10, major, Endian.little);
  return bd.buffer.asUint8List();
}

class _StubHasher implements Sha256Hasher {
  @override
  Uint8List hash(Uint8List data) => Uint8List(32);
}

void main() {
  group('VariantDictionary.parse rejects malformed input', () {
    test('truncated length throws (not RangeError)', () {
      // version 0x0100, then a type byte with no room for the key length.
      final bytes = _b([0x00, 0x01, 0x04]);
      expect(() => VariantDictionary.parse(bytes),
          throwsA(isA<VariantDictionaryException>()),);
    });

    test('oversized key length is bounded', () {
      final bd = ByteData(7)
        ..setUint16(0, 0x0100, Endian.little)
        ..setUint8(2, 0x18) // String
        ..setUint32(3, 0x7fffffff, Endian.little); // huge keyLen
      expect(() => VariantDictionary.parse(bd.buffer.asUint8List()),
          throwsA(isA<VariantDictionaryException>()),);
    });

    test('typed value too short for its width throws', () {
      // UInt32 entry whose value is only 1 byte.
      final out = BytesBuilder()
        ..add(_b([0x00, 0x01])) // version
        ..add(_b([0x04])) // UInt32 type
        ..add((ByteData(4)..setUint32(0, 1, Endian.little)).buffer.asUint8List())
        ..add(_b([0x41])) // key 'A'
        ..add((ByteData(4)..setUint32(0, 1, Endian.little)).buffer.asUint8List())
        ..add(_b([0x09])) // 1-byte value (needs 4)
        ..add(_b([0x00])); // terminator
      expect(() => VariantDictionary.parse(out.toBytes()),
          throwsA(isA<VariantDictionaryException>()),);
    });

    test('missing terminator throws', () {
      final out = BytesBuilder()
        ..add(_b([0x00, 0x01]))
        ..add(_b([0x08])) // Bool type
        ..add((ByteData(4)..setUint32(0, 1, Endian.little)).buffer.asUint8List())
        ..add(_b([0x41]))
        ..add((ByteData(4)..setUint32(0, 1, Endian.little)).buffer.asUint8List())
        ..add(_b([0x01])); // value, but no 0x00 terminator
      expect(() => VariantDictionary.parse(out.toBytes()),
          throwsA(isA<VariantDictionaryException>()),);
    });

    test('valid round-trip still parses', () {
      final vd = VariantDictionary()..setUInt64('R', 6000);
      final back = VariantDictionary.parse(vd.serialize());
      expect(back.getUInt64('R'), 6000);
    });
  });

  group('KdbxHeader.read bounds the TLV loop', () {
    test('field length overrunning the buffer throws KdbxFormatException', () {
      final out = BytesBuilder()
        ..add(_kdbxMagic(4))
        ..add(_b([0x02])) // CipherID field id
        ..add((ByteData(4)..setUint32(0, 0x7fffffff, Endian.little))
            .buffer
            .asUint8List(),); // huge len, no data
      expect(() => KdbxHeader.read(out.toBytes()),
          throwsA(isA<KdbxFormatException>()),);
    });

    test('no end-of-header field throws rather than looping off the end', () {
      final out = BytesBuilder()
        ..add(_kdbxMagic(4))
        ..add(_b([0x05])) // an ignored field id
        ..add((ByteData(4)..setUint32(0, 0, Endian.little)).buffer.asUint8List());
      // ...stream ends with no id-0 terminator.
      expect(() => KdbxHeader.read(out.toBytes()),
          throwsA(isA<KdbxFormatException>()),);
    });
  });

  group('Kdbx3Reader bounds the v3 header', () {
    test('overrunning v3 field throws KdbxFormatException', () {
      final out = BytesBuilder()
        ..add(_kdbxMagic(3))
        ..add(_b([0x04])) // a field id
        ..add((ByteData(2)..setUint16(0, 0xffff, Endian.little))
            .buffer
            .asUint8List(),); // huge 16-bit len, no data
      expect(
        const Kdbx3Reader().read(
          out.toBytes(),
          CompositeCredential(password: _b([1, 2, 3])),
          compressor: const GzipCompressor(),
        ),
        throwsA(isA<KdbxFormatException>()),
      );
    });
  });

  group('GzipCompressor', () {
    test('round-trips', () {
      const c = GzipCompressor();
      final data = _b(List.generate(500, (i) => i % 256));
      expect(c.decompress(c.compress(data)), data);
    });

    test('decompression bomb is capped', () {
      const writer = GzipCompressor();
      final bomb = writer.compress(Uint8List(50000)); // compresses tiny
      const reader = GzipCompressor(maxDecompressedBytes: 1024);
      expect(() => reader.decompress(bomb), throwsA(isA<GzipException>()));
    });

    test('non-gzip input throws GzipException', () {
      expect(() => const GzipCompressor().decompress(_b([1, 2, 3, 4, 5])),
          throwsA(isA<GzipException>()),);
    });
  });

  group('CborReader rejects abusive input', () {
    test('deep nesting throws instead of overflowing the stack', () {
      final deep = _b([...List.filled(80, 0x81), 0x00]); // 80x array-of-1
      expect(() => CborReader(deep).readItem(), throwsA(isA<CborException>()));
    });

    test('implausible element count throws', () {
      // array with a 4-byte length of 0xFFFFFFFF but no elements.
      expect(() => CborReader(_b([0x9a, 0xff, 0xff, 0xff, 0xff])).readItem(),
          throwsA(isA<CborException>()),);
    });

    test('negative (overflowed) length throws', () {
      // array, 8-byte length 0xFFFFFFFFFFFFFFFF -> negative in Dart int.
      final bytes =
          _b([0x9b, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff]);
      expect(() => CborReader(bytes).readItem(),
          throwsA(isA<CborException>()),);
    });
  });

  test('KeyFile rejects invalid base64 in a v1 XML key file', () {
    const xml = '<?xml version="1.0"?><KeyFile><Key>'
        '<Data>!!! not base64 !!!</Data></Key></KeyFile>';
    expect(() => KeyFile(_StubHasher()).parse(_b(xml.codeUnits)),
        throwsA(isA<KeyFileException>()),);
  });
}
