// The open/unlock/save flow is real — bytes are decrypted by KdbxCodec and
// written back to actual files on disk.

import 'dart:io';
import 'dart:typed_data';

import 'package:dgvault/ui/state/vault_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_vault.dart';

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
    expect(c.entryCount, 2);

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
