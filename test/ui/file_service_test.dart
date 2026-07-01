// Pure managed-vault path helpers (no path_provider): safe names + collision
// handling. The path_provider-backed methods are exercised on-device.

import 'dart:io';

import 'package:dgvault/ui/state/file_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sanitizeVaultName strips extension/unsafe chars, never empty', () {
    expect(VaultFiles.sanitizeVaultName('Personal'), 'Personal');
    expect(VaultFiles.sanitizeVaultName('work.kdbx'), 'work');
    expect(VaultFiles.sanitizeVaultName('a/b:c*?'), 'a_b_c__');
    expect(VaultFiles.sanitizeVaultName('   '), 'vault');
    expect(VaultFiles.sanitizeVaultName('///'), '___'); // unsafe chars → _
  });

  test('uniqueVaultPath avoids clobbering existing files', () async {
    final dir = await Directory.systemTemp.createTemp('dgvault_vaults');
    addTearDown(() => dir.delete(recursive: true));

    final p1 = VaultFiles.uniqueVaultPath(dir, 'my vault');
    expect(p1, '${dir.path}/my vault.kdbx');
    File(p1).writeAsBytesSync([0]);

    final p2 = VaultFiles.uniqueVaultPath(dir, 'my vault');
    expect(p2, '${dir.path}/my vault (1).kdbx');
    File(p2).writeAsBytesSync([0]);

    final p3 = VaultFiles.uniqueVaultPath(dir, 'my vault');
    expect(p3, '${dir.path}/my vault (2).kdbx');
  });
}
