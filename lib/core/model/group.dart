import 'entry.dart';

/// A folder in the database tree. Holds child groups and entries, preserving
/// explicit ordering (Custom Order & Sorting feature).
class Group {
  Group({
    required this.uuid,
    required this.name,
    List<Group>? groups,
    List<Entry>? entries,
    this.iconId = 48, // KeePass default folder icon
    this.customIconUuid,
    this.notes,
    this.enableSearching,
  })  : groups = groups ?? <Group>[],
        entries = entries ?? <Entry>[];

  final String uuid;
  String name;
  String? notes;

  final List<Group> groups;
  final List<Entry> entries;

  int iconId;
  String? customIconUuid;

  /// KeePass per-group search flag (`EnableSearching`): whether this group's
  /// entries appear in whole-vault search. `null` = inherit from the parent
  /// (root defaults to searchable). `false` keeps the subtree out of the
  /// "All"/search view (e.g. an archive folder) while it stays fully browsable.
  bool? enableSearching;

  /// Depth-first walk over every entry in this subtree.
  Iterable<Entry> get allEntries sync* {
    yield* entries;
    for (final child in groups) {
      yield* child.allEntries;
    }
  }

  /// Entries in this subtree, skipping any group whose UUID is in [exclude]
  /// (e.g. the Recycle Bin) so trashed entries stay out of the normal view.
  Iterable<Entry> entriesExcluding(Set<String> exclude) sync* {
    if (exclude.contains(uuid)) return;
    yield* entries;
    for (final child in groups) {
      yield* child.entriesExcluding(exclude);
    }
  }

  /// Entries in this subtree that are searchable from the root/"All" view.
  /// A group in [nonSearchable] contributes none of its own entries, but the
  /// walk still descends into its children — so a child that re-enables
  /// searching (not in the set) is reached even under an excluded parent.
  Iterable<Entry> searchableEntries(Set<String> nonSearchable) sync* {
    if (!nonSearchable.contains(uuid)) yield* entries;
    for (final child in groups) {
      yield* child.searchableEntries(nonSearchable);
    }
  }

  /// Total entries in this subtree (including subgroups).
  int get entryCount => allEntries.length;
}
