// Critic-owned adversarial round-trip audit for the KeePass inner-XML codec.
//
// This codec is interop-critical: it is the decrypted document KeePass stores
// inside a KDBX file, so any value the round-trip mangles is silent credential
// corruption. Composer's suite covers structural round-trips; these target the
// content edges that XML codecs classically get wrong:
//   • XML metacharacters in values (<, >, &, ", ')
//   • whitespace-significant values under pretty-printing (the DEFAULT) — the
//     highest-risk case: a pretty-printer that reflows text nodes would corrupt
//     leading/trailing spaces, tabs, and newlines in a password/note
//   • unicode + the Protected flag.
//
// Toolchain not installed here; the structural/escaping assertions are traced
// against `package:xml` semantics. The whitespace-under-pretty assertions double
// as a BUG PROBE: they encode the required invariant, so if pretty-printing
// reflows text content CI will surface it (see reviews/Critic-round-11.md).

import 'package:dgvault/core/core.dart';
import 'package:test/test.dart';

Database _dbWith(Entry e) =>
    Database(meta: DatabaseMeta(name: 'V'), root: Group(uuid: 'root', name: 'Root', entries: [e]));

Entry _roundTrip(Entry e, {bool pretty = true}) {
  final xml = const KeePassXml().encode(_dbWith(e), pretty: pretty);
  return const KeePassXml().decode(xml).root.entries.single;
}

Field _f(String key, String value, {bool protect = false}) =>
    Field(key: key, value: InMemoryProtectedValue(value, isProtected: protect));

void main() {
  test('XML metacharacters in values survive the round-trip', () {
    final e = Entry(uuid: 'e', fields: {
      Field.title: _f(Field.title, 'a<b>c&d"e\'f'),
      Field.password: _f(Field.password, 'p&<>"\'|', protect: true),
    },);
    final back = _roundTrip(e);
    expect(back.fields[Field.title]!.value.reveal(), 'a<b>c&d"e\'f');
    expect(back.fields[Field.password]!.value.reveal(), 'p&<>"\'|');
  });

  group('whitespace-significant values (pretty-print bug probe)', () {
    final e = Entry(uuid: 'e', fields: {
      Field.notes: _f(Field.notes, '  leading/trailing  '),
      Field.userName: _f(Field.userName, 'line1\nline2\tindented'),
    },);

    test('preserved with pretty: true (the default)', () {
      final back = _roundTrip(e, pretty: true);
      expect(back.fields[Field.notes]!.value.reveal(), '  leading/trailing  ',
          reason: 'pretty-printing must not trim/reflow value whitespace',);
      expect(back.fields[Field.userName]!.value.reveal(), 'line1\nline2\tindented');
    });

    test('preserved with pretty: false', () {
      final back = _roundTrip(e, pretty: false);
      expect(back.fields[Field.notes]!.value.reveal(), '  leading/trailing  ');
      expect(back.fields[Field.userName]!.value.reveal(), 'line1\nline2\tindented');
    });
  });

  test('unicode and the Protected flag round-trip', () {
    final e = Entry(uuid: 'e', fields: {
      Field.title: _f(Field.title, 'café — 日本語 — 🔐'),
      Field.password: _f(Field.password, 'pw', protect: true),
      'Recovery': _f('Recovery', 'protected-custom', protect: true),
      'Plain': _f('Plain', 'visible'),
    },);
    final back = _roundTrip(e);
    expect(back.fields[Field.title]!.value.reveal(), 'café — 日本語 — 🔐');
    expect(back.fields[Field.password]!.isProtected, isTrue);
    expect(back.fields['Recovery']!.isProtected, isTrue);
    expect(back.fields['Recovery']!.value.reveal(), 'protected-custom');
    expect(back.fields['Plain']!.isProtected, isFalse);
  });
}
