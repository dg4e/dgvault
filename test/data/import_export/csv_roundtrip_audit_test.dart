// Critic-owned adversarial round-trip audit for CSV import/export.
//
// Performer's round-trip test runs import→export→import and checks standard
// field *values*; that path cannot observe export-side loss because it starts
// from a CSV that never had custom fields/tags. These tests run the integrity-
// critical direction — a live Entry tree → export → import — and pin exactly
// what survives and what is silently dropped.
//
// Toolchain not installed here; assertions traced against implementation source
// by hand (see reviews/Critic-round-7.md).

import 'dart:math';

import 'package:dgvault/core/core.dart';
import 'package:dgvault/data/import_export/csv_import_export.dart';
import 'package:test/test.dart';

Field _f(String key, String value, {bool? protect}) => Field(
      key: key,
      value: (protect ?? key == Field.password)
          ? InMemoryProtectedValue(value)
          : InMemoryProtectedValue.plain(value),
    );

Group _rootWith(Entry e) => Group(uuid: 'r', name: 'Root', entries: [e]);

CsvImportResult _roundTrip(Group root) {
  final csv = const CsvExporter().export(root);
  return CsvImporter(random: Random(1)).import(csv);
}

void main() {
  group('standard fields survive a live-tree round-trip (incl. nasty chars)', () {
    test('comma, embedded quote+newline, and unicode are preserved', () {
      final e = Entry(uuid: 'e', fields: {
        Field.title: _f(Field.title, 'Acme, Inc.'),
        Field.userName: _f(Field.userName, 'bob@example.com'),
        Field.password: _f(Field.password, 'p"a\nss,1'),
        Field.notes: _f(Field.notes, 'héllo\nwörld — ☂'),
      });
      final imported = _roundTrip(_rootWith(e)).root.entries.single;
      expect(imported.fields[Field.title]!.value.reveal(), 'Acme, Inc.');
      expect(imported.fields[Field.userName]!.value.reveal(), 'bob@example.com');
      expect(imported.fields[Field.password]!.value.reveal(), 'p"a\nss,1');
      expect(imported.fields[Field.notes]!.value.reveal(), 'héllo\nwörld — ☂');
    });

    test('password field stays protected after import', () {
      final e = Entry(uuid: 'e', fields: {
        Field.title: _f(Field.title, 'X'),
        Field.password: _f(Field.password, 'secret'),
      });
      final imported = _roundTrip(_rootWith(e)).root.entries.single;
      expect(imported.fields[Field.password]!.isProtected, isTrue);
    });
  });

  group('group tree + TOTP survive the round-trip', () {
    test('nested group path is reconstructed', () {
      final root = Group(uuid: 'r', name: 'Root');
      final work = Group(uuid: 'w', name: 'Work');
      final email = Group(uuid: 'm', name: 'Email');
      work.groups.add(email);
      root.groups.add(work);
      email.entries.add(Entry(uuid: 'e', fields: {Field.title: _f(Field.title, 'Gmail')}));

      final result = _roundTrip(root);
      final w = result.root.groups.firstWhere((g) => g.name == 'Work');
      final m = w.groups.firstWhere((g) => g.name == 'Email');
      expect(m.entries.single.fields[Field.title]!.value.reveal(), 'Gmail');
    });

    test('TOTP seed round-trips', () {
      final e = Entry(uuid: 'e', fields: {
        Field.title: _f(Field.title, 'X'),
        kTotpFieldKey: _f(kTotpFieldKey, 'otpauth://totp/x?secret=ABC123', protect: true),
      });
      final imported = _roundTrip(_rootWith(e)).root.entries.single;
      expect(imported.fields[kTotpFieldKey]!.value.reveal(),
          'otpauth://totp/x?secret=ABC123');
    });
  });

  // ---- DATA-LOSS findings: these assert the CURRENT (lossy) behaviour so a fix
  // is a deliberate, visible change. Flagged REQUEST_CHANGES in the review. ----
  group('DATA LOSS — export drops non-column data', () {
    test('custom fields are NOT exported (silent loss)', () {
      final e = Entry(uuid: 'e', fields: {
        Field.title: _f(Field.title, 'Bank'),
        'Security Question': _f('Security Question', 'first pet', protect: false),
        'Recovery Code': _f('Recovery Code', 'ABCD-EFGH', protect: false),
      });
      final csv = const CsvExporter().export(_rootWith(e));
      expect(csv.contains('Security Question'), isFalse,
          reason: 'custom field header absent → value cannot survive export');
      final imported = CsvImporter(random: Random(1)).import(csv).root.entries.single;
      expect(imported.fields.containsKey('Security Question'), isFalse);
      expect(imported.fields.containsKey('Recovery Code'), isFalse);
    });

    test('tags are NOT exported (silent loss)', () {
      final e = Entry(
        uuid: 'e',
        fields: {Field.title: _f(Field.title, 'X')},
        tags: ['work', 'vip'],
      );
      final imported = _roundTrip(_rootWith(e)).root.entries.single;
      expect(imported.tags, isEmpty,
          reason: 'exporter has no Tags column — tags are lost on export');
    });
  });
}
