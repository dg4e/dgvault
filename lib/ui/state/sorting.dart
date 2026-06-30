// dgvault — display-level sort orders for folders and entries.
//
// These are non-destructive: they reorder what the UI shows without touching
// the stored custom order in the model. `manual` preserves the database's own
// ordering.

import 'package:dgvault/core/core.dart';

enum FolderSort { manual, nameAsc, nameDesc }

enum EntrySort { manual, titleAsc, titleDesc, modifiedDesc, createdDesc }

extension FolderSortX on FolderSort {
  String get label => switch (this) {
        FolderSort.manual => 'manual',
        FolderSort.nameAsc => 'name a→z',
        FolderSort.nameDesc => 'name z→a',
      };

  /// A copy of [groups] in this order (input is never mutated).
  List<Group> apply(List<Group> groups) {
    if (this == FolderSort.manual) return groups;
    int byName(Group a, Group b) =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return stableSort(
        groups, this == FolderSort.nameAsc ? byName : (a, b) => byName(b, a),);
  }
}

/// A stable sort (equal-key items keep their original relative order) returning
/// a new list — Dart's [List.sort] is not guaranteed stable, which would let
/// items with equal titles/timestamps reshuffle between rebuilds.
List<T> stableSort<T>(List<T> items, int Function(T a, T b) compare) {
  final indexed = [
    for (var i = 0; i < items.length; i++) (i, items[i]),
  ];
  indexed.sort((a, b) {
    final c = compare(a.$2, b.$2);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}

extension EntrySortX on EntrySort {
  String get label => switch (this) {
        EntrySort.manual => 'manual',
        EntrySort.titleAsc => 'title a→z',
        EntrySort.titleDesc => 'title z→a',
        EntrySort.modifiedDesc => 'modified',
        EntrySort.createdDesc => 'created',
      };

  /// A copy of [entries] in this order (input is never mutated).
  List<Entry> apply(List<Entry> entries) {
    if (this == EntrySort.manual) return entries;
    int byTitle(Entry a, Entry b) => (a.title ?? '')
        .toLowerCase()
        .compareTo((b.title ?? '').toLowerCase());
    // Newest first; entries without a timestamp sink to the bottom.
    int byDateDesc(DateTime? a, DateTime? b) {
      if (a == null && b == null) return 0;
      if (a == null) return 1;
      if (b == null) return -1;
      return b.compareTo(a);
    }

    return switch (this) {
      EntrySort.manual => entries, // handled by the early return above
      EntrySort.titleAsc => stableSort(entries, byTitle),
      EntrySort.titleDesc => stableSort(entries, (a, b) => byTitle(b, a)),
      EntrySort.modifiedDesc =>
        stableSort(entries, (a, b) => byDateDesc(a.modified, b.modified)),
      EntrySort.createdDesc =>
        stableSort(entries, (a, b) => byDateDesc(a.created, b.created)),
    };
  }
}
