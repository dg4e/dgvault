// Drives the real app path the user described: edit an entry's notes several
// times (VaultController.updateEntry, exactly what the editor calls), save to a
// real file each time, then reopen — and assert the entry does NOT multiply.

import 'dart:io';

import 'package:dgvault/core/core.dart';
import 'package:dgvault/ui/state/vault_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_vault.dart';

void main() {
  test('edit notes + save repeatedly, then reopen → entry count stable',
      () async {
    final dir = await Directory.systemTemp.createTemp('dgvault_repro');
    final file = File('${dir.path}/paypal.kdbx');
    await file.writeAsBytes(await buildTestVaultBytes(), flush: true);

    final c = VaultController();
    c.loadBytes(await file.readAsBytes(), name: 'paypal.kdbx', path: file.path);
    await c.unlock(testVaultPassword);

    final before = c.entryCount;
    final entry = c.search('GitHub').single;

    // Edit the notes field and save, several times — the user's repro.
    for (var i = 1; i <= 6; i++) {
      c.updateEntry(entry, (d) {
        d.fields[Field.notes] = Field(
            key: Field.notes,
            value: InMemoryProtectedValue.plain('note version $i'),);
      });
      await c.save();
      expect(c.entryCount, before,
          reason: 'entry multiplied in memory after edit #$i',);
    }

    // Reopen from disk — the fresh parse must still show the same count.
    final c2 = VaultController();
    c2.loadBytes(await file.readAsBytes(),
        name: 'paypal.kdbx', path: file.path,);
    await c2.unlock(testVaultPassword);
    expect(c2.entryCount, before, reason: 'entry multiplied after reopen');

    final gh = c2.search('GitHub');
    expect(gh.length, 1, reason: 'GitHub appears more than once');
    expect(gh.single.history.length, 6, reason: 'history should be nested');

    await dir.delete(recursive: true);
  });
}
