// Re-keying a vault, end to end: the file on disk is rewritten under the new
// password, the old one stops working, and a failed write leaves BOTH the file
// and the in-memory credential on the old password (no half-changed state).

import 'dart:io';

import 'package:dgvault/ui/state/vault_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_vault.dart';

const _newPassword = 'a whole new password';

/// A vault written to a real temp file and unlocked, as the app does.
Future<(VaultController, File, Directory)> _openOnDisk() async {
  final dir = await Directory.systemTemp.createTemp('dgvault_rekey');
  final file = File('${dir.path}/vault.kdbx');
  await file.writeAsBytes(await buildTestVaultBytes(), flush: true);

  final c = VaultController();
  c.loadBytes(await file.readAsBytes(), name: 'vault.kdbx', path: file.path);
  await c.unlock(testVaultPassword);
  expect(c.status, VaultStatus.unlocked);
  return (c, file, dir);
}

/// Re-read [file] from scratch and unlock it with [password].
Future<VaultController> _reopen(File file, String password) async {
  final c = VaultController();
  c.loadBytes(await file.readAsBytes(), name: 'vault.kdbx', path: file.path);
  await c.unlock(password);
  return c;
}

Future<bool> _opensWith(File file, String password) async =>
    (await _reopen(file, password)).status == VaultStatus.unlocked;

void main() {
  test('change → file is re-encrypted under the new password only', () async {
    final (c, file, dir) = await _openOnDisk();

    final result = await c.changeMasterPassword(
      currentPassword: testVaultPassword,
      newPassword: _newPassword,
    );

    expect(result, ChangePasswordResult.ok);
    expect(c.error, isNull);
    expect(c.status, VaultStatus.unlocked, reason: 'vault stays open');
    expect(c.entryCount, 4, reason: 're-key must not disturb the contents');

    // The file on disk now opens with the new password and not the old one.
    expect(await _opensWith(file, _newPassword), isTrue);
    expect(await _opensWith(file, testVaultPassword), isFalse);

    // The still-open controller can keep saving under the new credential.
    await c.save();
    expect(c.error, isNull);
    expect(await _opensWith(file, _newPassword), isTrue);

    await dir.delete(recursive: true);
  });

  test('change stamps MasterKeyChanged into the saved file', () async {
    final (c, file, dir) = await _openOnDisk();
    expect(c.database!.meta.masterKeyChanged, isNull,
        reason: 'the fixture predates the field',);

    final before = DateTime.now().toUtc();
    expect(
      await c.changeMasterPassword(
          currentPassword: testVaultPassword, newPassword: _newPassword,),
      ChangePasswordResult.ok,
    );
    final after = DateTime.now().toUtc();

    // Stamped in memory and persisted — a fresh reopen sees it.
    final stamp = c.database!.meta.masterKeyChanged;
    expect(stamp, isNotNull);
    expect(stamp!.isUtc, isTrue);
    expect(stamp.isBefore(before), isFalse);
    expect(stamp.isAfter(after), isFalse);

    final reopened = await _reopen(file, _newPassword);
    expect(reopened.database!.meta.masterKeyChanged, stamp);

    await dir.delete(recursive: true);
  });

  test('a refused change leaves MasterKeyChanged alone', () async {
    final (c, file, dir) = await _openOnDisk();

    // Give the vault an existing stamp, persisted, so we can see it survive.
    final original = DateTime.utc(2020, 1, 2, 3, 4, 5);
    c.database!.meta.masterKeyChanged = original;
    await c.save();
    expect(c.error, isNull);

    // Wrong current password: refused before anything is touched.
    expect(
      await c.changeMasterPassword(
          currentPassword: 'nope', newPassword: _newPassword,),
      ChangePasswordResult.wrongCurrentPassword,
    );
    expect(c.database!.meta.masterKeyChanged, original);

    // Failed write: the stamp rolls back with the credential.
    c.path = '${dir.path}/no/such/dir/vault.kdbx';
    expect(
      await c.changeMasterPassword(
          currentPassword: testVaultPassword, newPassword: _newPassword,),
      ChangePasswordResult.saveFailed,
    );
    expect(c.database!.meta.masterKeyChanged, original,
        reason: 'the file is still under the old password; the stamp must '
            'not claim the key changed',);

    final reopened = await _reopen(file, testVaultPassword);
    expect(reopened.database!.meta.masterKeyChanged, original);

    await dir.delete(recursive: true);
  });

  test('wrong current password → refused, file untouched', () async {
    final (c, file, dir) = await _openOnDisk();
    final before = await file.readAsBytes();

    final result = await c.changeMasterPassword(
      currentPassword: 'not the password',
      newPassword: _newPassword,
    );

    expect(result, ChangePasswordResult.wrongCurrentPassword);
    expect(await file.readAsBytes(), before, reason: 'no rewrite at all');
    expect(await _opensWith(file, testVaultPassword), isTrue);
    expect(await _opensWith(file, _newPassword), isFalse);

    await dir.delete(recursive: true);
  });

  test('empty new password is refused', () async {
    final (c, file, dir) = await _openOnDisk();
    final before = await file.readAsBytes();

    expect(
      await c.changeMasterPassword(
          currentPassword: testVaultPassword, newPassword: '',),
      ChangePasswordResult.emptyNewPassword,
    );
    expect(await file.readAsBytes(), before);

    await dir.delete(recursive: true);
  });

  test('pathless vault → refused (nowhere to persist the new password)',
      () async {
    final c = VaultController();
    c.loadBytes(await buildTestVaultBytes(), name: 'ro.kdbx'); // no path
    await c.unlock(testVaultPassword);

    expect(
      await c.changeMasterPassword(
          currentPassword: testVaultPassword, newPassword: _newPassword,),
      ChangePasswordResult.noWritableLocation,
    );
  });

  test('locked vault → refused', () async {
    final c = VaultController();
    c.loadBytes(await buildTestVaultBytes(), name: 'ro.kdbx');
    expect(c.status, VaultStatus.locked);

    expect(
      await c.changeMasterPassword(
          currentPassword: testVaultPassword, newPassword: _newPassword,),
      ChangePasswordResult.notUnlocked,
    );
  });

  test('failed write → rolls back to the old password, not a half-change',
      () async {
    final (c, file, dir) = await _openOnDisk();
    final before = await file.readAsBytes();

    // Point the controller at an unwritable location (missing parent dir) so
    // the re-encrypted bytes can't land.
    c.path = '${dir.path}/no/such/dir/vault.kdbx';

    final result = await c.changeMasterPassword(
      currentPassword: testVaultPassword,
      newPassword: _newPassword,
    );

    expect(result, ChangePasswordResult.saveFailed);
    expect(c.error, isNotNull, reason: 'the write failure is surfaced');
    expect(await file.readAsBytes(), before, reason: 'original file untouched');

    // The in-memory credential rolled back: saving to a good path again writes
    // under the OLD password, matching what is already on disk.
    c.path = file.path;
    await c.save();
    expect(c.error, isNull);
    expect(await _opensWith(file, testVaultPassword), isTrue);
    expect(await _opensWith(file, _newPassword), isFalse);

    // And the old password is still accepted for a subsequent real re-key.
    expect(
      await c.changeMasterPassword(
          currentPassword: testVaultPassword, newPassword: _newPassword,),
      ChangePasswordResult.ok,
    );
    expect(await _opensWith(file, _newPassword), isTrue);

    await dir.delete(recursive: true);
  });
}
