// Smoke test for the host shell entrypoint.

import 'package:dgvault/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app shell renders', (tester) async {
    await tester.pumpWidget(const DgvaultApp());
    expect(find.text('dgvault'), findsOneWidget);
  });
}
