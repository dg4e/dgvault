// Reproduction: editing an entry's notes repeatedly (each save snapshots the
// prior version into History) must NOT resurface those versions as separate
// live entries after a write→read round-trip.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dgvault/core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../ui/test_vault.dart';

void main() {
  test('edit notes N times, save, reload → still ONE entry (history nested)',
      () async {
    final entry = Entry(
      uuid: 'paypal-uuid',
      fields: {
        Field.title: Field(
            key: Field.title,
            value: InMemoryProtectedValue.plain('paypal'),),
        Field.userName: Field(
            key: Field.userName,
            value: InMemoryProtectedValue.plain('sales@digitalgangster.com'),),
        Field.notes:
            Field(key: Field.notes, value: InMemoryProtectedValue.plain('v0')),
      },
      modified: DateTime.utc(2026, 1, 1),
    );
    final db = Database(
      meta: DatabaseMeta(name: 'repro'),
      root: Group(uuid: 'root', name: 'Root', entries: [entry]),
    );

    // Simulate the user: edit the notes field and save, several times.
    for (var i = 1; i <= 8; i++) {
      EntryHistory.record(entry);
      entry.fields[Field.notes] =
          Field(key: Field.notes, value: InMemoryProtectedValue.plain('v$i'));
      entry.modified = DateTime.utc(2026, 1, 1 + i);
    }

    expect(db.root.allEntries.length, 1, reason: 'in-memory before save');
    expect(entry.history.length, 8);

    final cred =
        CompositeCredential(password: Uint8List.fromList(utf8.encode('pw')));

    // Write → read through the real KDBX codec.
    final bytes = await testCodec().write(db, testHeader(), cred);
    final reloaded = await testCodec().read(bytes, cred);

    final live = reloaded.root.allEntries.toList();
    expect(live.length, 1,
        reason: 'after reload, history must stay nested, not become siblings',);
    expect(live.single.title, 'paypal');
    expect(live.single.history.length, 8);
  });
}
