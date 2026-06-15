import 'package:dgvault/core/core.dart';
import 'package:dgvault/data/database_repository.dart';
import 'package:test/test.dart';

Entry _entry(String uuid, String password, {List<String>? tags}) {
  return Entry(
    uuid: uuid,
    fields: {
      Field.password: Field(
        key: Field.password,
        value: InMemoryProtectedValue(password),
      ),
    },
    tags: tags,
  );
}

void main() {
  group('snapshotOf', () {
    test('copies fields/tags but carries no nested history', () {
      final e = _entry('e1', 'v1', tags: ['a']);
      e.history.add(_entry('e1', 'old'));
      final snap = EntryHistory.snapshotOf(e);
      expect(snap.uuid, 'e1');
      expect(snap.fields[Field.password]!.value.reveal(), 'v1');
      expect(snap.tags, ['a']);
      expect(snap.history, isEmpty);
    });

    test('snapshot is independent of later disposal of the live value', () {
      final e = _entry('e1', 'secret');
      final snap = EntryHistory.snapshotOf(e);
      e.fields[Field.password]!.value.dispose();
      // Live value is now wiped, but the snapshot keeps its own copy.
      expect(snap.fields[Field.password]!.value.reveal(), 'secret');
    });
  });

  group('record + prune', () {
    test('records prior versions oldest-first', () {
      final e = _entry('e1', 'v1');
      EntryHistory.record(e); // captures v1
      e.fields[Field.password] = Field(
        key: Field.password,
        value: InMemoryProtectedValue('v2'),
      );
      EntryHistory.record(e); // captures v2
      expect(e.history.map((h) => h.fields[Field.password]!.value.reveal()),
          ['v1', 'v2'],);
    });

    test('maxItems prunes the oldest', () {
      final e = _entry('e1', 'v');
      const policy = EntryHistoryPolicy(maxItems: 3, maxSizeBytes: -1);
      for (var i = 0; i < 6; i++) {
        e.fields[Field.password] = Field(
          key: Field.password,
          value: InMemoryProtectedValue('v$i'),
        );
        EntryHistory.record(e, policy: policy);
      }
      expect(e.history.length, 3);
      // Oldest three (v0,v1,v2) dropped; newest three remain.
      expect(e.history.map((h) => h.fields[Field.password]!.value.reveal()),
          ['v3', 'v4', 'v5'],);
    });

    test('maxItems == 0 keeps no history', () {
      final e = _entry('e1', 'v');
      EntryHistory.record(e, policy: const EntryHistoryPolicy(maxItems: 0));
      expect(e.history, isEmpty);
    });

    test('size pruning always keeps at least one version', () {
      final e = _entry('e1', 'a-very-long-password-value-exceeding-limit');
      const tiny = EntryHistoryPolicy(maxItems: -1, maxSizeBytes: 1);
      EntryHistory.record(e, policy: tiny);
      EntryHistory.record(e, policy: tiny);
      expect(e.history.length, 1);
    });
  });

  group('repository updateEntry wiring', () {
    test('snapshots prior state then applies the mutation', () {
      final e = _entry('e1', 'old');
      final root = Group(uuid: 'r', name: 'Root', entries: [e]);
      final repo = InMemoryDatabaseRepository(
        Database(meta: DatabaseMeta(name: 'T'), root: root),
      );

      repo.updateEntry(e, (draft) {
        draft.fields[Field.password] = Field(
          key: Field.password,
          value: InMemoryProtectedValue('new'),
        );
      });

      expect(e.fields[Field.password]!.value.reveal(), 'new');
      expect(e.history.single.fields[Field.password]!.value.reveal(), 'old');
    });

    test('updateEntry is rejected on a read-only database', () {
      final e = _entry('e1', 'v');
      final root = Group(uuid: 'r', name: 'Root', entries: [e]);
      final repo = InMemoryDatabaseRepository(
        Database(meta: DatabaseMeta(name: 'T'), root: root, readOnly: true),
      );
      expect(
        () => repo.updateEntry(e, (_) {}),
        throwsA(isA<ReadOnlyDatabaseException>()),
      );
      expect(e.history, isEmpty); // no snapshot taken on rejection
    });
  });

  group('restore', () {
    test('reverts a prior version and keeps the pre-restore state undoable', () {
      final e = _entry('e1', 'v1');
      EntryHistory.record(e); // history: [v1]
      e.fields[Field.password] = Field(
        key: Field.password,
        value: InMemoryProtectedValue('v2'),
      );

      EntryHistory.restore(e, 0); // restore v1; snapshot v2 first
      expect(e.fields[Field.password]!.value.reveal(), 'v1');
      // The pre-restore value (v2) was captured so the restore is undoable.
      expect(
        e.history.map((h) => h.fields[Field.password]!.value.reveal()),
        contains('v2'),
      );
    });

    test('out-of-range index throws', () {
      final e = _entry('e1', 'v');
      expect(() => EntryHistory.restore(e, 0), throwsRangeError);
    });

    test('clearHistory empties history', () {
      final e = _entry('e1', 'v');
      EntryHistory.record(e);
      EntryHistory.clearHistory(e);
      expect(e.history, isEmpty);
    });
  });
}
