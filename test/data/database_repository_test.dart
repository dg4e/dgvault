import 'package:dgvault/core/core.dart';
import 'package:dgvault/data/database_repository.dart';
import 'package:test/test.dart';

Entry _e(String uuid) => Entry(uuid: uuid);

(Database, Group, Group) _fixture({bool readOnly = false}) {
  final work = Group(uuid: 'work', name: 'Work', entries: [_e('a')]);
  final personal = Group(uuid: 'personal', name: 'Personal');
  final root = Group(uuid: 'root', name: 'Root', groups: [work, personal]);
  final db = Database(
    meta: DatabaseMeta(name: 'T'),
    root: root,
    readOnly: readOnly,
  );
  return (db, work, personal);
}

void main() {
  group('reads (always allowed)', () {
    test('findEntry and findGroupOf traverse the tree', () {
      final (db, work, _) = _fixture();
      final repo = InMemoryDatabaseRepository(db);
      final a = repo.findEntry('a');
      expect(a, isNotNull);
      expect(repo.findGroupOf(a!), same(work));
      expect(repo.findEntry('missing'), isNull);
      expect(repo.allEntries.map((e) => e.uuid), ['a']);
    });
  });

  group('writes on a writable database', () {
    test('add, move, and delete entries', () {
      final (db, work, personal) = _fixture();
      final repo = InMemoryDatabaseRepository(db);
      final b = _e('b');

      repo.addEntry(work, b);
      expect(work.entries.map((e) => e.uuid), ['a', 'b']);

      repo.moveEntry(b, personal);
      expect(work.entries.map((e) => e.uuid), ['a']);
      expect(personal.entries.map((e) => e.uuid), ['b']);

      repo.deleteEntry(b);
      expect(personal.entries, isEmpty);
    });

    test('moveEntry to the same group is a no-op', () {
      final (db, work, _) = _fixture();
      final repo = InMemoryDatabaseRepository(db);
      final a = repo.findEntry('a')!;
      repo.moveEntry(a, work);
      expect(work.entries.map((e) => e.uuid), ['a']);
    });
  });

  group('read-only guard', () {
    test('every mutation throws ReadOnlyDatabaseException', () {
      final (db, work, personal) = _fixture(readOnly: true);
      final repo = InMemoryDatabaseRepository(db);
      final a = repo.findEntry('a')!;

      expect(() => repo.addEntry(work, _e('x')),
          throwsA(isA<ReadOnlyDatabaseException>()));
      expect(() => repo.moveEntry(a, personal),
          throwsA(isA<ReadOnlyDatabaseException>()));
      expect(() => repo.deleteEntry(a),
          throwsA(isA<ReadOnlyDatabaseException>()));
      expect(() => repo.addGroup(work, Group(uuid: 'g', name: 'G')),
          throwsA(isA<ReadOnlyDatabaseException>()));
      // Tree is untouched after rejected writes.
      expect(work.entries.map((e) => e.uuid), ['a']);
    });

    test('toggling read-only off re-enables writes', () {
      final (db, work, _) = _fixture(readOnly: true);
      final repo = InMemoryDatabaseRepository(db);
      expect(repo.isReadOnly, isTrue);

      repo.setReadOnly(false);
      expect(repo.isReadOnly, isFalse);
      repo.addEntry(work, _e('c'));
      expect(work.entries.map((e) => e.uuid), ['a', 'c']);
    });
  });
}
