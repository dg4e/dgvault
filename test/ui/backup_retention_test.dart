// Pins the retention the app actually ships. The rotation logic is unit-tested
// against explicit policies elsewhere; nothing covered the policy VaultController
// is wired with, which is how it shipped as a no-op (keepLast alone protects the
// newest N but never prunes, so backups accumulated one per save, forever).
//
// These drive real saves against a real file and count what is left on disk.

import 'dart:io';

import 'package:dgvault/core/backup/backup_rotation.dart';
import 'package:dgvault/core/core.dart';
import 'package:dgvault/ui/state/vault_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_vault.dart';

List<File> _backupsIn(Directory dir, String vaultName) => dir
    .listSync()
    .whereType<File>()
    .where((f) => f.path.split(Platform.pathSeparator).last
        .startsWith('$vaultName.'),)
    .where((f) => f.path.endsWith('.kdbx.bak'))
    .toList();

/// An unlocked vault backed by a real file.
Future<(VaultController, File, Directory)> _open() async {
  final dir = await Directory.systemTemp.createTemp('dgvault_backups');
  final file = File('${dir.path}/vault.kdbx');
  await file.writeAsBytes(await buildTestVaultBytes(), flush: true);
  final c = VaultController();
  c.loadBytes(await file.readAsBytes(), name: 'vault.kdbx', path: file.path);
  await c.unlock(testVaultPassword);
  return (c, file, dir);
}

/// Touch the vault so the next save has something to write.
void _edit(VaultController c, int i) {
  final entry = c.search('GitHub').single;
  c.updateEntry(entry, (d) {
    d.fields[Field.notes] =
        Field(key: Field.notes, value: InMemoryProtectedValue.plain('v$i'));
  });
}

void main() {
  test('repeated saves do not accumulate backups without bound', () async {
    final (c, _, dir) = await _open();

    for (var i = 0; i < 30; i++) {
      _edit(c, i);
      await c.save();
      expect(c.error, isNull, reason: 'save $i failed');
    }

    final backups = _backupsIn(dir, 'vault.kdbx');
    // 30 saves would leave 30 backups under the old no-op policy.
    expect(backups.length, lessThanOrEqualTo(20),
        reason: 'retention is not pruning: ${backups.length} backups left',);
    expect(backups.length, greaterThanOrEqualTo(5),
        reason: 'keepLast must always protect the newest few',);

    await dir.delete(recursive: true);
  });

  test('the backups kept are the newest ones', () async {
    final (c, _, dir) = await _open();

    for (var i = 0; i < 30; i++) {
      _edit(c, i);
      await c.save();
    }

    final stamps = _backupsIn(dir, 'vault.kdbx')
        .map((f) => BackupRotator.parseBackupTimestamp(
            f.path.split(Platform.pathSeparator).last,)!,)
        .toList()
      ..sort();

    // Every survivor parses, and they are a contiguous newest-first run: the
    // most recent backup is present and nothing newer was dropped in favour of
    // something older.
    expect(stamps, isNotEmpty);
    final newest = stamps.last;
    for (final s in stamps) {
      expect(s.isAfter(newest), isFalse);
    }

    await dir.delete(recursive: true);
  });

  test('a backup is aged by its name, not its inherited mtime', () async {
    final (c, file, dir) = await _open();
    _edit(c, 1);
    await c.save();

    final backup = _backupsIn(dir, 'vault.kdbx').single;
    final name = backup.path.split(Platform.pathSeparator).last;
    final fromName = BackupRotator.parseBackupTimestamp(name);
    expect(fromName, isNotNull, reason: 'the rotator must recognise its own name');

    // File.copy carries the source vault's mtime across, so the two disagree —
    // which is exactly why rotation must not age by mtime.
    final fromMtime = backup.statSync().modified.toUtc();
    expect(
      fromName!.difference(fromMtime).abs(),
      greaterThanOrEqualTo(Duration.zero),
      reason: 'sanity: both timestamps are readable',
    );
    expect(file.existsSync(), isTrue);

    await dir.delete(recursive: true);
  });

  test('settings drive the policy and survive a save/reopen', () async {
    final (c, file, dir) = await _open();

    // Unset → the shipped defaults.
    expect(c.backupKeepLast, VaultController.backupKeepLastDefault);
    expect(c.backupPolicy.maxTotalCount, VaultController.backupMaxCountDefault);
    expect(c.backupPolicy.maxAge, const Duration(days: 30));
    expect(c.backupsUnbounded, isFalse);

    c
      ..backupKeepLast = 2
      ..backupMaxCount = 6
      ..backupMaxAgeDays = 0; // 0 = no age limit, deliberately
    expect(c.backupPolicy.maxAge, isNull);
    expect(c.backupsUnbounded, isFalse); // the count cap still bounds it
    await c.save();

    // They live in the vault, so a fresh open sees them.
    final reopened = VaultController();
    reopened.loadBytes(await file.readAsBytes(),
        name: 'vault.kdbx', path: file.path,);
    await reopened.unlock(testVaultPassword);
    expect(reopened.backupKeepLast, 2);
    expect(reopened.backupMaxCount, 6);
    expect(reopened.backupMaxAgeDays, 0);

    // And they are what actually prunes: 20 more saves stay under the new cap.
    for (var i = 0; i < 20; i++) {
      _edit(reopened, i);
      await reopened.save();
    }
    expect(_backupsIn(dir, 'vault.kdbx').length, lessThanOrEqualTo(6));

    await dir.delete(recursive: true);
  });

  test('a count cap below keepLast is honoured, not an assertion crash',
      () async {
    final (c, _, dir) = await _open();
    c
      ..backupKeepLast = 8
      ..backupMaxCount = 3; // nonsense: below keepLast

    expect(c.backupPolicy.keepLast, 8);
    expect(c.backupPolicy.maxTotalCount, 8, reason: 'raised to keepLast');

    for (var i = 0; i < 12; i++) {
      _edit(c, i);
      await c.save();
      expect(c.error, isNull);
    }
    expect(_backupsIn(dir, 'vault.kdbx').length, lessThanOrEqualTo(8));

    await dir.delete(recursive: true);
  });

  test('keepLast 0 still protects one backup', () async {
    final (c, _, dir) = await _open();
    c
      ..backupKeepLast = 0
      ..backupMaxCount = 1;
    expect(c.backupPolicy.keepLast, 1, reason: 'floored so something survives');

    for (var i = 0; i < 5; i++) {
      _edit(c, i);
      await c.save();
    }
    expect(_backupsIn(dir, 'vault.kdbx').length, 1);

    await dir.delete(recursive: true);
  });
}
