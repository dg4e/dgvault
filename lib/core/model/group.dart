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
  })  : groups = groups ?? <Group>[],
        entries = entries ?? <Entry>[];

  final String uuid;
  String name;
  String? notes;

  final List<Group> groups;
  final List<Entry> entries;

  int iconId;
  String? customIconUuid;

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

  /// Total entries in this subtree (including subgroups).
  int get entryCount => allEntries.length;
}
