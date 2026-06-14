// dgvault — custom order & sorting.
//
// Two complementary capabilities:
//   • Column sorting — order entries/groups by a chosen key (title, username,
//     url, created, modified) ascending or descending. Stable, so equal keys
//     keep their existing relative order.
//   • Custom (manual) order — the model preserves explicit list order; this
//     provides safe reorder primitives (move, moveBefore) the UI drives via
//     drag-and-drop, and a recursive "apply manual order" pass.
//
// Sorting is non-destructive for column sorts on copies, with in-place variants
// for when the UI commits an order to the database. Pure Dart.

import '../model/entry.dart';
import '../model/field.dart';
import '../model/group.dart';

enum EntrySortKey { title, username, url, created, modified }

class EntrySortSpec {
  const EntrySortSpec(this.key, {this.ascending = true});

  final EntrySortKey key;
  final bool ascending;

  EntrySortSpec get reversed => EntrySortSpec(key, ascending: !ascending);
}

class EntrySorter {
  const EntrySorter();

  /// Returns a new list of [entries] ordered by [spec]. Stable: entries with
  /// equal keys retain their input order. Null/empty keys sort last regardless
  /// of direction (so blanks never crowd the top of a descending sort).
  List<Entry> sorted(Iterable<Entry> entries, EntrySortSpec spec) {
    final list = entries.toList();
    _stableSort(list, _comparatorFor(spec));
    return list;
  }

  /// Sorts a group's entries in place (commits a column sort to the model).
  void sortGroupEntries(Group group, EntrySortSpec spec) {
    _stableSort(group.entries, _comparatorFor(spec));
  }

  /// Sorts [group]'s entries and, when [recursive], every descendant group's
  /// entries and child-group lists (child groups ordered by name).
  void sortTree(Group group, EntrySortSpec spec, {bool recursive = true}) {
    sortGroupEntries(group, spec);
    _stableSort(
      group.groups,
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    if (recursive) {
      for (final child in group.groups) {
        sortTree(child, spec, recursive: true);
      }
    }
  }

  Comparator<Entry> _comparatorFor(EntrySortSpec spec) {
    // Null/empty keys always sort last, independent of direction; only the
    // comparison between two present values is reversed for descending order.
    return (a, b) {
      final (Comparable<Object>? ka, Comparable<Object>? kb) =
          (_key(a, spec.key), _key(b, spec.key));
      if (ka == null && kb == null) return 0;
      if (ka == null) return 1; // a after b
      if (kb == null) return -1; // a before b
      final c = ka.compareTo(kb);
      return spec.ascending ? c : -c;
    };
  }

  /// Returns the sort key for [e] under [key], or null when absent/blank.
  Comparable<Object>? _key(Entry e, EntrySortKey key) {
    switch (key) {
      case EntrySortKey.title:
        return _text(e, Field.title);
      case EntrySortKey.username:
        return _text(e, Field.userName);
      case EntrySortKey.url:
        return _text(e, Field.url);
      case EntrySortKey.created:
        return e.created;
      case EntrySortKey.modified:
        return e.modified;
    }
  }

  String? _text(Entry e, String key) {
    final v = e.fields[key]?.value.reveal();
    if (v == null || v.isEmpty) return null;
    return v.toLowerCase();
  }

  // ---- custom / manual order ----

  /// Moves the entry at [from] to index [to] within [group], shifting the rest.
  /// Indices are clamped to valid bounds.
  void move(Group group, int from, int to) {
    final list = group.entries;
    if (list.isEmpty) return;
    final f = from.clamp(0, list.length - 1);
    final entry = list.removeAt(f);
    final t = to.clamp(0, list.length);
    list.insert(t, entry);
  }

  /// Moves [entry] to directly precede [anchor] within [group]. If [anchor] is
  /// null, moves [entry] to the end. Both must already be in [group].
  void moveBefore(Group group, Entry entry, Entry? anchor) {
    final list = group.entries;
    if (!list.remove(entry)) {
      throw StateError('moveBefore: entry not in group');
    }
    if (anchor == null) {
      list.add(entry);
      return;
    }
    final idx = list.indexOf(anchor);
    if (idx < 0) {
      throw StateError('moveBefore: anchor not in group');
    }
    list.insert(idx, entry);
  }
}

void _stableSort<T>(List<T> list, Comparator<T> compare) {
  // Decorate with original index to make any comparator stable.
  final indexed = <_Indexed<T>>[
    for (var i = 0; i < list.length; i++) _Indexed(i, list[i]),
  ];
  indexed.sort((a, b) {
    final c = compare(a.value, b.value);
    return c != 0 ? c : a.index.compareTo(b.index);
  });
  for (var i = 0; i < list.length; i++) {
    list[i] = indexed[i].value;
  }
}

class _Indexed<T> {
  _Indexed(this.index, this.value);
  final int index;
  final T value;
}
