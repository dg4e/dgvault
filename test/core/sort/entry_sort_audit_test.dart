// Critic-owned adversarial audit for custom order & sorting.
//
// Composer's suite covers ascending/descending, blanks-last-both-directions,
// basic stability, move/clamp/moveBefore, and sortTree. These add the edges that
// catch subtle comparator/reorder bugs: stability is preserved under *descending*
// order (tie-break must not reverse), `sorted()` is non-destructive, moveBefore
// handles the entry-before-anchor index shift and rejects non-members, and
// modified-date nulls sort last in both directions.
//
// Toolchain not installed here; assertions traced against source by hand
// (see reviews/Critic-round-9.md).

import 'package:dgvault/core/core.dart';
import 'package:dgvault/core/sort/entry_sort.dart';
import 'package:test/test.dart';

Entry _e(String uuid, {String? title, DateTime? modified}) {
  final fields = <String, Field>{};
  if (title != null) {
    fields[Field.title] =
        Field(key: Field.title, value: InMemoryProtectedValue.plain(title));
  }
  return Entry(uuid: uuid, fields: fields, modified: modified);
}

void main() {
  const sorter = EntrySorter();

  group('stability & purity', () {
    test('descending sort keeps INPUT order among equal keys (no tie reversal)', () {
      final list = [_e('x', title: 'same'), _e('y', title: 'same'), _e('z', title: 'same')];
      final desc =
          sorter.sorted(list, const EntrySortSpec(EntrySortKey.title, ascending: false));
      expect(desc.map((e) => e.uuid), ['x', 'y', 'z']);
    });

    test('sorted() is non-destructive to the input list', () {
      final input = [_e('b', title: 'b'), _e('a', title: 'a')];
      sorter.sorted(input, const EntrySortSpec(EntrySortKey.title));
      expect(input.map((e) => e.uuid), ['b', 'a'], reason: 'input must be untouched');
    });
  });

  group('modified-date nulls', () {
    test('null modified sorts last ascending AND descending', () {
      final withDate = _e('d', modified: DateTime.utc(2025));
      final noDate = _e('n');
      final asc =
          sorter.sorted([noDate, withDate], const EntrySortSpec(EntrySortKey.modified));
      expect(asc.last.uuid, 'n');
      final desc = sorter.sorted(
          [withDate, noDate], const EntrySortSpec(EntrySortKey.modified, ascending: false));
      expect(desc.last.uuid, 'n', reason: 'blanks stay last even descending');
    });
  });

  group('moveBefore edges', () {
    test('moving an entry that precedes the anchor lands just before it', () {
      final a = _e('a'), b = _e('b'), c = _e('c');
      final g = Group(uuid: 'g', name: 'G', entries: [a, b, c]);
      sorter.moveBefore(g, a, c); // a is before c → expect [b, a, c]
      expect(g.entries.map((e) => e.uuid), ['b', 'a', 'c']);
    });

    test('throws when the entry is not a member', () {
      final a = _e('a'), b = _e('b'), outsider = _e('z');
      final g = Group(uuid: 'g', name: 'G', entries: [a, b]);
      expect(() => sorter.moveBefore(g, outsider, a), throwsA(isA<StateError>()));
    });

    test('throws when the anchor is not a member', () {
      final a = _e('a'), outsider = _e('z');
      final g = Group(uuid: 'g', name: 'G', entries: [a]);
      expect(() => sorter.moveBefore(g, a, outsider), throwsA(isA<StateError>()));
    });
  });
}
