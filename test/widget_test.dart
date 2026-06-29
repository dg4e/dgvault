// Widget smoke tests for the terminal UI shell.

import 'package:dgvault/ui/app.dart';
import 'package:dgvault/ui/state/vault_controller.dart';
import 'package:dgvault/ui/theme/terminal_theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Future<VaultController> _unlocked(WidgetTester tester) async {
  final c = VaultController();
  await c.bootstrap();
  await c.attempt(VaultController.demoPin);
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
  testWidgets('locked state shows the unlock prompt', (tester) async {
    final c = VaultController();
    await c.bootstrap();
    await tester.pumpWidget(DgvaultApp(controller: c));
    await tester.pump();

    expect(find.text('hint: demo pin is ${VaultController.demoPin}'), findsOneWidget);
    expect(find.text('[ UNLOCK ]'), findsOneWidget);
  });

  testWidgets('unlocked state renders the vault with entries', (tester) async {
    final c = VaultController();
    await c.bootstrap();
    await c.attempt(VaultController.demoPin);

    await tester.pumpWidget(DgvaultApp(controller: c));
    await tester.pump();

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
