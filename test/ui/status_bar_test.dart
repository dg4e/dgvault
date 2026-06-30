// A long folder name / filter in the status bar must ellipsize, not overflow
// on a narrow phone. (A RenderFlex overflow throws and fails the test.)

import 'package:dgvault/ui/widgets/terminal_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('long left items ellipsize without overflowing on a narrow bar',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: 320, // a narrow phone
              child: StatusBar(
                mode: 'UNLOCKED',
                left: [
                  '⌂ A Very Long Folder Name That Would Overflow The Status Bar',
                  '12/40 entries',
                ],
                right: [], // touch: keyboard hints hidden
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('UNLOCKED'), findsOneWidget);
    expect(find.textContaining('entries'), findsOneWidget);
  });

  testWidgets('desktop right hints still render alongside the left',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            child: StatusBar(
              mode: 'UNLOCKED',
              left: ['⌂ All', '3/3 entries'],
              right: ['/ find', 'esc'],
            ),
          ),
        ),
      ),
    );
    expect(find.text('/ find'), findsOneWidget);
    expect(find.text('esc'), findsOneWidget);
  });
}
