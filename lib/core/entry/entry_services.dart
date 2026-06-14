// dgvault — custom-field helpers + attachment (binary-pool) management.
//
// Pure Dart, model-only. KeePass entries carry arbitrary custom string fields
// (some protected) and reference binaries pooled at the database level. These
// services provide the add/remove operations a UI needs while keeping the pool
// consistent (orphan pruning on detach, unique id minting on attach).

import 'dart:typed_data';

import '../model/attachment.dart';
import '../model/database.dart';
import '../model/entry.dart';
import '../model/field.dart';
import '../model/protected_value.dart';

/// Custom (non-standard) string-field operations on an [Entry].
extension EntryCustomFields on Entry {
  /// All custom fields (excludes the five standard KeePass fields).
  List<Field> customFields() => fields.values.where((f) => f.isCustom).toList();

  /// Set a custom field [key] = [value]. Throws if [key] is a standard field
  /// key (use the standard field directly for those).
  void setCustomField(String key, String value, {bool protect = false}) {
    if (Field.isStandardKey(key)) {
      throw ArgumentError.value(key, 'key', 'is a standard field key');
    }
    if (key.isEmpty) {
      throw ArgumentError.value(key, 'key', 'must not be empty');
    }
    fields[key] = Field(
      key: key,
      value: protect
          ? InMemoryProtectedValue(value)
          : InMemoryProtectedValue.plain(value),
    );
  }

  /// Remove a custom field. Returns true if it existed. Refuses to remove
  /// standard fields.
  bool removeCustomField(String key) {
    if (Field.isStandardKey(key)) return false;
    return fields.remove(key) != null;
  }
}

/// Attachment + binary-pool management within a single database.
class AttachmentService {
  const AttachmentService();

  /// Attach binary [data] (named [name]) to [entry], storing the payload once in
  /// [db.binaryPool] and referencing it from the entry. A unique pool id is
  /// minted unless [id] is supplied. Returns the entry-side reference.
  Attachment attach(
    Database db,
    Entry entry, {
    required String name,
    required Uint8List data,
    String? id,
  }) {
    final poolId = id ?? _mintId(db);
    if (!db.binaryPool.any((b) => b.id == poolId)) {
      db.binaryPool.add(Attachment(
        id: poolId,
        name: name,
        size: data.length,
        inlineData: data,
      ));
    }
    // Entry-side reference is a pointer (no inline payload).
    final ref = Attachment(id: poolId, name: name, size: data.length);
    entry.attachments.add(ref);
    return ref;
  }

  /// Remove the reference to [attachmentId] from [entry]. When [pruneOrphan] is
  /// true and no other entry references that id, the pooled binary is removed
  /// too. Returns true if the entry referenced it.
  bool detach(
    Database db,
    Entry entry,
    String attachmentId, {
    bool pruneOrphan = true,
  }) {
    final before = entry.attachments.length;
    entry.attachments.removeWhere((a) => a.id == attachmentId);
    final removed = entry.attachments.length != before;
    if (removed && pruneOrphan && !_isReferenced(db, attachmentId)) {
      db.binaryPool.removeWhere((b) => b.id == attachmentId);
    }
    return removed;
  }

  /// Pooled binaries not referenced by any entry.
  List<Attachment> orphans(Database db) =>
      db.binaryPool.where((b) => !_isReferenced(db, b.id)).toList();

  bool _isReferenced(Database db, String id) =>
      db.root.allEntries.any((e) => e.attachments.any((a) => a.id == id));

  String _mintId(Database db) {
    final existing = db.binaryPool.map((b) => b.id).toSet();
    var n = 0;
    while (existing.contains('bin-$n')) {
      n++;
    }
    return 'bin-$n';
  }
}
