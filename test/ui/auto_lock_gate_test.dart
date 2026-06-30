// AutoLockGate re-locks the vault when the app returns from the background
// after the focus timeout. Clock is injected so the test is deterministic.

import 'package:dgvault/ui/state/vault_controller.dart';
import 'package:dgvault/ui/widgets/auto_lock_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_vault.dart';

Future<VaultController> _unlocked() async {
  final c = VaultController();
  c.loadBytes(await buildTestVaultBytes(), name: 'test.kdbx');
  await c.unlock(testVaultPassword);
  return c;
}

void main() {
  testWidgets('locks on refocus after the focus timeout', (tester) async {
    final c = await _unlocked();
    c.focusLockMinutes = 1;
    expect(c.isUnlocked, isTrue);

    var now = DateTime.utc(2026, 1, 1, 12);
    await tester.pumpWidget(MaterialApp(
      home: AutoLockGate(
        controller: c,
        now: () => now,
        child: const SizedBox.shrink(),
      ),
    ),);

    // Leave the foreground, stay away 2 minutes, then return.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    now = now.add(const Duration(minutes: 2));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(c.status, VaultStatus.locked);
  });

  testWidgets('does NOT lock on a brief switch-away', (tester) async {
    final c = await _unlocked();
    c.focusLockMinutes = 5;

    var now = DateTime.utc(2026, 1, 1, 12);
    await tester.pumpWidget(MaterialApp(
      home: AutoLockGate(
        controller: c,
        now: () => now,
        child: const SizedBox.shrink(),
      ),
    ),);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    now = now.add(const Duration(seconds: 30)); // back well within 5 min
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(c.status, VaultStatus.unlocked);
  });
}
