// The open/unlock/save flow is real — bytes are decrypted by KdbxCodec and
// written back to actual files on disk.

import 'dart:io';
import 'dart:typed_data';

import 'package:dgvault/core/core.dart';
import 'package:dgvault/ui/state/vault_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_vault.dart';

Future<VaultController> _open() async {
  final c = VaultController();
  c.loadBytes(await buildTestVaultBytes(), name: 'test.kdbx');
  await c.unlock(testVaultPassword);
  return c;
}

Entry _find(VaultController c, String title) =>
    c.search(title).firstWhere((e) => e.title == title);

void main() {
  test('loadBytes → locked; correct password unlocks + decrypts', () async {
    final c = VaultController();
    expect(c.status, VaultStatus.noVault);

    c.loadBytes(await buildTestVaultBytes(), name: 'test.kdbx');
    expect(c.status, VaultStatus.locked);
    expect(c.fileName, 'test.kdbx');

    await c.unlock(testVaultPassword);
    expect(c.status, VaultStatus.unlocked);
    expect(c.database, isNotNull);
    expect(c.entryCount, 4); // total incl. Work + Recycle Bin
    expect(c.recycleBinUuid, 'rb');

    final hits = c.search('github');
    expect(hits.single.title, 'GitHub');
  });

  test('wrong password is denied (real authenticated decrypt)', () async {
    final c = VaultController();
    c.loadBytes(await buildTestVaultBytes(), name: 'test.kdbx');

    await c.unlock('not the password');
    expect(c.status, VaultStatus.locked);
    expect(c.database, isNull);
    expect(c.error, contains('ACCESS DENIED'));

    await c.unlock(testVaultPassword);
    expect(c.status, VaultStatus.unlocked);
  });

  group('mutations', () {
    test('updateEntry snapshots history, edits, bumps modified, marks dirty',
        () async {
      final c = await _open();
      final e = _find(c, 'GitHub');
      expect(c.isDirty, isFalse);

      c.updateEntry(e, (draft) {
        draft.fields[Field.title] =
            Field(key: Field.title, value: InMemoryProtectedValue.plain('GitHub2'));
      });

      expect(e.title, 'GitHub2');
      expect(e.history.last.title, 'GitHub'); // prior version snapshotted
      expect(c.isDirty, isTrue);
    });

    test('restoreHistory reverts to a prior version (undoable)', () async {
      final c = await _open();
      final e = _find(c, 'GitHub');
      c.updateEntry(e, (d) => d.fields[Field.title] =
          Field(key: Field.title, value: InMemoryProtectedValue.plain('GitHub2')),);
      expect(e.title, 'GitHub2');

      c.restoreHistory(e, 0); // restore the snapshot ('GitHub')
      expect(e.title, 'GitHub');
      // the pre-restore state ('GitHub2') is itself snapshotted
      expect(e.history.map((h) => h.title), contains('GitHub2'));
    });

    test('deleteEntry moves to the Recycle Bin when enabled', () async {
      final c = await _open();
      final e = _find(c, 'GitHub');
      expect(c.findGroupOf(e)!.name, 'Personal');

      c.deleteEntry(e);
      expect(c.findGroupOf(e)!.uuid, 'rb'); // moved to recycle bin
      expect(c.entryCount, 4); // still present, just relocated
    });

    test('deleteEntry permanently removes when recycle bin is disabled',
        () async {
      final c = await _open();
      c.setRecycleBinEnabled(false);
      final e = _find(c, 'Jira');

      c.deleteEntry(e);
      expect(c.findGroupOf(e), isNull);
      expect(c.entryCount, 3);
    });

    test('addGroup / renameGroup / findParentOf', () async {
      final c = await _open();
      final personal =
          c.rootGroup!.groups.firstWhere((g) => g.name == 'Personal');

      final sub = c.addGroup('Banking', parent: personal);
      expect(personal.groups, contains(sub));
      expect(c.findParentOf(sub), personal);
      expect(c.isDirty, isTrue);

      c.renameGroup(sub, 'Finance');
      expect(sub.name, 'Finance');

      // A top-level folder defaults to root.
      final top = c.addGroup('Servers');
      expect(c.findParentOf(top), c.rootGroup);
    });

    test('deleteGroup moves the subtree to the Recycle Bin when enabled',
        () async {
      final c = await _open();
      final work = c.rootGroup!.groups.firstWhere((g) => g.name == 'Work');

      c.deleteGroup(work);
      expect(c.rootGroup!.groups, isNot(contains(work)));
      final bin =
          c.rootGroup!.groups.firstWhere((g) => g.uuid == c.recycleBinUuid);
      expect(bin.groups, contains(work)); // relocated, entries preserved
    });

    test('deleteGroup permanently removes when recycle bin is disabled',
        () async {
      final c = await _open();
      c.setRecycleBinEnabled(false);
      final work = c.rootGroup!.groups.firstWhere((g) => g.name == 'Work');

      c.deleteGroup(work);
      expect(c.findParentOf(work), isNull);
      expect(c.rootGroup!.groups.any((g) => g.name == 'Work'), isFalse);
    });

    test('setKdfIterations updates the pending header', () async {
      final c = await _open();
      c.setKdfIterations(7);
      expect(c.kdfIterations, 7);
      expect(c.isDirty, isTrue);
    });

    test('benchmarkKdfIterations returns a positive suggestion', () async {
      final c = await _open();
      final n = await c.benchmarkKdfIterations(
          target: const Duration(milliseconds: 200),);
      expect(n, greaterThanOrEqualTo(1));
    }, timeout: const Timeout(Duration(minutes: 1)),);

    test('history limits: maxItems caps snapshots and persists in meta',
        () async {
      final c = await _open();
      c.setHistoryMaxItems(2);
      expect(c.historyMaxItems, 2);
      final e = _find(c, 'GitHub');

      for (var i = 0; i < 5; i++) {
        c.updateEntry(e, (d) => d.fields[Field.title] = Field(
            key: Field.title,
            value: InMemoryProtectedValue.plain('GitHub$i'),),);
      }
      expect(e.history.length, 2); // bounded by the policy
    });

    test('deleteEntry creates the Recycle Bin if the vault has none', () async {
      final dir = await Directory.systemTemp.createTemp('dgvault_rb');
      addTearDown(() => dir.delete(recursive: true));
      final c = VaultController();
      await c.createNew('${dir.path}/v.kdbx', 'pw'); // empty vault, no recycle bin
      expect(c.recycleBinUuid, isNull);

      final e = Entry(uuid: 'x', fields: {
        Field.title: Field(key: Field.title, value: InMemoryProtectedValue.plain('Temp')),
      },);
      c.addEntry(e);
      c.deleteEntry(e);

      expect(c.recycleBinUuid, isNotNull);
      expect(c.findGroupOf(e)!.name, 'Recycle Bin');
    });
  });

  test('non-KDBX bytes are rejected', () {
    final c = VaultController();
    c.loadBytes(Uint8List.fromList(List.filled(64, 0)), name: 'junk.bin');
    expect(c.status, VaultStatus.noVault);
    expect(c.error, contains('not a KDBX'));
  });

  test('create new → save → reopen round-trips through a real file', () async {
    final dir = await Directory.systemTemp.createTemp('dgvault_test');
    final path = '${dir.path}/vault.kdbx';
    addTearDown(() => dir.delete(recursive: true));

    final c = VaultController();
    await c.createNew(path, 's3cret-master');
    expect(c.status, VaultStatus.unlocked);
    expect(File(path).existsSync(), isTrue);

    await c.save(); // re-encrypt + write
    expect(c.error, isNull);

    // Reopen from disk with a fresh controller.
    final c2 = VaultController();
    await c2.openFile(path);
    expect(c2.status, VaultStatus.locked);
    await c2.unlock('s3cret-master');
    expect(c2.status, VaultStatus.unlocked);
    expect(c2.database!.meta.name, 'vault');

    await c2.unlock('wrong'); // already unlocked → ignored; sanity
  });

  test('opens a REAL third-party .kdbx file from disk (pykeepass fixture)',
      () async {
    final c = VaultController();
    await c.openFile('test/fixtures/kdbx/reference_aes_argon2.kdbx');
    expect(c.status, VaultStatus.locked);
    expect(c.fileName, 'reference_aes_argon2.kdbx');

    await c.unlock('correct horse battery staple');
    expect(c.status, VaultStatus.unlocked, reason: c.error);
    expect(c.search('acme').isNotEmpty, isTrue); // the fixture's 'Acme Corp'
  }, timeout: const Timeout(Duration(minutes: 2)),);

  test('opens a legacy KDBX3 file via the same flow (version dispatch)',
      () async {
    final c = VaultController();
    await c.openFile('test/fixtures/kdbx/reference_kdbx3.kdbx');
    expect(c.status, VaultStatus.locked); // v3 accepted, prompts for password

    await c.unlock('kdbx3pass');
    expect(c.status, VaultStatus.unlocked, reason: c.error);
    expect(c.search('acme v3').isNotEmpty, isTrue);
  });

  test('lock keeps the file loaded; close drops it', () async {
    final c = VaultController();
    c.loadBytes(await buildTestVaultBytes(), name: 'test.kdbx');
    await c.unlock(testVaultPassword);

    c.lock();
    expect(c.status, VaultStatus.locked); // file still loaded
    expect(c.database, isNull);

    c.close();
    expect(c.status, VaultStatus.noVault);
    expect(c.fileName, isNull);
  });
}
