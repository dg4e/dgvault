// dgvault — move/copy items between databases.
//
// Moving an entry across databases is more than a list splice: KDBX stores
// binary attachments in a per-database pool and entries reference them by id.
// A naive move would leave the entry pointing at ids that don't exist in the
// destination pool (and orphan binaries in the source). This service relinks
// attachment references into the destination pool and garbage-collects binaries
// that no longer have any referrer in the source.
//
// Pure Dart, platform-agnostic. Read-only databases reject moves (a move
// mutates both sides); copies reject only when the destination is read-only.

import '../core/model/attachment.dart';
import '../core/model/database.dart';
import '../core/model/entry.dart';
import '../core/model/field.dart';
import '../core/model/group.dart';
import '../core/model/protected_value.dart';
import 'database_repository.dart';

class DatabaseTransfer {
  const DatabaseTransfer();

  /// Moves [entry] out of [source] and into [destGroup] of [dest], relinking
  /// its attachments into the destination pool and pruning orphaned source
  /// binaries. Throws:
  ///  - [ReadOnlyDatabaseException] if either database is read-only,
  ///  - [StateError] if [entry] is not present in [source],
  ///  - [StateError] if [dest] already contains an entry with the same UUID.
  void moveEntry(
    Database source,
    Entry entry,
    Database dest,
    Group destGroup,
  ) {
    if (source.readOnly) throw ReadOnlyDatabaseException('moveEntry(source)');
    if (dest.readOnly) throw ReadOnlyDatabaseException('moveEntry(dest)');
    _assertNoUuidCollision(dest, entry);

    final owner = _findOwner(source.root, entry);
    if (owner == null) {
      throw StateError('moveEntry: entry ${entry.uuid} not found in source');
    }

    _relinkBinariesIntoDest(source, dest, entry);
    owner.entries.remove(entry);
    _pruneOrphans(source);
    destGroup.entries.add(entry);
  }

  /// Copies [entry] into [destGroup] of [dest], leaving the source entirely
  /// unchanged. The entry is **deep-cloned first** so relinking its attachments
  /// into the destination pool never mutates the source entry's references and
  /// the two databases never alias the same object. Returns the inserted clone.
  /// The copy keeps the same UUID, so callers wanting a distinct identity should
  /// assign a new UUID to the returned entry.
  Entry copyEntry(
    Entry entry,
    Database source,
    Database dest,
    Group destGroup,
  ) {
    if (dest.readOnly) throw ReadOnlyDatabaseException('copyEntry(dest)');
    _assertNoUuidCollision(dest, entry);
    final clone = _cloneEntry(entry);
    _relinkBinariesIntoDest(source, dest, clone);
    destGroup.entries.add(clone);
    return clone;
  }

  /// Deep-clones an entry: fresh field/value instances, copied attachment
  /// references, tags, and history (history versions carry no nested history,
  /// so the recursion terminates).
  Entry _cloneEntry(Entry e) {
    final fields = <String, Field>{};
    e.fields.forEach((key, f) {
      fields[key] = Field(
        key: f.key,
        value: InMemoryProtectedValue(
          f.value.reveal(),
          isProtected: f.value.isProtected,
        ),
      );
    });
    return Entry(
      uuid: e.uuid,
      fields: fields,
      tags: List<String>.of(e.tags),
      attachments: [
        for (final a in e.attachments)
          Attachment(
            id: a.id,
            name: a.name,
            size: a.size,
            inlineData: a.inlineData,
          ),
      ],
      history: [for (final h in e.history) _cloneEntry(h)],
      iconId: e.iconId,
      customIconUuid: e.customIconUuid,
      created: e.created,
      modified: e.modified,
    );
  }

  void _assertNoUuidCollision(Database dest, Entry entry) {
    for (final e in dest.root.allEntries) {
      if (e.uuid == entry.uuid) {
        throw StateError(
          'transfer: destination already contains entry ${entry.uuid}',
        );
      }
    }
  }

  Group? _findOwner(Group group, Entry entry) {
    if (group.entries.contains(entry)) return group;
    for (final child in group.groups) {
      final found = _findOwner(child, entry);
      if (found != null) return found;
    }
    return null;
  }

  /// Ensures every attachment referenced by [entry] exists in [dest]'s pool,
  /// rewriting the entry's references to the destination ids.
  void _relinkBinariesIntoDest(Database source, Database dest, Entry entry) {
    for (var i = 0; i < entry.attachments.length; i++) {
      final ref = entry.attachments[i];
      final binary = _poolBinary(source, ref.id) ?? ref;
      final destId = _ensureInDestPool(dest, binary);
      if (destId != ref.id) {
        entry.attachments[i] = Attachment(
          id: destId,
          name: ref.name,
          size: ref.size,
          inlineData: ref.inlineData,
        );
      }
    }
  }

  Attachment? _poolBinary(Database db, String id) {
    for (final b in db.binaryPool) {
      if (b.id == id) return b;
    }
    return null;
  }

  /// Adds [binary] to [dest]'s pool, returning the id to reference it by. If an
  /// identical binary (same id + size + name) already exists it is reused; if
  /// the id collides with a *different* binary, a fresh unique id is minted.
  String _ensureInDestPool(Database dest, Attachment binary) {
    final clash = _poolBinary(dest, binary.id);
    if (clash != null) {
      final identical = clash.size == binary.size && clash.name == binary.name;
      if (identical) return clash.id;
      final fresh = _mintId(dest, binary.id);
      dest.binaryPool.add(Attachment(
        id: fresh,
        name: binary.name,
        size: binary.size,
        inlineData: binary.inlineData,
      ));
      return fresh;
    }
    dest.binaryPool.add(Attachment(
      id: binary.id,
      name: binary.name,
      size: binary.size,
      inlineData: binary.inlineData,
    ));
    return binary.id;
  }

  String _mintId(Database dest, String base) {
    var n = 1;
    while (_poolBinary(dest, '$base#$n') != null) {
      n++;
    }
    return '$base#$n';
  }

  /// Removes pool binaries in [source] that no surviving entry references.
  void _pruneOrphans(Database source) {
    final referenced = <String>{};
    for (final e in source.root.allEntries) {
      for (final a in e.attachments) {
        referenced.add(a.id);
      }
    }
    source.binaryPool.removeWhere((b) => !referenced.contains(b.id));
  }
}
