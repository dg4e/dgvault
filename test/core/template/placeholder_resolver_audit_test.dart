// Critic-owned adversarial audit for the placeholder resolver.
//
// Composer's own suite covers happy paths and REF-cycle termination. These tests
// target the edges a resolver most often gets wrong: NON-ref cycles ({S:} self
// reference), the {O}/Other field code, expansion that crosses placeholder
// *types* between passes, the maxDepth boundary, and the loose-match behaviour of
// an empty REF search text. Each assertion was traced against the current
// implementation by hand (the Flutter/Dart toolchain is not installed here, so
// `flutter test` cannot be executed — see reviews/Critic-round-4.md).

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
    Database(meta: DatabaseMeta(name: 'T'), root: Group(uuid: 'root', name: 'Root', entries: entries));

void main() {
  group('non-REF cycle safety', () {
    test('a {S:} custom string that references itself terminates verbatim', () {
      final e = _entry('u1', {
        Field.title: 'Self',
        'Loop': '{S:Loop}',
      });
      final r = PlaceholderResolver(_db([e]));
      // Fixed point reached immediately; must not loop or throw.
      expect(r.resolve('{S:Loop}', e), '{S:Loop}');
    });
  });

  group('cross-type expansion across passes', () {
    test('a custom string containing a local placeholder fully resolves', () {
      final e = _entry('u1', {
        Field.title: 'Hello',
        'Greeting': '{TITLE}',
      });
      final r = PlaceholderResolver(_db([e]));
      // pass 1: {S:Greeting} -> {TITLE}; pass 2: {TITLE} -> Hello
      expect(r.resolve('{S:Greeting}', e), 'Hello');
    });
  });

  group('{O} / Other field code', () {
    test('{REF:O@I:uuid} returns the targets first custom field', () {
      final target = _entry('T1', {
        Field.title: 'Std',
        'ApiNote': 'extra-value', // first (only) custom field
      });
      final ctx = _entry('c1', {Field.title: 'ctx'});
      final r = PlaceholderResolver(_db([target, ctx]));
      expect(r.resolve('{REF:O@I:T1}', ctx), 'extra-value');
    });
  });

  group('maxDepth boundary', () {
    test('maxDepth:1 performs exactly one expansion (inner ref left raw)', () {
      final a = _entry('A1', {Field.password: '{REF:P@I:B1}'});
      final b = _entry('B1', {Field.password: 'deep'});
      final r = PlaceholderResolver(_db([a, b]));
      // One pass: {PASSWORD} -> a.Password ('{REF:P@I:B1}'); ref not yet expanded.
      expect(r.resolve('{PASSWORD}', a, maxDepth: 1), '{REF:P@I:B1}');
      // Two passes are enough to fully resolve.
      expect(r.resolve('{PASSWORD}', a, maxDepth: 2), 'deep');
    });
  });

  group('empty REF search text — documented foot-gun', () {
    test('{REF:P@T:} matches the FIRST entry via empty-substring match', () {
      // needle '' -> hay.contains('') is always true, so the first scanned
      // entry is selected. This is surprising; flagged in the review as a
      // potential foot-gun rather than a hard bug. Test pins current behaviour
      // so a future fix is a conscious, visible change.
      final first = _entry('f1', {Field.title: 'Alpha', Field.password: 'first-pw'});
      final second = _entry('s1', {Field.title: 'Beta', Field.password: 'second-pw'});
      final ctx = _entry('c1', {Field.title: 'ctx'});
      final r = PlaceholderResolver(_db([first, second, ctx]));
      expect(r.resolve('{REF:P@T:}', ctx), 'first-pw');
    });
  });
}
