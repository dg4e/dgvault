// Critic-owned adversarial audit for Entry History.
//
// Composer's suite covers snapshot isolation, oldest-first ordering, maxItems
// pruning, maxItems==0, size-keeps-one, the repository wiring, and restore basics.
// These add the edges it doesn't: unlimited (negative-bound) retention, size
// pruning collapsing to exactly one, a *multi-edit* repository round-trip, and
// the documented fact that restore rolls back content but NOT timestamps.
//
// Toolchain not installed here; assertions traced against implementation source
// by hand (see reviews/Critic-round-6.md).

import 'package:dgvault/core/core.dart';
import 'package:dgvault/data/database_repository.dart';
import 'package:test/test.dart';

Entry _entry(Map<String, String> fields, {DateTime? modified}) {
  final map = <String, Field>{};
  fields.forEach((k, v) =>
      map[k] = Field(key: k, value: InMemoryProtectedValue(v, isProtected: k == Field.password)),);
  return Entry(uuid: 'u', fields: map, modified: modified);
}

String _pw(Entry e) => e.fields[Field.password]!.value.reveal();
void _setPw(Entry e, String v) =>
    e.fields[Field.password] = Field(key: Field.password, value: InMemoryProtectedValue(v));

void main() {
  group('retention bounds', () {
    test('negative bounds mean unlimited — no pruning', () {
      final e = _entry({Field.password: 'p'});
      const unlimited = EntryHistoryPolicy(maxItems: -1, maxSizeBytes: -1);
      for (var i = 0; i < 25; i++) {
        EntryHistory.record(e, policy: unlimited);
      }
      expect(e.history.length, 25);
    });

    test('size pruning collapses to exactly one when every version exceeds cap',
        () {
      // Each snapshot ~1010 bytes (500-char Notes); cap is 100.
      final e = _entry({Field.notes: 'x' * 500});
      const policy = EntryHistoryPolicy(maxItems: -1, maxSizeBytes: 100);
      EntryHistory.record(e, policy: policy);
      EntryHistory.record(e, policy: policy);
      EntryHistory.record(e, policy: policy);
      expect(e.history.length, 1, reason: 'always keep the most recent version');
    });
  });

  group('restore semantics', () {
    test('rolls back content but does NOT roll back the modified timestamp', () {
      final t2020 = DateTime.utc(2020);
      final t2025 = DateTime.utc(2025);
      final e = _entry({Field.title: 'old'}, modified: t2020);
      EntryHistory.record(e); // history[0] captures 'old' @ 2020

      // Live edit moves title + timestamp forward.
      e.fields[Field.title] =
          Field(key: Field.title, value: InMemoryProtectedValue.plain('new'));
      e.modified = t2025;

      EntryHistory.restore(e, 0, keepCurrentInHistory: false);
      expect(e.title, 'old', reason: 'content is reverted');
      expect(e.modified, t2025,
          reason: 'restore does not roll back modified — flagged as a KeePass '
              'fidelity gap in the review',);
    });
  });

  group('repository multi-edit round-trip', () {
    test('two sequential edits leave newest live + ordered prior versions', () {
      final e = _entry({Field.password: 'v1'});
      final db = Database(
        meta: DatabaseMeta(name: 'T'),
        root: Group(uuid: 'r', name: 'Root', entries: [e]),
      );
      final repo = InMemoryDatabaseRepository(db);

      repo.updateEntry(e, (x) => _setPw(x, 'v2'));
      repo.updateEntry(e, (x) => _setPw(x, 'v3'));

      expect(_pw(e), 'v3', reason: 'live entry holds the newest value');
      expect(e.history.length, 2);
      expect(_pw(e.history[0]), 'v1', reason: 'oldest-first');
      expect(_pw(e.history[1]), 'v2');
    });

    test('updateEntry on a read-only db neither mutates nor records', () {
      final e = _entry({Field.password: 'v1'});
      final db = Database(
        meta: DatabaseMeta(name: 'T'),
        root: Group(uuid: 'r', name: 'Root', entries: [e]),
        readOnly: true,
      );
      final repo = InMemoryDatabaseRepository(db);
      expect(() => repo.updateEntry(e, (x) => _setPw(x, 'v2')),
          throwsA(isA<ReadOnlyDatabaseException>()),);
      expect(_pw(e), 'v1');
      expect(e.history, isEmpty, reason: 'no snapshot taken when write rejected');
    });
  });
}
