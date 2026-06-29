// Widget-level coverage for the entry editor + detail (edit / add / history /
// delete UI) on top of the real VaultController.

import 'package:dgvault/core/core.dart';
import 'package:dgvault/ui/screens/entry_detail.dart';
import 'package:dgvault/ui/screens/entry_editor.dart';
import 'package:dgvault/ui/state/vault_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_vault.dart';

Future<VaultController> _open() async {
  final c = VaultController();
  c.loadBytes(await buildTestVaultBytes(), name: 'test.kdbx');
  await c.unlock(testVaultPassword);
  return c;
}

Entry _find(VaultController c, String title) =>
    c.search(title).firstWhere((e) => e.title == title);

void main() {
  testWidgets('editor creates a new entry in the chosen group', (tester) async {
    final c = await _open();
    final personal =
        c.rootGroup!.groups.firstWhere((g) => g.name == 'Personal');
    final before = personal.entries.length;

    await tester.pumpWidget(MaterialApp(
      home: EntryEditor(controller: c, group: personal),
    ));

    await tester.enterText(find.byType(TextField).first, 'New Login');
    await tester.tap(find.text('[ SAVE ]'));
    await tester.pumpAndSettle();

    expect(personal.entries.length, before + 1);
    expect(personal.entries.any((e) => e.title == 'New Login'), isTrue);
    expect(c.isDirty, isTrue);
  });

  testWidgets('editor edits an existing entry and snapshots history',
      (tester) async {
    final c = await _open();
    final gh = _find(c, 'GitHub');

    await tester.pumpWidget(MaterialApp(
      home: EntryEditor(controller: c, entry: gh),
    ));

    final titleField = find.byType(TextField).first;
    await tester.enterText(titleField, 'GitHub Renamed');
    await tester.tap(find.text('[ SAVE ]'));
    await tester.pumpAndSettle();

    expect(gh.title, 'GitHub Renamed');
    expect(gh.history.last.title, 'GitHub'); // prior version captured
  });

  testWidgets('detail view shows a history section after an edit',
      (tester) async {
    final c = await _open();
    final gh = _find(c, 'GitHub');
    c.updateEntry(gh, (d) {
      d.fields[Field.title] =
          Field(key: Field.title, value: InMemoryProtectedValue.plain('GH2'));
    });

    var restored = -1;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: EntryDetailView(entry: gh, onRestore: (i) => restored = i),
      ),
    ));

    expect(find.text('// HISTORY (1)'), findsOneWidget);
    // Expand the version row, then restore it.
    await tester.tap(find.text('v0'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('[ RESTORE ]'));
    await tester.pumpAndSettle();
    expect(restored, 0);
  });
}
