import 'dart:typed_data';

import 'package:dgvault/core/model/database.dart';
import 'package:dgvault/core/model/entry.dart';
import 'package:dgvault/core/model/field.dart';
import 'package:dgvault/core/model/group.dart';
import 'package:dgvault/core/model/protected_value.dart';
import 'package:dgvault/core/entry/entry_services.dart';
import 'package:test/test.dart';

Entry titled(String uuid, String title) => Entry(
      uuid: uuid,
      fields: {Field.title: Field(key: Field.title, value: InMemoryProtectedValue.plain(title))},
    );

Database dbWith(List<Entry> entries) => Database(
      meta: DatabaseMeta(name: 'd'),
      root: Group(uuid: 'r', name: 'Root', entries: entries),
    );

void main() {
  group('EntryCustomFields', () {
    test('set / list / remove custom fields', () {
      final e = titled('e', 'X');
      e.setCustomField('Security Question', 'first pet');
      e.setCustomField('Recovery Code', 'ABCD', protect: true);
      expect(e.customFields().map((f) => f.key).toSet(),
          {'Security Question', 'Recovery Code'},);
      expect(e.fields['Recovery Code']!.isProtected, isTrue);
      expect(e.removeCustomField('Security Question'), isTrue);
      expect(e.removeCustomField('Security Question'), isFalse);
    });

    test('standard keys are rejected by custom-field ops', () {
      final e = titled('e', 'X');
      expect(() => e.setCustomField(Field.password, 'p'),
          throwsA(isA<ArgumentError>()),);
      expect(e.removeCustomField(Field.title), isFalse);
      expect(e.fields.containsKey(Field.title), isTrue);
    });

    test('customFields excludes standard fields', () {
      final e = titled('e', 'X');
      e.setCustomField('k', 'v');
      expect(e.customFields(), hasLength(1));
    });
  });

  group('AttachmentService', () {
    const svc = AttachmentService();

    test('attach stores payload once in the pool and references it', () {
      final e = titled('e', 'X');
      final db = dbWith([e]);
      final ref = svc.attach(db, e, name: 'f.png', data: Uint8List.fromList([1, 2, 3]));
      expect(db.binaryPool, hasLength(1));
      expect(db.binaryPool.single.inlineData, isNotNull);
      expect(db.binaryPool.single.size, 3);
      expect(e.attachments.single.id, ref.id);
      expect(e.attachments.single.inlineData, isNull, reason: 'entry ref is a pointer');
    });

    test('mints unique ids against existing pool', () {
      final e = titled('e', 'X');
      final db = dbWith([e]);
      final a = svc.attach(db, e, name: 'a', data: Uint8List(1));
      final b = svc.attach(db, e, name: 'b', data: Uint8List(1));
      expect(a.id, isNot(b.id));
      expect(db.binaryPool.map((x) => x.id).toSet(), hasLength(2));
    });

    test('detach removes the ref and prunes the orphaned binary', () {
      final e = titled('e', 'X');
      final db = dbWith([e]);
      final ref = svc.attach(db, e, name: 'f', data: Uint8List(2));
      expect(svc.detach(db, e, ref.id), isTrue);
      expect(e.attachments, isEmpty);
      expect(db.binaryPool, isEmpty, reason: 'orphan pruned');
    });

    test('detach keeps a binary still referenced by another entry', () {
      final e1 = titled('e1', 'A');
      final e2 = titled('e2', 'B');
      final db = dbWith([e1, e2]);
      final ref = svc.attach(db, e1, name: 'shared', data: Uint8List(4), id: 'shared-1');
      // e2 references the same pooled binary.
      e2.attachments.add(ref);
      expect(svc.detach(db, e1, 'shared-1'), isTrue);
      expect(db.binaryPool.any((b) => b.id == 'shared-1'), isTrue,
          reason: 'still referenced by e2 → not pruned',);
    });

    test('orphans lists unreferenced pooled binaries', () {
      final e = titled('e', 'X');
      final db = dbWith([e]);
      svc.attach(db, e, name: 'used', data: Uint8List(1));
      svc.detach(db, e, db.binaryPool.first.id, pruneOrphan: false);
      expect(svc.orphans(db), hasLength(1));
    });
  });
}
