// Critic-owned adversarial audit for Advanced Merge + cross-DB transfer.
//
// Targets the data-integrity edges of sync/merge and move/copy — where silent
// loss or reference corruption of credential data is the worst outcome. Positive
// paths confirm correctness; the DATA-LOSS / CORRUPTION groups pin current
// behaviour so a fix is a deliberate, visible change (flagged in the review).
//
// Toolchain not installed here; assertions traced against implementation source
// by hand (see reviews/Critic-round-8.md).

import 'package:dgvault/core/core.dart';
import 'package:dgvault/core/diff/database_diff.dart';
import 'package:dgvault/data/database_transfer.dart';
import 'package:dgvault/data/database_repository.dart';
import 'package:test/test.dart';

Entry _entry(
  String uuid,
  Map<String, String> fields, {
  DateTime? modified,
  List<Attachment>? attachments,
  List<String>? tags,
}) {
  final map = <String, Field>{};
  fields.forEach((k, v) => map[k] =
      Field(key: k, value: InMemoryProtectedValue(v, isProtected: k == Field.password)));
  return Entry(uuid: uuid, fields: map, modified: modified, attachments: attachments, tags: tags);
}

Database _db(List<Entry> entries, {List<Attachment>? pool, bool readOnly = false}) =>
    Database(
      meta: DatabaseMeta(name: 'd'),
      root: Group(uuid: 'root', name: 'Root', entries: entries),
      binaryPool: pool,
      readOnly: readOnly,
    );

String _pw(Entry e) => e.fields[Field.password]!.value.reveal();

void main() {
  group('DatabaseMerger — last-write-wins correctness', () {
    test('strictly-newer source replaces target content', () {
      final t = _db([_entry('e', {Field.password: 'old'}, modified: DateTime.utc(2020))]);
      final s = _db([_entry('e', {Field.password: 'new'}, modified: DateTime.utc(2025))]);
      final res = const DatabaseMerger().merge(t, s);
      expect(res.updated, ['e']);
      expect(_pw(t.root.entries.single), 'new');
    });

    test('older source is ignored', () {
      final t = _db([_entry('e', {Field.password: 'keep'}, modified: DateTime.utc(2025))]);
      final s = _db([_entry('e', {Field.password: 'stale'}, modified: DateTime.utc(2020))]);
      final res = const DatabaseMerger().merge(t, s);
      expect(res.updated, isEmpty);
      expect(_pw(t.root.entries.single), 'keep');
    });

    test('equal timestamps: source does not win (target retained)', () {
      final ts = DateTime.utc(2025);
      final t = _db([_entry('e', {Field.password: 'tval'}, modified: ts)]);
      final s = _db([_entry('e', {Field.password: 'sval'}, modified: ts)]);
      const DatabaseMerger().merge(t, s);
      expect(_pw(t.root.entries.single), 'tval');
    });

    test('source-only entry is added as an isolated deep copy', () {
      final t = _db(<Entry>[]);
      final src = _entry('s1', {Field.title: 'New'}, modified: DateTime.utc(2025));
      final res = const DatabaseMerger().merge(t, _db([src]));
      expect(res.added, ['s1']);
      final added = t.root.entries.single;
      expect(added.fields[Field.title]!.value.reveal(), 'New');
      // mutating the source must not bleed into the merged copy
      src.fields[Field.title] =
          Field(key: Field.title, value: InMemoryProtectedValue.plain('Mutated'));
      expect(added.fields[Field.title]!.value.reveal(), 'New');
    });

    test('deletions are not propagated (target-only entry survives)', () {
      final t = _db([_entry('keep', {Field.title: 'K'}, modified: DateTime.utc(2025))]);
      const DatabaseMerger().merge(t, _db(<Entry>[]));
      expect(t.root.entries.length, 1);
    });
  });

  group('DatabaseMerger — concurrent edits keep a recovery trail (R9 fix)', () {
    test('overwritten target version is snapshotted to history (recoverable)', () {
      // target edited the username; source edited the password slightly later.
      final t = _db([
        _entry('e', {Field.userName: 'alice-edited', Field.password: 'orig'},
            modified: DateTime.utc(2025, 1, 1)),
      ]);
      final s = _db([
        _entry('e', {Field.userName: 'alice', Field.password: 'src-edited'},
            modified: DateTime.utc(2025, 1, 2)),
      ]);
      const DatabaseMerger().merge(t, s);
      final merged = t.root.entries.single;
      // Whole-entry LWW: source (newer) wins the live values...
      expect(merged.fields[Field.userName]!.value.reveal(), 'alice');
      expect(_pw(merged), 'src-edited');
      // ...but the overwritten target version is now preserved in history,
      // so the losing-side edit ('alice-edited') is recoverable (Critic M1 fix).
      expect(merged.history, isNotEmpty);
      expect(
        merged.history.any(
            (h) => h.fields[Field.userName]?.value.reveal() == 'alice-edited'),
        isTrue,
        reason: 'pre-merge target snapshot must be recoverable',
      );
    });
  });

  group('DatabaseTransfer.moveEntry — correctness', () {
    test('relinks binary into dest pool and prunes the source orphan', () {
      final e = _entry('e', {Field.title: 'X'},
          attachments: [Attachment(id: 'b1', name: 'f.png', size: 10)]);
      final source = _db([e], pool: [Attachment(id: 'b1', name: 'f.png', size: 10)]);
      final dest = _db(<Entry>[], pool: <Attachment>[]);

      const DatabaseTransfer().moveEntry(source, e, dest, dest.root);

      expect(source.root.entries, isEmpty);
      expect(dest.root.entries.single.uuid, 'e');
      final movedRefId = dest.root.entries.single.attachments.single.id;
      expect(dest.binaryPool.any((b) => b.id == movedRefId), isTrue);
      expect(source.binaryPool, isEmpty, reason: 'orphaned source binary pruned');
    });

    test('rejects move when destination is read-only', () {
      final e = _entry('e', {Field.title: 'X'});
      expect(
        () => const DatabaseTransfer()
            .moveEntry(_db([e]), e, _db(<Entry>[], readOnly: true), _db(<Entry>[]).root),
        throwsA(isA<ReadOnlyDatabaseException>()),
      );
    });

    test('rejects move on UUID collision in destination', () {
      final e = _entry('dup', {Field.title: 'X'});
      final dest = _db([_entry('dup', {Field.title: 'Y'})]);
      expect(
        () => const DatabaseTransfer().moveEntry(_db([e]), e, dest, dest.root),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('DatabaseTransfer.copyEntry — CORRUPTION (flagged)', () {
    test('copy mutates the SOURCE entry ref and aliases the object', () {
      // Source binary 'b1'; dest already has a *different* binary under id 'b1',
      // forcing a fresh minted id — which gets written back into the entry.
      final e = _entry('e', {Field.title: 'X'},
          attachments: [Attachment(id: 'b1', name: 'f.png', size: 10)]);
      final source = _db([e], pool: [Attachment(id: 'b1', name: 'f.png', size: 10)]);
      final dest = _db(<Entry>[], pool: [Attachment(id: 'b1', name: 'other.png', size: 99)]);

      const DatabaseTransfer().copyEntry(e, source, dest, dest.root);

      // BUG: copyEntry relinked the SOURCE entry's own attachment to a dest id
      // that does not exist in the source pool — "source unchanged" is violated.
      expect(source.root.entries.single.attachments.single.id, isNot('b1'),
          reason: 'source entry attachment ref corrupted by copy');
      // And the SAME object now lives in both databases (aliasing).
      expect(identical(source.root.entries.single, dest.root.entries.single), isTrue,
          reason: 'copy shares one Entry object across two databases');
    });
  });
}
