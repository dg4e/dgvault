// The re-key as the user drives it: menu → settings → change password → type,
// and the file on disk really is re-encrypted. Also covers the dialog's own
// validation, since a rejected attempt must keep the dialog open.
//
// Driven at phone width on purpose: the wide two-pane layout renders
// _EmptyDetail, whose BlinkingCursor repeats forever, so pumpAndSettle would
// never settle there.

import 'dart:io';
import 'dart:typed_data';

import 'package:dgvault/ui/app.dart';
import 'package:dgvault/ui/app_info.dart';
import 'package:dgvault/ui/state/vault_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'test_vault.dart';

const _newPassword = 'a whole new password';

/// TerminalPanel renders its title as `┤ title ├`.
const _dialogTitle = '┤ change master password ├';

/// Pump the app with a vault unlocked from a real file. A path is required —
/// a re-key has to be persistable to be allowed at all.
Future<(VaultController, File, Directory)> _pumpUnlocked(
    WidgetTester tester,) async {
  tester.view.physicalSize = const Size(390, 844); // phone, < wide breakpoint
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  late final Directory dir;
  late final File file;
  late final VaultController c;
  // Real dart:io never completes inside the fake-async test zone, so every
  // filesystem touch in this file goes through runAsync.
  await tester.runAsync(() async {
    dir = await Directory.systemTemp.createTemp('dgvault_rekey_ui');
    file = File('${dir.path}/vault.kdbx');
    await file.writeAsBytes(await buildTestVaultBytes(), flush: true);
    c = VaultController();
    c.loadBytes(await file.readAsBytes(), name: 'vault.kdbx', path: file.path);
    await c.unlock(testVaultPassword);
  });
  expect(c.status, VaultStatus.unlocked);

  await tester.pumpWidget(DgvaultApp(controller: c));
  await tester.pumpAndSettle();
  return (c, file, dir);
}

/// Let real file I/O finish. The re-key writes the vault with dart:io, which
/// the fake-async test zone won't drive on its own.
Future<void> _flushIo(WidgetTester tester) async {
  // pumpAndSettle can't be used while the button is busy: its spinner animates
  // forever, so "no frames scheduled" never arrives. Drive the real loop until
  // the spinner clears instead.
  for (var i = 0; i < 40; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),);
    await tester.pump(const Duration(milliseconds: 25));
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      await tester.pumpAndSettle();
      return;
    }
  }
  fail('the re-key never finished (the busy spinner is still up)');
}

/// Open the settings sheet from the overflow menu and open the re-key dialog.
Future<void> _openChangePasswordDialog(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Menu'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Settings'));
  await tester.pumpAndSettle();

  // The sheet scrolls; ensureVisible walks to its own Scrollable ancestor
  // (find.byType(Scrollable).last would grab the search field's internal one).
  await tester.ensureVisible(find.text('[ CHANGE PASSWORD ]'));
  await tester.pumpAndSettle();

  await tester.tap(find.text('[ CHANGE PASSWORD ]'));
  await tester.pumpAndSettle();
  expect(find.text(_dialogTitle), findsOneWidget);
}

/// Fill the dialog's three fields, in order.
Future<void> _fill(
    WidgetTester tester, String current, String fresh, String confirm,) async {
  final fields = find.descendant(
    of: find.byType(Dialog),
    matching: find.byType(EditableText),
  );
  expect(fields, findsNWidgets(3));
  await tester.enterText(fields.at(0), current);
  await tester.enterText(fields.at(1), fresh);
  await tester.enterText(fields.at(2), confirm);
  await tester.pumpAndSettle();
}

Future<bool> _opensWith(File file, String password) async {
  final c = VaultController();
  c.loadBytes(await file.readAsBytes(), name: 'vault.kdbx', path: file.path);
  await c.unlock(password);
  return c.status == VaultStatus.unlocked;
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

  testWidgets('settings → change password re-encrypts the file',
      (tester) async {
    final (_, file, dir) = await _pumpUnlocked(tester);

    await _openChangePasswordDialog(tester);
    await _fill(tester, testVaultPassword, _newPassword, _newPassword);
    await tester.tap(find.text('[ CHANGE ]'));
    await tester.pump(); // kick off the async re-key (button goes busy)
    await _flushIo(tester);

    // Dialog closed, the sheet confirms, and the file really is re-keyed.
    expect(find.text(_dialogTitle), findsNothing);
    expect(find.textContaining('changed'), findsOneWidget);

    late final bool opensNew, opensOld;
    await tester.runAsync(() async {
      opensNew = await _opensWith(file, _newPassword);
      opensOld = await _opensWith(file, testVaultPassword);
    });
    expect(opensNew, isTrue);
    expect(opensOld, isFalse);

    await tester.runAsync(() => dir.delete(recursive: true));
  });

  testWidgets('wrong current password keeps the dialog open with an error',
      (tester) async {
    final (_, file, dir) = await _pumpUnlocked(tester);

    await _openChangePasswordDialog(tester);
    await _fill(tester, 'wrong', _newPassword, _newPassword);
    await tester.tap(find.text('[ CHANGE ]'));
    await tester.pump();
    await _flushIo(tester);

    expect(find.text(_dialogTitle), findsOneWidget,
        reason: 'the dialog must not close on a rejected attempt',);
    expect(find.textContaining('current password is wrong'), findsOneWidget);

    late final bool opensOld;
    await tester.runAsync(() async {
      opensOld = await _opensWith(file, testVaultPassword);
    });
    expect(opensOld, isTrue);

    await tester.runAsync(() => dir.delete(recursive: true));
  });

  testWidgets('mismatched confirmation is refused before any write',
      (tester) async {
    final (_, file, dir) = await _pumpUnlocked(tester);
    late final Uint8List before;
    await tester.runAsync(() async => before = await file.readAsBytes());

    await _openChangePasswordDialog(tester);
    await _fill(tester, testVaultPassword, _newPassword, 'something else');
    await tester.tap(find.text('[ CHANGE ]'));
    await tester.pump();
    await _flushIo(tester);

    expect(find.textContaining('do not match'), findsOneWidget);
    late final Uint8List after;
    await tester.runAsync(() async => after = await file.readAsBytes());
    expect(after, before, reason: 'nothing was written');

    await tester.runAsync(() => dir.delete(recursive: true));
  });

  testWidgets('cancel leaves the password alone', (tester) async {
    final (_, file, dir) = await _pumpUnlocked(tester);

    await _openChangePasswordDialog(tester);
    await _fill(tester, testVaultPassword, _newPassword, _newPassword);
    await tester.tap(find.text('[ CANCEL ]'));
    await tester.pumpAndSettle();

    expect(find.text(_dialogTitle), findsNothing);

    late final bool opensOld, opensNew;
    await tester.runAsync(() async {
      opensOld = await _opensWith(file, testVaultPassword);
      opensNew = await _opensWith(file, _newPassword);
    });
    expect(opensOld, isTrue);
    expect(opensNew, isFalse);

    await tester.runAsync(() => dir.delete(recursive: true));
  });
}
