// The unlock flow is real (Argon2 KeyVault → KDBX decrypt), so this exercises
// the engine through the UI controller.

import 'package:dgvault/ui/state/vault_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bootstrap → locked; correct PIN unlocks and decrypts the vault', () async {
    final c = VaultController();
    await c.bootstrap();
    expect(c.status, VaultStatus.locked);

    await c.attempt(VaultController.demoPin);
    expect(c.status, VaultStatus.unlocked);
    expect(c.database, isNotNull);
    expect(c.entryCount, greaterThan(0));

    // The real search engine filters the decrypted entries.
    final hits = c.search('github');
    expect(hits, isNotEmpty);
    expect(hits.first.title, 'GitHub');
    expect(c.search('').length, c.entryCount);
  });

  test('wrong PIN is denied and decrements the attempt budget', () async {
    final c = VaultController();
    await c.bootstrap();

    await c.attempt('0000');
    expect(c.status, VaultStatus.locked);
    expect(c.database, isNull);
    expect(c.error, contains('ACCESS DENIED'));
    expect(c.remainingAttempts, 4);

    // Recover with the right PIN; counter resets.
    await c.attempt(VaultController.demoPin);
    expect(c.status, VaultStatus.unlocked);
    expect(c.remainingAttempts, 5);
  });

  test('lock returns to the locked state and drops the database', () async {
    final c = VaultController();
    await c.bootstrap();
    await c.attempt(VaultController.demoPin);
    expect(c.status, VaultStatus.unlocked);

    c.lock();
    expect(c.status, VaultStatus.locked);
    expect(c.database, isNull);
  });
}
