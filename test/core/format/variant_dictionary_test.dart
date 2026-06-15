import 'dart:typed_data';

import 'package:dgvault/core/core.dart';
import 'package:test/test.dart';

void main() {
  test('round-trips all supported value types', () {
    final vd = VariantDictionary()
      ..setUInt32('u32', 0xDEADBEEF)
      ..setUInt64('u64', 0x0102030405)
      ..setBool('bt', true)
      ..setBool('bf', false)
      ..setString('str', 'héllo')
      ..setBytes('bytes', Uint8List.fromList([9, 8, 7, 0, 255]));

    final back = VariantDictionary.parse(vd.serialize());
    expect(back.getUInt32('u32'), 0xDEADBEEF);
    expect(back.getUInt64('u64'), 0x0102030405);
    expect(back.getBool('bt'), isTrue);
    expect(back.getBool('bf'), isFalse);
    expect(back.getString('str'), 'héllo');
    expect(back.getBytes('bytes'), [9, 8, 7, 0, 255]);
  });

  test('preserves key insertion order', () {
    final vd = VariantDictionary()
      ..setUInt32('z', 1)
      ..setUInt32('a', 2)
      ..setUInt32('m', 3);
    expect(VariantDictionary.parse(vd.serialize()).keys.toList(),
        ['z', 'a', 'm'],);
  });

  test('absent keys return null', () {
    final vd = VariantDictionary();
    expect(vd.getString('nope'), isNull);
    expect(vd.getUInt64('nope'), isNull);
  });

  test('rejects an unsupported dictionary version', () {
    final bad = Uint8List.fromList([0x00, 0x99, 0x00]); // version 0x9900
    expect(() => VariantDictionary.parse(bad),
        throwsA(isA<VariantDictionaryException>()),);
  });
}
