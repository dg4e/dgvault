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

/// The narrowest phone still worth supporting (iPhone SE 1st gen). Long button
/// labels overflowed here until TermButton was made to ellipsize.
const _tinyPhone = Size(320, 568);

/// Phone: below the wide breakpoint, so the header collapses to an overflow
/// menu and the detail pane is not built.
const _phone = Size(390, 844);

/// Desktop: above the wide breakpoint, so the two-pane layout renders.
const _desktop = Size(1280, 900);

/// Pump the app with a vault unlocked. No file is needed: these tests never
/// save, so the vault can stay pathless.
Future<VaultController> _pumpUnlocked(WidgetTester tester,
    {Size size = _phone,}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final c = VaultController();
  c.loadBytes(await buildTestVaultBytes(), name: 'test.kdbx');
  await c.unlock(testVaultPassword);
  await tester.pumpWidget(DgvaultApp(controller: c));
  await _settle(tester);
  return c;
}

/// pumpAndSettle is unusable in the wide layout: _EmptyDetail carries a
/// BlinkingCursor that repeats forever, so "no frames scheduled" never arrives.
/// Bounded pumps work at both widths.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Open the settings sheet, via the overflow menu on a phone and the header
/// button on a desktop.
Future<void> _openSettings(WidgetTester tester, {required bool wide}) async {
  if (wide) {
    await tester.tap(find.byTooltip('Vault settings'));
  } else {
    await tester.tap(find.byTooltip('Menu'));
    await _settle(tester);
    await tester.tap(find.text('Settings'));
  }
  await _settle(tester);
  expect(find.text('// VAULT SETTINGS'), findsOneWidget);
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
    await _openSettings(tester, wide: false);

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

  // A RenderFlex overflow throws, so simply walking the sheet at each width
  // fails the test if anything is too wide for its row.
  for (final (label, size) in [
    ('a 320pt phone', _tinyPhone),
    ('phone', _phone),
    ('desktop', _desktop),
  ]) {
    testWidgets('backup settings render cleanly on $label', (tester) async {
      final c = await _pumpUnlocked(tester, size: size);
      await _openSettings(tester, wide: size.width >= 760);

      await tester.ensureVisible(find.text('// BACKUPS'));
      await _settle(tester);

      // The three fields are present, seeded from the vault's settings.
      for (final field in ['// KEEP NEWEST', '// MAX TOTAL', '// MAX AGE (DAYS)']) {
        expect(find.text(field), findsOneWidget, reason: '$field on $label');
      }
      expect(c.backupKeepLast, VaultController.backupKeepLastDefault);
      expect(c.backupMaxCount, VaultController.backupMaxCountDefault);
      expect(c.backupMaxAgeDays, VaultController.backupMaxAgeDaysDefault);

      // Defaults are bounded, so no warning yet.
      expect(find.textContaining('both limits are off'), findsNothing);
    });

    testWidgets('turning both limits off warns, without overflow on $label',
        (tester) async {
      final c = await _pumpUnlocked(tester, size: size);
      await _openSettings(tester, wide: size.width >= 760);

      await tester.ensureVisible(find.text('// MAX TOTAL'));
      await _settle(tester);

      Finder fieldUnder(String label) => find.descendant(
            of: find.ancestor(
                of: find.text(label), matching: find.byType(Column),).first,
            matching: find.byType(EditableText),
          );

      await tester.enterText(fieldUnder('// MAX TOTAL'), '0');
      await _settle(tester);
      await tester.enterText(fieldUnder('// MAX AGE (DAYS)'), '0');
      await _settle(tester);

      expect(c.backupMaxCount, 0);
      expect(c.backupMaxAgeDays, 0);
      expect(c.backupsUnbounded, isTrue);
      expect(find.textContaining('both limits are off'), findsOneWidget,
          reason: 'the unbounded warning must appear on $label',);
    });
  }
}
