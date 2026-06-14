// dgvault — Entry History tracking.
//
// KeePass keeps prior versions of an entry so edits are reversible. Before an
// entry is modified, a snapshot of its current state is appended to its history
// list (oldest-first). Retention is bounded by [EntryHistoryPolicy] — by item
// count and by total size — matching KeePass's MaxHistoryItems / MaxHistorySize.
//
// Pure Dart, platform-agnostic. A snapshot deliberately does NOT carry its own
// history (history versions are flat, never nested).

import '../model/attachment.dart';
import '../model/entry.dart';
import '../model/field.dart';
import '../model/protected_value.dart';

/// Retention policy for an entry's history. A negative bound means "unlimited".
class EntryHistoryPolicy {
  const EntryHistoryPolicy({
    this.maxItems = 10,
    this.maxSizeBytes = 6 * 1024 * 1024,
  });

  /// KeePass defaults: keep 10 versions, cap at 6 MiB.
  static const EntryHistoryPolicy keepassDefault = EntryHistoryPolicy();

  final int maxItems;
  final int maxSizeBytes;
}

class EntryHistory {
  /// Records the current state of [entry] as a historical version, then prunes
  /// per [policy]. Call this immediately BEFORE mutating the live entry.
  static void record(
    Entry entry, {
    EntryHistoryPolicy policy = EntryHistoryPolicy.keepassDefault,
  }) {
    entry.history.add(snapshotOf(entry));
    prune(entry.history, policy);
  }

  /// A flat copy of [entry]'s content (no nested history). Field secrets are
  /// re-wrapped in fresh [InMemoryProtectedValue]s so later disposal of the live
  /// entry's values does not corrupt the snapshot.
  static Entry snapshotOf(Entry entry) {
    final fields = <String, Field>{};
    entry.fields.forEach((key, field) {
      fields[key] = Field(
        key: field.key,
        value: InMemoryProtectedValue(
          field.value.reveal(),
          isProtected: field.value.isProtected,
        ),
      );
    });
    return Entry(
      uuid: entry.uuid,
      fields: fields,
      tags: List<String>.of(entry.tags),
      attachments: List<Attachment>.of(entry.attachments),
      history: <Entry>[], // flat: snapshots never nest history
      iconId: entry.iconId,
      customIconUuid: entry.customIconUuid,
      created: entry.created,
      modified: entry.modified,
    );
  }

  /// Trims [history] (oldest-first) to satisfy [policy]. At least one version is
  /// always retained when any size limit would otherwise empty the list.
  static void prune(List<Entry> history, EntryHistoryPolicy policy) {
    if (policy.maxItems >= 0) {
      while (history.length > policy.maxItems) {
        history.removeAt(0);
      }
    }
    if (policy.maxSizeBytes >= 0) {
      while (history.length > 1 && _totalSize(history) > policy.maxSizeBytes) {
        history.removeAt(0);
      }
    }
  }

  /// Restores historical version [index] (0 = oldest) into [entry] in place,
  /// so users can browse and revert prior versions. When [keepCurrentInHistory]
  /// is true the current state is snapshotted first, making the restore itself
  /// undoable (KeePass behaviour: the restored version is left in history).
  static void restore(
    Entry entry,
    int index, {
    bool keepCurrentInHistory = true,
    EntryHistoryPolicy policy = EntryHistoryPolicy.keepassDefault,
  }) {
    if (index < 0 || index >= entry.history.length) {
      throw RangeError.index(index, entry.history, 'index');
    }
    final target = entry.history[index];
    if (keepCurrentInHistory) {
      entry.history.add(snapshotOf(entry));
    }
    entry.fields
      ..clear()
      ..addAll({
        for (final f in target.fields.entries)
          f.key: Field(
            key: f.value.key,
            value: InMemoryProtectedValue(
              f.value.value.reveal(),
              isProtected: f.value.value.isProtected,
            ),
          ),
      });
    entry.tags
      ..clear()
      ..addAll(target.tags);
    entry.attachments
      ..clear()
      ..addAll(target.attachments);
    entry.iconId = target.iconId;
    entry.customIconUuid = target.customIconUuid;
    prune(entry.history, policy);
  }

  /// Removes all historical versions of [entry].
  static void clearHistory(Entry entry) => entry.history.clear();

  static int _totalSize(List<Entry> history) {
    var total = 0;
    for (final e in history) {
      total += estimateSize(e);
    }
    return total;
  }

  /// Rough byte size of an entry's content for size-based pruning: field values
  /// (UTF-16 code units ≈ 2 bytes) plus attachment payload sizes.
  static int estimateSize(Entry entry) {
    var bytes = 0;
    for (final field in entry.fields.values) {
      bytes += field.key.length * 2;
      bytes += field.value.reveal().length * 2;
    }
    for (final att in entry.attachments) {
      bytes += att.size;
    }
    return bytes;
  }
}
