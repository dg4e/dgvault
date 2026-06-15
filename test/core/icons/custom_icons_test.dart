import 'dart:typed_data';

import 'package:dgvault/core/model/database.dart';
import 'package:dgvault/core/model/entry.dart';
import 'package:dgvault/core/model/field.dart';
import 'package:dgvault/core/model/group.dart';
import 'package:dgvault/core/model/protected_value.dart';
import 'package:dgvault/core/icons/custom_icons.dart';
import 'package:test/test.dart';

Uint8List _bytes(int n, int fill) => Uint8List.fromList(List.filled(n, fill));

Entry _entry(String uuid, {String? customIcon}) {
  final e = Entry(
    uuid: uuid,
    fields: {Field.title: Field(key: Field.title, value: InMemoryProtectedValue.plain(uuid))},
  );
  e.customIconUuid = customIcon;
  return e;
}

void main() {
  group('preset icons', () {
    test('valid index range is 0..68 (69 icons)', () {
      expect(kKeePassPresetIconCount, 69);
      expect(isValidPresetIcon(0), isTrue);
      expect(isValidPresetIcon(68), isTrue);
      expect(isValidPresetIcon(69), isFalse);
      expect(isValidPresetIcon(-1), isFalse);
    });

    test('IconRef.preset rejects out-of-range', () {
      expect(() => IconRef.preset(69), throwsA(isA<ArgumentError>()));
      final ref = IconRef.preset(3);
      expect(ref.isCustom, isFalse);
      expect(ref.presetIndex, 3);
    });

    test('IconRef.custom carries a uuid', () {
      final ref = IconRef.custom('abc');
      expect(ref.isCustom, isTrue);
      expect(ref.customUuid, 'abc');
    });
  });

  group('CustomIconPool', () {
    test('add / contains / remove', () {
      final pool = CustomIconPool();
      pool.add(CustomIcon(uuid: 'i1', data: _bytes(4, 1)));
      expect(pool.contains('i1'), isTrue);
      expect(pool['i1']!.data, _bytes(4, 1));
      expect(pool.remove('i1'), isTrue);
      expect(pool.contains('i1'), isFalse);
    });

    test('addDeduplicated returns existing uuid for identical bytes', () {
      final pool = CustomIconPool();
      final u1 = pool.addDeduplicated('i1', _bytes(8, 7));
      final u2 = pool.addDeduplicated('i2', _bytes(8, 7)); // same content
      expect(u1, 'i1');
      expect(u2, 'i1', reason: 'dedup → reuse existing uuid');
      expect(pool.length, 1);
    });

    test('addDeduplicated stores distinct content under new uuid', () {
      final pool = CustomIconPool();
      pool.addDeduplicated('i1', _bytes(8, 7));
      final u2 = pool.addDeduplicated('i2', _bytes(8, 9));
      expect(u2, 'i2');
      expect(pool.length, 2);
    });
  });

  group('CustomIconService reference scanning + prune', () {
    Database dbWith(Group root) => Database(meta: DatabaseMeta(name: 'd'), root: root);

    test('referencedUuids collects from nested groups and entries', () {
      final root = Group(uuid: 'r', name: 'Root', entries: [
        _entry('e1', customIcon: 'used-a'),
      ], groups: [
        Group(uuid: 'g', name: 'G', entries: [_entry('e2', customIcon: 'used-b')])
          ..customIconUuid = 'used-grp',
      ],);
      final refs = const CustomIconService().referencedUuids(dbWith(root));
      expect(refs, {'used-a', 'used-b', 'used-grp'});
    });

    test('orphans + pruneOrphans remove only unreferenced icons', () {
      final root = Group(uuid: 'r', name: 'Root', entries: [
        _entry('e1', customIcon: 'used'),
      ],);
      final db = dbWith(root);
      final pool = CustomIconPool()
        ..add(CustomIcon(uuid: 'used', data: _bytes(2, 1)))
        ..add(CustomIcon(uuid: 'orphan', data: _bytes(2, 2)));
      const svc = CustomIconService();
      expect(svc.orphans(db, pool), ['orphan']);
      expect(svc.pruneOrphans(db, pool), 1);
      expect(pool.contains('used'), isTrue);
      expect(pool.contains('orphan'), isFalse);
    });
  });
}
