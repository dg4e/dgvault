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
    final out = List<Group>.of(groups);
    int byName(Group a, Group b) =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase());
    out.sort(this == FolderSort.nameAsc ? byName : (a, b) => byName(b, a));
    return out;
  }
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
    final out = List<Entry>.of(entries);
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

    switch (this) {
      case EntrySort.manual:
        break; // handled by the early return above
      case EntrySort.titleAsc:
        out.sort(byTitle);
      case EntrySort.titleDesc:
        out.sort((a, b) => byTitle(b, a));
      case EntrySort.modifiedDesc:
        out.sort((a, b) => byDateDesc(a.modified, b.modified));
      case EntrySort.createdDesc:
        out.sort((a, b) => byDateDesc(a.created, b.created));
    }
    return out;
  }
}
