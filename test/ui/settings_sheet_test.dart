// The vault settings sheet at phone width. Rows here grow after a tap (a
// confirmation appears next to the button), which is exactly when a fixed Row
// runs out of horizontal space — an overflow throws and fails these tests.

import 'package:dgvault/ui/app.dart';
import 'package:dgvault/ui/app_info.dart';
import 'package:dgvault/ui/state/vault_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'test_vault.dart';

/// Pump the app at phone width with a vault unlocked. No file is needed: these
/// tests never save, so the vault can stay pathless.
Future<VaultController> _pumpUnlocked(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844); // phone, < wide breakpoint
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final c = VaultController();
  c.loadBytes(await buildTestVaultBytes(), name: 'test.kdbx');
  await c.unlock(testVaultPassword);
  await tester.pumpWidget(DgvaultApp(controller: c));
  await tester.pumpAndSettle();
  return c;
}

Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Menu'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Settings'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    PackageInfo.setMockInitialValues(
      appName: 'dgvault',
      packageName: 'com.digitalgangster.dgvault',
      version: '0.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
    await loadAppInfo();
  });

  testWidgets('clearing recents shows its confirmation without overflowing',
      (tester) async {
    await _pumpUnlocked(tester);
    await _openSettings(tester);

    await tester.ensureVisible(find.text('[ CLEAR RECENTS ]'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('[ CLEAR RECENTS ]'));
    await tester.pump();
    // Clearing hits path_provider, which the fake-async test zone won't drive.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),);
    await tester.pumpAndSettle();

    expect(find.textContaining('cleared'), findsOneWidget);
  });
}
