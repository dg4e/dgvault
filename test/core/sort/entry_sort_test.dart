import 'package:dgvault/core/core.dart';
import 'package:test/test.dart';

Entry _e(String uuid, {String? title, String? user, DateTime? created}) {
  final fields = <String, Field>{};
  if (title != null) {
    fields[Field.title] =
        Field(key: Field.title, value: InMemoryProtectedValue.plain(title));
  }
  if (user != null) {
    fields[Field.userName] =
        Field(key: Field.userName, value: InMemoryProtectedValue.plain(user));
  }
  return Entry(uuid: uuid, fields: fields, created: created);
}

void main() {
  const sorter = EntrySorter();

  group('column sort', () {
    test('by title ascending, case-insensitive', () {
      final entries = [
        _e('1', title: 'banana'),
        _e('2', title: 'Apple'),
        _e('3', title: 'cherry'),
      ];
      final r = sorter.sorted(entries, const EntrySortSpec(EntrySortKey.title));
      expect(r.map((e) => e.uuid), ['2', '1', '3']);
    });

    test('descending reverses present values', () {
      final entries = [_e('1', title: 'a'), _e('2', title: 'b')];
      final r = sorter.sorted(
          entries, const EntrySortSpec(EntrySortKey.title, ascending: false));
      expect(r.map((e) => e.uuid), ['2', '1']);
    });

    test('null/blank keys sort last in BOTH directions', () {
      final entries = [
        _e('hasNone'),
        _e('hasTitle', title: 'name'),
        _e('blank', title: ''),
      ];
      final asc =
          sorter.sorted(entries, const EntrySortSpec(EntrySortKey.title));
      expect(asc.first.uuid, 'hasTitle');
      expect(asc.map((e) => e.uuid).skip(1).toSet(), {'hasNone', 'blank'});

      final desc = sorter.sorted(
          entries, const EntrySortSpec(EntrySortKey.title, ascending: false));
      expect(desc.first.uuid, 'hasTitle'); // still first, blanks still last
    });

    test('is stable for equal keys', () {
      final entries = [
        _e('1', title: 'same'),
        _e('2', title: 'same'),
        _e('3', title: 'same'),
      ];
      final r = sorter.sorted(entries, const EntrySortSpec(EntrySortKey.title));
      expect(r.map((e) => e.uuid), ['1', '2', '3']);
    });

    test('by created date', () {
      final entries = [
        _e('new', created: DateTime(2024, 6, 1)),
        _e('old', created: DateTime(2020, 1, 1)),
      ];
      final r =
          sorter.sorted(entries, const EntrySortSpec(EntrySortKey.created));
      expect(r.map((e) => e.uuid), ['old', 'new']);
    });
  });

  group('manual order', () {
    test('move shifts an entry to a new index', () {
      final g = Group(uuid: 'g', name: 'G', entries: [
        _e('a'),
        _e('b'),
        _e('c'),
      ]);
      sorter.move(g, 0, 2); // a -> end
      expect(g.entries.map((e) => e.uuid), ['b', 'c', 'a']);
    });

    test('move clamps out-of-range indices', () {
      final g = Group(uuid: 'g', name: 'G', entries: [_e('a'), _e('b')]);
      sorter.move(g, 5, 99);
      expect(g.entries.map((e) => e.uuid), ['a', 'b']);
    });

    test('moveBefore positions relative to an anchor', () {
      final a = _e('a');
      final b = _e('b');
      final c = _e('c');
      final g = Group(uuid: 'g', name: 'G', entries: [a, b, c]);
      sorter.moveBefore(g, c, a); // c before a
      expect(g.entries.map((e) => e.uuid), ['c', 'a', 'b']);
    });

    test('moveBefore null anchor moves to end', () {
      final a = _e('a');
      final b = _e('b');
      final g = Group(uuid: 'g', name: 'G', entries: [a, b]);
      sorter.moveBefore(g, a, null);
      expect(g.entries.map((e) => e.uuid), ['b', 'a']);
    });
  });

  group('sortTree', () {
    test('sorts entries and child groups recursively', () {
      final child = Group(uuid: 'c', name: 'Zeta', entries: [
        _e('z2', title: 'b'),
        _e('z1', title: 'a'),
      ]);
      final other = Group(uuid: 'd', name: 'Alpha');
      final root = Group(uuid: 'r', name: 'Root', groups: [child, other]);

      sorter.sortTree(root, const EntrySortSpec(EntrySortKey.title));
      expect(root.groups.map((g) => g.name), ['Alpha', 'Zeta']);
      expect(child.entries.map((e) => e.uuid), ['z1', 'z2']);
    });
  });
}
