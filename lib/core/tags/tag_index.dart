// dgvault — KeePass Tags: index + database-wide tag operations.
//
// Pure Dart, model-only. KeePass stores tags as a per-entry list of strings;
// this provides the cross-database views (all tags, counts, entries-by-tag) and
// the bulk operations (rename/remove a tag everywhere) that a tag UI needs.
// Tag matching is exact and case-sensitive, matching KeePass.

import '../model/database.dart';
import '../model/entry.dart';
import '../model/group.dart';

/// Read-only view of the tags used across a group subtree.
class TagIndex {
  TagIndex(this.root);

  factory TagIndex.fromDatabase(Database db) => TagIndex(db.root);

  final Group root;

  /// Tag → number of entries carrying it.
  Map<String, int> tagCounts() {
    final counts = <String, int>{};
    for (final e in root.allEntries) {
      for (final t in e.tags) {
        counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    return counts;
  }

  /// All distinct tags, sorted.
  List<String> allTags() => tagCounts().keys.toList()..sort();

  /// Entries carrying [tag], in tree order.
  List<Entry> entriesWithTag(String tag) =>
      root.allEntries.where((e) => e.tags.contains(tag)).toList();
}

/// Mutating tag operations on entries / subtrees.
class TagOps {
  const TagOps._();

  /// Add [tag] to [entry] if non-empty and not already present. Returns true if
  /// the entry changed.
  static bool addTag(Entry entry, String tag) {
    if (tag.isEmpty || entry.tags.contains(tag)) return false;
    entry.tags.add(tag);
    return true;
  }

  /// Remove [tag] from [entry]. Returns true if the entry changed.
  static bool removeTagFromEntry(Entry entry, String tag) =>
      entry.tags.remove(tag);

  /// Rename [from] → [to] across every entry in [root]. If an entry already has
  /// [to], the duplicate is collapsed. Returns the number of entries changed.
  /// A no-op when [from] == [to] or [to] is empty.
  static int renameTag(Group root, String from, String to) {
    if (from == to || to.isEmpty) return 0;
    var changed = 0;
    for (final e in root.allEntries) {
      final i = e.tags.indexOf(from);
      if (i < 0) continue;
      e.tags.removeAt(i);
      if (!e.tags.contains(to)) {
        e.tags.insert(i, to);
      }
      changed++;
    }
    return changed;
  }

  /// Remove [tag] from every entry in [root]. Returns the number of entries
  /// changed.
  static int removeTag(Group root, String tag) {
    var changed = 0;
    for (final e in root.allEntries) {
      if (e.tags.remove(tag)) changed++;
    }
    return changed;
  }
}
