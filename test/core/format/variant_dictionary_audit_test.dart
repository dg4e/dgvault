// Critic-owned adversarial audit for the KDBX4 VariantDictionary binary codec.
//
// This is interop-critical and, crucially, the serialized bytes are covered by
// the KDBX header's SHA-256/HMAC — so the codec must be **byte-deterministic**:
// parse→serialize has to reproduce the exact input bytes, or header integrity
// verification against a KeePass-written file fails. Composer's suite covers
// basic type round-trips, ordering, absent keys, and version rejection. These
// add byte-stability and the value edges (large uint64, unicode, empties, bools).
//
// Toolchain not installed here; assertions traced against source + KDBX wire
// format by hand (see reviews/Critic-round-12.md).

import 'dart:convert';
import 'dart:typed_data';

import 'package:dgvault/core/format/variant_dictionary.dart';
import 'package:test/test.dart';

void main() {
  test('serialize → parse → serialize is byte-identical (header HMAC stability)', () {
    final vd = VariantDictionary()
      ..setUInt32('V', 0x13)
      ..setUInt64('M', 67108864) // 64 MiB Argon2 memory
      ..setUInt64('I', 3)
      ..setUInt32('P', 4)
      ..setString('name', 'café')
      ..setBytes('S', Uint8List.fromList(List<int>.generate(32, (i) => i)));

    final bytes1 = vd.serialize();
    final bytes2 = VariantDictionary.parse(bytes1).serialize();
    expect(bytes2, equals(bytes1),
        reason: 'non-deterministic re-serialization would break header HMAC');
  });

  test('value edges round-trip (large u64, unicode, empties, bools)', () {
    final big = 1 << 40; // 1,099,511,627,776 — well above uint32 range
    final vd = VariantDictionary()
      ..setUInt64('big', big)
      ..setString('unicode', 'café — 日本語 — 🔐')
      ..setString('emptyStr', '')
      ..setBytes('emptyBytes', Uint8List(0))
      ..setBool('t', true)
      ..setBool('f', false);

    final back = VariantDictionary.parse(vd.serialize());
    expect(back.getUInt64('big'), big);
    expect(back.getString('unicode'), 'café — 日本語 — 🔐');
    expect(back.getString('emptyStr'), '');
    expect(back.getBytes('emptyBytes'), isEmpty);
    expect(back.getBool('t'), isTrue);
    expect(back.getBool('f'), isFalse);
  });

  test('insertion order is reproduced after a parse (re-serialize stable)', () {
    final vd = VariantDictionary()
      ..setUInt32('z', 1)
      ..setUInt32('a', 2)
      ..setUInt32('m', 3);
    final back = VariantDictionary.parse(vd.serialize());
    expect(back.keys.toList(), ['z', 'a', 'm']);
  });

  test('a key whose UTF-8 length differs from its char length round-trips', () {
    // 'é' and '🔐' are multibyte in UTF-8; the int32 keyLen is a BYTE length, so
    // a char-vs-byte length confusion would misframe the stream.
    final vd = VariantDictionary()..setUInt32('clé-🔐', 7);
    final back = VariantDictionary.parse(vd.serialize());
    expect(back.getUInt32('clé-🔐'), 7);
    expect(utf8.encode('clé-🔐').length, greaterThan('clé-🔐'.length));
  });
}
