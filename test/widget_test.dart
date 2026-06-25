// Widget smoke tests for the terminal UI shell.

import 'package:dgvault/ui/app.dart';
import 'package:dgvault/ui/state/vault_controller.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
