// Widget smoke tests for the terminal UI shell.

import 'package:dgvault/ui/app.dart';
import 'package:dgvault/ui/state/vault_controller.dart';
import 'package:dgvault/ui/theme/terminal_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui/test_vault.dart';

Future<VaultController> _unlocked(WidgetTester tester) async {
  final c = VaultController();
  c.loadBytes(await buildTestVaultBytes(), name: 'test.kdbx');
  await c.unlock(testVaultPassword);
  await tester.pumpWidget(DgvaultApp(controller: c));
  await tester.pumpAndSettle();
  return c;
}

Future<void> _ctrl(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

bool _searchHasFocus(WidgetTester tester) =>
    tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus;

void main() {
  testWidgets('landing shows open/new when no vault is loaded', (tester) async {
    await tester.pumpWidget(DgvaultApp(controller: VaultController()));
    await tester.pump();
    expect(find.text('[ OPEN .KDBX ]'), findsOneWidget);
    expect(find.text('[ NEW VAULT ]'), findsOneWidget);
  });

  testWidgets('a loaded file shows the unlock prompt', (tester) async {
    final c = VaultController();
    c.loadBytes(await buildTestVaultBytes(), name: 'test.kdbx');
    await tester.pumpWidget(DgvaultApp(controller: c));
    await tester.pump();

    expect(find.text('test.kdbx'), findsOneWidget); // filename shown
    expect(find.text('[ UNLOCK ]'), findsOneWidget);
  });

  testWidgets('unlocked state renders the vault with entries', (tester) async {
    await _unlocked(tester);
    // 'GitHub' shows in the list and (two-pane) the detail header.
    expect(find.text('GitHub'), findsWidgets);
    expect(find.text('UNLOCKED'), findsOneWidget); // status bar mode
  });

  testWidgets('^L (Ctrl+L) locks the vault', (tester) async {
    final c = await _unlocked(tester);
    expect(c.status, VaultStatus.unlocked);

    await _ctrl(tester, LogicalKeyboardKey.keyL);

    expect(c.status, VaultStatus.locked);
    expect(find.text('[ UNLOCK ]'), findsOneWidget);
  });

  testWidgets('^G (Ctrl+G) opens the password generator', (tester) async {
    await _unlocked(tester);
    expect(find.text('// PASSWORD GENERATOR'), findsNothing);

    await _ctrl(tester, LogicalKeyboardKey.keyG);

    expect(find.text('// PASSWORD GENERATOR'), findsOneWidget);
  });

  testWidgets('/ focuses the search field', (tester) async {
    await _unlocked(tester);
    expect(_searchHasFocus(tester), isFalse);

    await _key(tester, LogicalKeyboardKey.slash);

    expect(_searchHasFocus(tester), isTrue);
  });

  testWidgets('Esc clears an active search, then locks', (tester) async {
    final c = await _unlocked(tester);

    await tester.enterText(find.byType(EditableText), 'github');
    await tester.pumpAndSettle();
    expect(find.text('Proton Mail'), findsNothing); // filtered out

    await _key(tester, LogicalKeyboardKey.escape); // first esc clears search
    expect(find.text('Proton Mail'), findsWidgets);
    expect(c.status, VaultStatus.unlocked);

    await _key(tester, LogicalKeyboardKey.escape); // second esc locks
    expect(c.status, VaultStatus.locked);
  });

  testWidgets('arrow down moves the selection to the next entry', (tester) async {
    await _unlocked(tester);
    // Default selection is the first entry → its URL shows in the detail pane.
    expect(find.text('https://github.com'), findsOneWidget);

    await _key(tester, LogicalKeyboardKey.arrowDown);

    expect(find.text('https://github.com'), findsNothing);
    expect(find.text('https://proton.me'), findsOneWidget);
  });

  testWidgets('folder rows do not resize on hover', (tester) async {
    await _unlocked(tester);
    // 'Work' sits below 'Personal' in the tree; if hovering 'Personal' grew its
    // row, 'Work' would shift down.
    final before = tester.getTopLeft(find.text('Work')).dy;

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(() => mouse.removePointer());
    await mouse.moveTo(tester.getCenter(find.text('Personal')));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.more_vert), findsWidgets); // hover revealed actions
    expect(tester.getTopLeft(find.text('Work')).dy, before); // unchanged
  });

  testWidgets('entry rows do not resize on hover when reorderable',
      (tester) async {
    await _unlocked(tester);
    // Select a folder so its entries become drag-reorderable (manual sort).
    await tester.tap(find.text('Personal'));
    await tester.pumpAndSettle();

    // 'Proton Mail' sits below 'GitHub' in Personal; hovering GitHub must not
    // grow its row and push Proton Mail down.
    final before = tester.getTopLeft(find.text('Proton Mail')).dy;
    final ghInList = find.descendant(
        of: find.byType(ReorderableListView), matching: find.text('GitHub'),);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(() => mouse.removePointer());
    await mouse.moveTo(tester.getCenter(ghInList));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.drag_indicator), findsWidgets); // handle on hover
    expect(tester.getTopLeft(find.text('Proton Mail')).dy, before); // unchanged
  });

  testWidgets('move-to relocates the selected entry via the folder picker',
      (tester) async {
    final c = await _unlocked(tester);
    final gh = c.search('GitHub').first;
    expect(c.findGroupOf(gh)!.name, 'Personal');

    // GitHub is auto-selected in the wide detail pane → its Move action shows.
    await tester.tap(find.byTooltip('Move to folder'));
    await tester.pumpAndSettle();
    expect(find.text('// MOVE ENTRY TO'), findsOneWidget);

    // Choose 'Work' from the picker dialog (disambiguate from the sidebar).
    await tester.tap(find.descendant(
        of: find.byType(Dialog), matching: find.text('Work'),),);
    await tester.pumpAndSettle();

    expect(c.findGroupOf(gh)!.name, 'Work');
  });

  testWidgets('folder tree shows groups; Recycle Bin excluded from default view',
      (tester) async {
    await _unlocked(tester);

    // Folder sidebar lists the groups (wide/two-pane test surface).
    expect(find.text('Personal'), findsOneWidget);
    expect(find.text('Work'), findsOneWidget);
    expect(find.text('Recycle Bin'), findsOneWidget);

    // Default (All) view shows live entries but NOT the trashed one.
    expect(find.text('GitHub'), findsWidgets);
    expect(find.text('Jira'), findsWidgets);
    expect(find.text('Deleted Thing'), findsNothing);

    // Selecting the Recycle Bin folder reveals the trashed entry.
    await tester.tap(find.text('Recycle Bin'));
    await tester.pumpAndSettle();
    expect(find.text('Deleted Thing'), findsWidgets);
    expect(find.text('GitHub'), findsNothing);
  });

  testWidgets('interactive controls expose hover tooltips', (tester) async {
    await _unlocked(tester);

    // header buttons (platform-correct shortcut in the message)
    expect(find.byTooltip('Generate a password (${hotkey('G')})'), findsOneWidget);
    expect(find.byTooltip('Lock the vault (${hotkey('L')})'), findsOneWidget);

    // entry row (multi-line: title / user / url)
    expect(
        find.byTooltip('open GitHub\nuser: realytcracker\nhttps://github.com'),
        findsOneWidget,);

    // detail field actions (GitHub selected by default in two-pane)
    expect(find.byTooltip('Copy username'), findsOneWidget);
    expect(find.byTooltip('Reveal password'), findsOneWidget);
    expect(find.byTooltip('Copy password'), findsWidgets);

    // tag chips
    expect(find.byTooltip('tag: dev'), findsWidgets);
  });

  testWidgets('Ctrl+C copies the selected entry password', (tester) async {
    // Mock the platform clipboard channel so Clipboard.setData succeeds.
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
    await _unlocked(tester);

    await _ctrl(tester, LogicalKeyboardKey.keyC);
    await tester.pump(); // let the snackbar appear

    expect(find.textContaining('copied password'), findsOneWidget);
  });
}
