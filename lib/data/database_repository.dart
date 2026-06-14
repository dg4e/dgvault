// dgvault — database repository (data layer).
//
// Wraps an in-memory [Database] and is the single seam through which the UI
// mutates content. Its primary job for this task is enforcing **Read-Only
// Mode**: when the database is opened read-only (e.g. a sync provider served a
// read-only file, or the user toggled view-only), every content mutation throws
// [ReadOnlyDatabaseException] instead of silently succeeding.
//
// Pure Dart, platform-agnostic, fully unit-testable.

import '../core/model/database.dart';
import '../core/model/entry.dart';
import '../core/model/group.dart';

/// Thrown when a mutation is attempted on a read-only database.
class ReadOnlyDatabaseException implements Exception {
  ReadOnlyDatabaseException(this.operation);

  /// Name of the attempted mutation (for diagnostics / UI messaging).
  final String operation;

  @override
  String toString() =>
      'ReadOnlyDatabaseException: cannot "$operation" — database is read-only';
}

/// Read + (guarded) write access to a [Database].
abstract interface class DatabaseRepository {
  Database get database;
  bool get isReadOnly;

  // ---- reads (always permitted) ----
  Iterable<Entry> get allEntries;
  Entry? findEntry(String uuid);
  Group? findGroupOf(Entry entry);

  // ---- writes (rejected when read-only) ----
  void addEntry(Group parent, Entry entry);
  void deleteEntry(Entry entry);
  void moveEntry(Entry entry, Group destination);
  void addGroup(Group parent, Group group);

  /// Toggle the session read-only flag. This is a view-mode change, not a
  /// content write, so it is always permitted.
  void setReadOnly(bool value);
}

class InMemoryDatabaseRepository implements DatabaseRepository {
  InMemoryDatabaseRepository(this._database);

  final Database _database;

  @override
  Database get database => _database;

  @override
  bool get isReadOnly => _database.readOnly;

  @override
  Iterable<Entry> get allEntries => _database.root.allEntries;

  @override
  Entry? findEntry(String uuid) {
    for (final e in _database.root.allEntries) {
      if (e.uuid == uuid) return e;
    }
    return null;
  }

  @override
  Group? findGroupOf(Entry entry) => _findGroupOf(_database.root, entry);

  Group? _findGroupOf(Group group, Entry entry) {
    if (group.entries.contains(entry)) return group;
    for (final child in group.groups) {
      final found = _findGroupOf(child, entry);
      if (found != null) return found;
    }
    return null;
  }

  @override
  void addEntry(Group parent, Entry entry) {
    _guard('addEntry');
    parent.entries.add(entry);
  }

  @override
  void deleteEntry(Entry entry) {
    _guard('deleteEntry');
    final owner = findGroupOf(entry);
    if (owner == null) {
      throw StateError('deleteEntry: entry ${entry.uuid} not in this database');
    }
    owner.entries.remove(entry);
  }

  @override
  void moveEntry(Entry entry, Group destination) {
    _guard('moveEntry');
    final owner = findGroupOf(entry);
    if (owner == null) {
      throw StateError('moveEntry: entry ${entry.uuid} not in this database');
    }
    if (identical(owner, destination)) return;
    owner.entries.remove(entry);
    destination.entries.add(entry);
  }

  @override
  void addGroup(Group parent, Group group) {
    _guard('addGroup');
    parent.groups.add(group);
  }

  @override
  void setReadOnly(bool value) {
    _database.readOnly = value;
  }

  void _guard(String operation) {
    if (_database.readOnly) {
      throw ReadOnlyDatabaseException(operation);
    }
  }
}
