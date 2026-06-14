import 'dart:typed_data';

import 'package:dgvault/core/core.dart';
import 'package:dgvault/data/database_repository.dart';
import 'package:dgvault/data/database_transfer.dart';
import 'package:test/test.dart';

Attachment _bin(String id, {String name = 'file.bin', int size = 3}) =>
    Attachment(id: id, name: name, size: size, inlineData: Uint8List(size));

Entry _entry(String uuid, {List<Attachment>? atts}) =>
    Entry(uuid: uuid, attachments: atts);

Database _db(
  String name, {
  List<Entry>? entries,
  List<Attachment>? pool,
  bool readOnly = false,
}) {
  final root = Group(uuid: '$name-root', name: 'Root', entries: entries);
  return Database(
    meta: DatabaseMeta(name: name),
    root: root,
    binaryPool: pool,
    readOnly: readOnly,
  );
}

void main() {
  const transfer = DatabaseTransfer();

  test('moves an entry and relinks its attachment into the dest pool', () {
    final att = _bin('b1');
    final entry = _entry('e1', atts: [att]);
    final src = _db('src', entries: [entry], pool: [_bin('b1')]);
    final dst = _db('dst');

    transfer.moveEntry(src, entry, dst, dst.root);

    // Entry left source, entered dest.
    expect(src.root.allEntries, isEmpty);
    expect(dst.root.entries.single.uuid, 'e1');
    // Binary relinked into dest pool, orphan pruned from source.
    expect(dst.binaryPool.map((b) => b.id), ['b1']);
    expect(src.binaryPool, isEmpty);
  });

  test('keeps a source binary still referenced by another entry', () {
    final shared = _bin('b1');
    final moving = _entry('e1', atts: [shared]);
    final staying = _entry('e2', atts: [_bin('b1')]);
    final src = _db('src', entries: [moving, staying], pool: [_bin('b1')]);
    final dst = _db('dst');

    transfer.moveEntry(src, moving, dst, dst.root);

    expect(src.root.allEntries.map((e) => e.uuid), ['e2']);
    expect(src.binaryPool.map((b) => b.id), ['b1']); // still referenced by e2
    expect(dst.binaryPool.map((b) => b.id), ['b1']);
  });

  test('mints a fresh id when the dest pool id collides with other content', () {
    final att = _bin('b1', name: 'mine.txt', size: 10);
    final entry = _entry('e1', atts: [att]);
    final src = _db('src', entries: [entry], pool: [_bin('b1', name: 'mine.txt', size: 10)]);
    // Destination already has a DIFFERENT binary under id 'b1'.
    final dst = _db('dst', pool: [_bin('b1', name: 'theirs.txt', size: 99)]);

    transfer.moveEntry(src, entry, dst, dst.root);

    final moved = dst.root.entries.single;
    expect(moved.attachments.single.id, isNot('b1')); // re-id'd to avoid clash
    expect(dst.binaryPool.length, 2);
    expect(dst.binaryPool.map((b) => b.name), containsAll(['theirs.txt', 'mine.txt']));
  });

  test('reuses an identical binary already present in dest', () {
    final att = _bin('b1', name: 'same.txt', size: 5);
    final entry = _entry('e1', atts: [att]);
    final src = _db('src', entries: [entry], pool: [_bin('b1', name: 'same.txt', size: 5)]);
    final dst = _db('dst', pool: [_bin('b1', name: 'same.txt', size: 5)]);

    transfer.moveEntry(src, entry, dst, dst.root);

    expect(dst.root.entries.single.attachments.single.id, 'b1');
    expect(dst.binaryPool.length, 1); // not duplicated
  });

  group('guards', () {
    test('rejects move when source is read-only', () {
      final e = _entry('e1');
      final src = _db('src', entries: [e], readOnly: true);
      final dst = _db('dst');
      expect(() => transfer.moveEntry(src, e, dst, dst.root),
          throwsA(isA<ReadOnlyDatabaseException>()));
    });

    test('rejects move when dest is read-only', () {
      final e = _entry('e1');
      final src = _db('src', entries: [e]);
      final dst = _db('dst', readOnly: true);
      expect(() => transfer.moveEntry(src, e, dst, dst.root),
          throwsA(isA<ReadOnlyDatabaseException>()));
    });

    test('rejects a UUID collision in the destination', () {
      final e = _entry('dup');
      final src = _db('src', entries: [e]);
      final dst = _db('dst', entries: [_entry('dup')]);
      expect(() => transfer.moveEntry(src, e, dst, dst.root),
          throwsStateError);
    });

    test('throws when the entry is not in the source', () {
      final orphan = _entry('ghost');
      final src = _db('src');
      final dst = _db('dst');
      expect(() => transfer.moveEntry(src, orphan, dst, dst.root),
          throwsStateError);
    });
  });

  test('copyEntry leaves the source intact', () {
    final att = _bin('b1');
    final entry = _entry('e1', atts: [att]);
    final src = _db('src', entries: [entry], pool: [_bin('b1')]);
    final dst = _db('dst');

    transfer.copyEntry(entry, src, dst, dst.root);

    expect(src.root.entries.single.uuid, 'e1'); // still in source
    expect(src.binaryPool.map((b) => b.id), ['b1']); // source pool intact
    expect(dst.binaryPool.map((b) => b.id), ['b1']);
  });

  // Regression for Critic R8 finding T1: copy must deep-clone, never aliasing
  // the source entry nor rewriting its attachment ids.
  test('copyEntry deep-clones — source ref untouched on id collision', () {
    final entry = _entry('e1', atts: [_bin('b1', name: 'mine.png', size: 10)]);
    final src = _db('src',
        entries: [entry], pool: [_bin('b1', name: 'mine.png', size: 10)]);
    // Dest already has a DIFFERENT binary under id 'b1' → forces a minted id.
    final dst = _db('dst', pool: [_bin('b1', name: 'other.png', size: 99)]);

    final copy = transfer.copyEntry(entry, src, dst, dst.root);

    // Source entry's attachment ref is unchanged...
    expect(src.root.entries.single.attachments.single.id, 'b1');
    // ...the dest copy got the minted id...
    expect(copy.attachments.single.id, isNot('b1'));
    // ...and the two databases hold distinct Entry objects.
    expect(identical(src.root.entries.single, dst.root.entries.single), isFalse);
  });
}
