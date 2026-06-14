import 'package:dgvault/core/model/entry.dart';
import 'package:dgvault/core/model/field.dart';
import 'package:dgvault/core/model/group.dart';
import 'package:dgvault/core/model/protected_value.dart';
import 'package:dgvault/core/tags/tag_index.dart';
import 'package:test/test.dart';

Entry e(String uuid, List<String> tags) => Entry(
      uuid: uuid,
      fields: {Field.title: Field(key: Field.title, value: InMemoryProtectedValue.plain(uuid))},
      tags: tags,
    );

Group tree(List<Entry> entries) =>
    Group(uuid: 'r', name: 'Root', entries: entries);

void main() {
  group('TagIndex', () {
    final root = tree([
      e('a', ['work', 'vip']),
      e('b', ['work']),
      e('c', ['personal']),
    ]);
    final idx = TagIndex(root);

    test('counts and sorted distinct tags', () {
      expect(idx.tagCounts(), {'work': 2, 'vip': 1, 'personal': 1});
      expect(idx.allTags(), ['personal', 'vip', 'work']);
    });

    test('entriesWithTag', () {
      expect(idx.entriesWithTag('work').map((x) => x.uuid), ['a', 'b']);
      expect(idx.entriesWithTag('none'), isEmpty);
    });
  });

  group('TagOps', () {
    test('addTag dedupes and ignores empty', () {
      final x = e('a', ['work']);
      expect(TagOps.addTag(x, 'vip'), isTrue);
      expect(TagOps.addTag(x, 'vip'), isFalse); // already present
      expect(TagOps.addTag(x, ''), isFalse);
      expect(x.tags, ['work', 'vip']);
    });

    test('removeTagFromEntry', () {
      final x = e('a', ['work', 'vip']);
      expect(TagOps.removeTagFromEntry(x, 'work'), isTrue);
      expect(TagOps.removeTagFromEntry(x, 'work'), isFalse);
      expect(x.tags, ['vip']);
    });

    test('renameTag across the tree, collapsing duplicates', () {
      final root = tree([
        e('a', ['work']),
        e('b', ['work', 'job']),
        e('c', ['personal']),
      ]);
      final changed = TagOps.renameTag(root, 'work', 'job');
      expect(changed, 2);
      // 'a' renamed work->job; 'b' had both, collapses to single 'job'.
      expect(root.entries[0].tags, ['job']);
      expect(root.entries[1].tags.where((t) => t == 'job').length, 1);
      expect(root.entries[2].tags, ['personal']);
    });

    test('renameTag is a no-op for equal or empty target', () {
      final root = tree([e('a', ['work'])]);
      expect(TagOps.renameTag(root, 'work', 'work'), 0);
      expect(TagOps.renameTag(root, 'work', ''), 0);
      expect(root.entries.single.tags, ['work']);
    });

    test('removeTag across the tree', () {
      final root = tree([
        e('a', ['work', 'vip']),
        e('b', ['work']),
      ]);
      expect(TagOps.removeTag(root, 'work'), 2);
      expect(root.entries[0].tags, ['vip']);
      expect(root.entries[1].tags, isEmpty);
    });
  });
}
