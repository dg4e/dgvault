import 'package:dgvault/core/model/attachment.dart';
import 'package:dgvault/core/model/database.dart';
import 'package:dgvault/core/model/entry.dart';
import 'package:dgvault/core/model/field.dart';
import 'package:dgvault/core/model/group.dart';
import 'package:dgvault/core/model/protected_value.dart';
import 'package:dgvault/core/diff/database_diff.dart';
import 'package:test/test.dart';

Entry e(String uuid,
    {String? title, String? password, DateTime? modified, List<String>? tags}) {
  final f = <String, Field>{};
  if (title != null) {
    f[Field.title] = Field(key: Field.title, value: InMemoryProtectedValue.plain(title));
  }
  if (password != null) {
    f[Field.password] = Field(key: Field.password, value: InMemoryProtectedValue(password));
  }
  return Entry(uuid: uuid, fields: f, modified: modified, tags: tags);
}

Database db(Group root) => Database(meta: DatabaseMeta(name: 'db'), root: root);

void main() {
  group('DatabaseComparator', () {
    test('detects added and removed entries', () {
      final a = db(Group(uuid: 'r', name: 'Root', entries: [e('1', title: 'A')]));
      final b = db(Group(uuid: 'r', name: 'Root', entries: [e('2', title: 'B')]));
      final d = const DatabaseComparator().compare(a, b);
      expect(d.addedEntries, ['2']);
      expect(d.removedEntries, ['1']);
      expect(d.hasDifferences, isTrue);
    });

    test('detects field modifications with old/new values', () {
      final a = db(Group(uuid: 'r', name: 'Root', entries: [e('1', title: 'Old', password: 'p')]));
      final b = db(Group(uuid: 'r', name: 'Root', entries: [e('1', title: 'New', password: 'p')]));
      final d = const DatabaseComparator().compare(a, b);
      expect(d.modifiedEntries, hasLength(1));
      final m = d.modifiedEntries.single;
      final titleChange = m.fieldChanges.singleWhere((c) => c.key == Field.title);
      expect(titleChange.oldValue, 'Old');
      expect(titleChange.newValue, 'New');
      expect(m.moved, isFalse);
    });

    test('detects a moved entry (different parent group)', () {
      final moved = e('1', title: 'X');
      final a = db(Group(uuid: 'r', name: 'Root', groups: [
        Group(uuid: 'g1', name: 'G1', entries: [moved]),
        Group(uuid: 'g2', name: 'G2'),
      ]));
      final b = db(Group(uuid: 'r', name: 'Root', groups: [
        Group(uuid: 'g1', name: 'G1'),
        Group(uuid: 'g2', name: 'G2', entries: [e('1', title: 'X')]),
      ]));
      final d = const DatabaseComparator().compare(a, b);
      final m = d.modifiedEntries.single;
      expect(m.moved, isTrue);
      expect(m.oldParentUuid, 'g1');
      expect(m.newParentUuid, 'g2');
    });

    test('detects group add/remove/rename', () {
      final a = db(Group(uuid: 'r', name: 'Root', groups: [
        Group(uuid: 'g1', name: 'Old Name'),
        Group(uuid: 'gone', name: 'Gone'),
      ]));
      final b = db(Group(uuid: 'r', name: 'Root', groups: [
        Group(uuid: 'g1', name: 'New Name'),
        Group(uuid: 'new', name: 'Fresh'),
      ]));
      final d = const DatabaseComparator().compare(a, b);
      expect(d.addedGroups, contains('new'));
      expect(d.removedGroups, contains('gone'));
      expect(d.renamedGroups.single.uuid, 'g1');
      expect(d.renamedGroups.single.newName, 'New Name');
    });

    test('identical databases report no differences', () {
      Group mk() => Group(uuid: 'r', name: 'Root', entries: [e('1', title: 'Same', password: 'p')]);
      final d = const DatabaseComparator().compare(db(mk()), db(mk()));
      expect(d.hasDifferences, isFalse);
    });

    test('detects tag changes', () {
      final a = db(Group(uuid: 'r', name: 'Root', entries: [e('1', title: 'T', tags: ['a'])]));
      final b = db(Group(uuid: 'r', name: 'Root', entries: [e('1', title: 'T', tags: ['a', 'b'])]));
      final d = const DatabaseComparator().compare(a, b);
      expect(d.modifiedEntries.single.tagsChanged, isTrue);
    });
  });

  group('DatabaseMerger (last-write-wins)', () {
    test('adds source-only entries under a mirrored group path', () {
      final target = db(Group(uuid: 'r', name: 'Root'));
      final source = db(Group(uuid: 'r2', name: 'Root', groups: [
        Group(uuid: 'f', name: 'Folder', entries: [e('new', title: 'N')]),
      ]));
      final res = const DatabaseMerger().merge(target, source);
      expect(res.added, ['new']);
      final folder = target.root.groups.singleWhere((g) => g.name == 'Folder');
      expect(folder.entries.single.uuid, 'new');
    });

    test('updates when source entry is newer', () {
      final target = db(Group(uuid: 'r', name: 'Root', entries: [
        e('1', title: 'Old', modified: DateTime.utc(2024)),
      ]));
      final source = db(Group(uuid: 'r2', name: 'Root', entries: [
        e('1', title: 'New', modified: DateTime.utc(2026)),
      ]));
      final res = const DatabaseMerger().merge(target, source);
      expect(res.updated, ['1']);
      expect(target.root.entries.single.title, 'New');
    });

    test('does not update when source entry is older', () {
      final target = db(Group(uuid: 'r', name: 'Root', entries: [
        e('1', title: 'Keep', modified: DateTime.utc(2026)),
      ]));
      final source = db(Group(uuid: 'r2', name: 'Root', entries: [
        e('1', title: 'Stale', modified: DateTime.utc(2024)),
      ]));
      final res = const DatabaseMerger().merge(target, source);
      expect(res.updated, isEmpty);
      expect(target.root.entries.single.title, 'Keep');
    });

    test('never deletes target-only entries', () {
      final target = db(Group(uuid: 'r', name: 'Root', entries: [e('keep', title: 'K')]));
      final source = db(Group(uuid: 'r2', name: 'Root'));
      const DatabaseMerger().merge(target, source);
      expect(target.root.entries.any((x) => x.uuid == 'keep'), isTrue);
    });

    test('newer source snapshots the overwritten target to history (M1)', () {
      final target = db(Group(uuid: 'r', name: 'Root', entries: [
        e('1', title: 'Old', modified: DateTime.utc(2024)),
      ]));
      final source = db(Group(uuid: 'r2', name: 'Root', entries: [
        e('1', title: 'New', modified: DateTime.utc(2026)),
      ]));
      const DatabaseMerger().merge(target, source);
      final merged = target.root.entries.single;
      expect(merged.title, 'New');
      expect(merged.history.any((h) => h.title == 'Old'), isTrue,
          reason: 'pre-merge version recoverable');
    });
  });

  group('DatabaseComparator — attachments (M2)', () {
    test('entry differing only in attachments is reported modified', () {
      Entry withAtt(List<Attachment> a) =>
          Entry(uuid: '1', fields: {
            Field.title: Field(key: Field.title, value: InMemoryProtectedValue.plain('T')),
          }, attachments: a);
      final a = db(Group(uuid: 'r', name: 'Root', entries: [withAtt([])]));
      final b = db(Group(uuid: 'r', name: 'Root', entries: [
        withAtt([Attachment(id: 'b1', name: 'f.png', size: 10)]),
      ]));
      final d = const DatabaseComparator().compare(a, b);
      expect(d.modifiedEntries.single.attachmentsChanged, isTrue);
    });
  });
}
