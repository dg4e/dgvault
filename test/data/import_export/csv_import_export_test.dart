import 'dart:math';

import 'package:dgvault/core/io/csv.dart';
import 'package:dgvault/core/model/entry.dart';
import 'package:dgvault/core/model/field.dart';
import 'package:dgvault/core/model/group.dart';
import 'package:dgvault/core/model/protected_value.dart';
import 'package:dgvault/data/import_export/csv_import_export.dart';
import 'package:test/test.dart';

void main() {
  CsvImporter importer() => CsvImporter(random: Random(1));

  group('CsvImporter — KeePassXC schema', () {
    const csv = '"Group","Title","Username","Password","URL","Notes","TOTP"\n'
        '"Bank/Personal","ACME Bank","alice","s3cret","https://bank.example","note","otpseed"\n'
        '"","Email","bob","pw2","https://mail.example","",""';

    test('maps standard fields and builds the group tree', () {
      final res = importer().import(csv);
      expect(res.entryCount, 2);

      // Top-level (no group) entry sits directly under root.
      final email = res.root.entries.singleWhere((e) => e.title == 'Email');
      expect(email.fields[Field.userName]!.value.reveal(), 'bob');
      expect(email.fields[Field.url]!.value.reveal(), 'https://mail.example');

      // Grouped entry under Bank/Personal.
      final bank = res.root.groups.singleWhere((g) => g.name == 'Bank');
      final personal = bank.groups.singleWhere((g) => g.name == 'Personal');
      final acme = personal.entries.single;
      expect(acme.title, 'ACME Bank');
      expect(acme.fields[Field.password]!.value.reveal(), 's3cret');
      expect(acme.fields[kTotpFieldKey]!.value.reveal(), 'otpseed');
      expect(acme.fields[Field.password]!.isProtected, isTrue);
    });
  });

  group('CsvImporter — 1Password-style headers + custom columns', () {
    const csv = 'Title,Url,Username,Password,Notes,One-time password,Membership No\n'
        'Gym,https://gym.example,carol,pw,hi there,otpx,12345';

    test('synonym headers map to standard fields; extras become custom fields', () {
      final res = importer().import(csv);
      final e = res.root.entries.single;
      expect(e.title, 'Gym');
      expect(e.fields[Field.url]!.value.reveal(), 'https://gym.example');
      expect(e.fields[Field.userName]!.value.reveal(), 'carol');
      expect(e.fields[kTotpFieldKey]!.value.reveal(), 'otpx');
      // Unmapped column preserved as a custom field under its header name.
      expect(e.fields['Membership No']!.value.reveal(), '12345');
      expect(e.fields['Membership No']!.isCustom, isTrue);
    });
  });

  group('CsvImporter — tags + empties', () {
    test('splits tags and skips blank rows', () {
      const csv = 'Title,Tags\n'
          'A,"work; personal,urgent"\n'
          '\n'
          'B,';
      final res = importer().import(csv);
      expect(res.entryCount, 2);
      final a = res.root.entries.firstWhere((e) => e.title == 'A');
      expect(a.tags, containsAll(['work', 'personal', 'urgent']));
    });

    test('empty CSV throws FormatException', () {
      expect(() => importer().import(''), throwsA(isA<FormatException>()));
    });
  });

  group('CsvExporter', () {
    test('emits header and one row per entry with group path', () {
      final root = Group(uuid: 'r', name: 'Root', groups: [
        Group(uuid: 'g', name: 'Bank', entries: [
          _entry('e1', title: 'ACME', username: 'alice', password: 's3cret'),
        ],),
      ], entries: [
        _entry('e2', title: 'Top'),
      ],);
      final out = const CsvExporter().export(root);
      final rows = const CsvCodec().decode(out);
      expect(rows.first, CsvExporter.columns);
      // Top-level entry has empty group path.
      expect(rows.any((r) => r[1] == 'Top' && r[0] == ''), isTrue);
      // Grouped entry carries the group name as its path.
      expect(rows.any((r) => r[1] == 'ACME' && r[0] == 'Bank'), isTrue);
    });
  });

  group('round trip import → export → import', () {
    test('preserves field values', () {
      const csv = '"Group","Title","Username","Password","URL","Notes","TOTP"\n'
          '"Bank/Personal","ACME","alice","s3cret","https://b.example","n","seed"';
      final first = importer().import(csv);
      final exported = const CsvExporter().export(first.root);
      final second = CsvImporter(random: Random(2)).import(exported);

      Entry find(CsvImportResult r) =>
          r.root.groups.first.groups.first.entries.single;
      final a = find(first), b = find(second);
      for (final k in [Field.title, Field.userName, Field.password, Field.url]) {
        expect(b.fields[k]!.value.reveal(), a.fields[k]!.value.reveal());
      }
    });
  });
}

Entry _entry(String uuid,
    {String? title, String? username, String? password,}) {
  final f = <String, Field>{};
  void put(String k, String? v) {
    if (v != null) f[k] = Field(key: k, value: InMemoryProtectedValue(v));
  }

  put(Field.title, title);
  put(Field.userName, username);
  put(Field.password, password);
  return Entry(uuid: uuid, fields: f);
}
