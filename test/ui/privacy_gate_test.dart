// The privacy overlay covers the UI when the app backgrounds (so the app
// switcher / recents snapshot can't capture vault contents) and lifts on resume.

import 'package:dgvault/ui/widgets/privacy_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('covers on inactive/paused and uncovers on resume',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PrivacyGate(
          child: Text('SECRET-CONTENT', textDirection: TextDirection.ltr),
        ),
      ),
    );

    // Foreground: content visible, no curtain.
    expect(find.text('SECRET-CONTENT'), findsOneWidget);
    expect(find.text('dgvault'), findsNothing);

    // Background (the OS snapshots for the switcher around here).
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.text('dgvault'), findsOneWidget, reason: 'curtain must be up');

    // Resume: curtain lifts.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('dgvault'), findsNothing);
    expect(find.text('SECRET-CONTENT'), findsOneWidget);
  });

  testWidgets('paused and hidden also raise the curtain', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: PrivacyGate(child: SizedBox.shrink())),
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(find.text('dgvault'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('dgvault'), findsNothing);
  });
}
