// Whole-vault search excludes the Recycle Bin and a top-level "Backup" archive
// by default (KeePass EnableSearching semantics), stays searchable when scoped
// into those folders, honors an explicit flag, and persists it across save.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dgvault/core/core.dart';
import 'package:dgvault/ui/state/vault_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_vault.dart';

Entry _e(String uuid, String title) => Entry(
      uuid: uuid,
      fields: {
        Field.title:
            Field(key: Field.title, value: InMemoryProtectedValue.plain(title)),
      },
    );

Database _db() => Database(
      meta: DatabaseMeta(name: 'x', recycleBinUuid: 'rb'),
      root: Group(uuid: 'root', name: 'Root', groups: [
        Group(uuid: 'live', name: 'bling', entries: [_e('a', 'paypal')]),
        Group(uuid: 'bk', name: 'Backup', entries: [_e('b', 'paypal')]),
        Group(uuid: 'rb', name: 'Recycle Bin', entries: [_e('c', 'paypal')]),
      ],),
    );

Future<Uint8List> _bytes(Database db) => testCodec().write(
      db,
      testHeader(),
      CompositeCredential(
          password: Uint8List.fromList(utf8.encode(testVaultPassword)),),
    );

Future<VaultController> _open(Uint8List bytes, {String? path}) async {
  final c = VaultController();
  c.loadBytes(bytes, name: 'x.kdbx', path: path);
  await c.unlock(testVaultPassword);
  return c;
}

void main() {
  test('root search skips Backup + Recycle Bin by default', () async {
    final c = await _open(await _bytes(_db()));
    final hits = c.search('paypal');
    expect(hits.map((e) => e.uuid), ['a'], reason: 'only the bling copy');
  });

  test('scoping into Backup / Recycle Bin still searches inside them',
      () async {
    final c = await _open(await _bytes(_db()));
    final root = c.rootGroup!;
    final backup = root.groups.firstWhere((g) => g.name == 'Backup');
    final bin = root.groups.firstWhere((g) => g.name == 'Recycle Bin');
    expect(c.search('paypal', scope: backup).map((e) => e.uuid), ['b']);
    expect(c.search('paypal', scope: bin).map((e) => e.uuid), ['c']);
  });

  test('explicit EnableSearching=true forces a default-off folder back in',
      () async {
    final c = await _open(await _bytes(_db()));
    final backup = c.rootGroup!.groups.firstWhere((g) => g.name == 'Backup');
    expect(c.isGroupSearchable(backup), isFalse);
    c.setGroupSearchable(backup, true);
    expect(c.isGroupSearchable(backup), isTrue);
    expect(c.search('paypal').map((e) => e.uuid).toSet(), {'a', 'b'});
  });

  test('EnableSearching=false persists across save + reload', () async {
    final dir = await Directory.systemTemp.createTemp('dgvault_es');
    final file = File('${dir.path}/x.kdbx');
    await file.writeAsBytes(await _bytes(_db()), flush: true);

    final c = await _open(await file.readAsBytes(), path: file.path);
    final bling = c.rootGroup!.groups.firstWhere((g) => g.name == 'bling');
    c.setGroupSearchable(bling, false);
    await c.save();

    final reloaded = await _open(await file.readAsBytes(), path: file.path);
    final bling2 =
        reloaded.rootGroup!.groups.firstWhere((g) => g.name == 'bling');
    expect(bling2.enableSearching, isFalse);
    // Now every "paypal" is in a non-searchable folder → root search empty.
    expect(reloaded.search('paypal'), isEmpty);

    await dir.delete(recursive: true);
  });
}
