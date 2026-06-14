// Verifies the two resolver fixes applied in round 4 per Critic R4 findings:
//   #1 empty {REF:...} search text must NOT match (was: matched first entry).
//   #2 {S:Name} custom-field lookup is case-insensitive (KeePass fidelity).
import 'package:dgvault/core/core.dart';
import 'package:test/test.dart';

Entry _entry(String uuid, Map<String, String> fields) {
  final map = <String, Field>{};
  fields.forEach((k, v) {
    map[k] = Field(
      key: k,
      value: InMemoryProtectedValue(v, isProtected: k == Field.password),
    );
  });
  return Entry(uuid: uuid, fields: map);
}

Database _db(List<Entry> entries) =>
    Database(meta: DatabaseMeta(name: 'T'), root: Group(uuid: 'r', name: 'Root', entries: entries));

void main() {
  test('empty REF search text is left verbatim (no arbitrary match)', () {
    final a = _entry('a', {Field.title: 'First', Field.password: 'first-pw'});
    final b = _entry('b', {Field.title: 'Second', Field.password: 'second-pw'});
    final r = PlaceholderResolver(_db([a, b]));
    // Previously '' substring-matched the first entry → leaked 'first-pw'.
    expect(r.resolve('{REF:P@T:}', b), '{REF:P@T:}');
  });

  test('{S:Name} resolves case-insensitively', () {
    final e = _entry('e', {Field.title: 'X', 'Token': 'abc123'});
    final r = PlaceholderResolver(_db([e]));
    expect(r.resolve('{S:Token}', e), 'abc123'); // exact
    expect(r.resolve('{S:token}', e), 'abc123'); // different case
    expect(r.resolve('{S:TOKEN}', e), 'abc123');
  });
}
