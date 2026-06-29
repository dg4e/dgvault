// Widget smoke tests for the terminal UI shell.

import 'package:dgvault/ui/app.dart';
import 'package:dgvault/ui/state/vault_controller.dart';
import 'package:flutter/services.dart';
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
}
