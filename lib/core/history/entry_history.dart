// dgvault — Entry History tracking.
//
// KeePass keeps a bounded list of prior versions of each entry. On every edit
// the *pre-edit* state is snapshotted and pushed onto [Entry.history]
// (oldest-first), then pruned to a retention policy (KeePass defaults: keep 10
// versions and at most ~6 MiB total). Users can browse and restore old
// versions.
//
// Pure Dart, platform-agnostic, deterministic (caller supplies `now`).

import '../model/entry.dart';
import '../model/field.dart';

/// Retention policy for an entry's history. Mirrors KeePass meta defaults.
class HistoryPolicy {
  const HistoryPolicy({
    this.maxItems = 10,
    this.maxTotalSizeBytes = 6 * 1024 * 1024,
  });

  /// Maximum number of historical versions kept (-1 = unlimited).
  final int maxItems;

  /// Maximum cumulative size of historical versions (-1 = unlimited). Oldest
  /// versions are dropped first when exceeded.
  final int maxTotalSizeBytes;

  static const HistoryPolicy unlimited =
      HistoryPolicy(maxItems: -1, maxTotalSizeBytes: -1);
}

class EntryHistoryService {
  const EntryHistoryService({this.policy = const HistoryPolicy()});

  final HistoryPolicy policy;

  /// Deep-copy the *content* of [e] (fields/tags/attachments/icon/timestamps)
  /// without its own history, so a snapshot never nests history recursively.
  static Entry snapshot(Entry e) {
    final fields = <String, Field>{};
    e.fields.forEach((key, f) {
      fields[key] = Field(
        key: f.key,
        value: InMemoryProtectedValue(f.value.reveal(), isProtected: f.isProtected),
      );
    });
    return Entry(
      uuid: e.uuid,
      fields: fields,
      tags: List<String>.of(e.tags),
      attachments: List.of(e.attachments), // Attachment is immutable
      history: const [], // snapshots carry no nested history
      iconId: e.iconId,
      customIconUuid: e.customIconUuid,
      created: e.created,
      modified: e.modified,
    );
  }

  /// Approximate stored size of an entry version in bytes: UTF-16 field values
  /// plus known attachment sizes. Used only for retention accounting.
  static int versionSize(Entry e) {
    var bytes = 0;
    for (final f in e.fields.values) {
      bytes += f.key.length * 2;
      bytes += f.value.reveal().length * 2;
    }
    for (final a in e.attachments) {
      bytes += a.size;
    }
    return bytes;
  }

  /// Record the current state of [entry] as a historical version, then bump
  /// [entry.modified] to [now] (if given) and prune per [policy].
  ///
  /// Call this immediately BEFORE applying an edit, so the snapshot captures the
  /// pre-edit state. Returns the number of versions retained.
  int record(Entry entry, {DateTime? now}) {
    entry.history.add(snapshot(entry));
    if (now != null) entry.modified = now;
    prune(entry);
    return entry.history.length;
  }

  /// Restore historical version [index] (0 = oldest) into [entry] in place.
  ///
  /// When [keepCurrentInHistory] is true the current state is first snapshotted
  /// so the restore itself is undoable. The restored version is left in history
  /// (KeePass behaviour: restoring does not consume the version).
  void restore(Entry entry, int index, {bool keepCurrentInHistory = true, DateTime? now}) {
    if (index < 0 || index >= entry.history.length) {
      throw RangeError.index(index, entry.history, 'index');
    }
    final target = entry.history[index];
    if (keepCurrentInHistory) {
      entry.history.add(snapshot(entry));
    }
    // Copy target content into entry (fields/tags/attachments/icon).
    entry.fields
      ..clear()
      ..addAll({
        for (final e in target.fields.entries)
          e.key: Field(
            key: e.value.key,
            value: InMemoryProtectedValue(e.value.value.reveal(),
                isProtected: e.value.isProtected),
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
    if (now != null) entry.modified = now;
    prune(entry);
  }

  /// Enforce [policy] on [entry.history], dropping oldest versions first.
  void prune(Entry entry) {
    final h = entry.history;
    if (policy.maxItems >= 0) {
      while (h.length > policy.maxItems) {
        h.removeAt(0);
      }
    }
    if (policy.maxTotalSizeBytes >= 0) {
      var total = h.fold<int>(0, (sum, e) => sum + versionSize(e));
      while (h.length > 1 && total > policy.maxTotalSizeBytes) {
        total -= versionSize(h.removeAt(0));
      }
    }
  }

  /// Remove all historical versions.
  void clear(Entry entry) => entry.history.clear();
}

/// Convenience extension for call sites that just want to track an edit.
extension EntryHistoryX on Entry {
  /// Snapshot current state into history using the default policy. Returns the
  /// retained version count. Prefer [EntryHistoryService.record] when you need a
  /// custom policy or to set the modified timestamp.
  int pushHistory({DateTime? now, HistoryPolicy policy = const HistoryPolicy()}) {
    return EntryHistoryService(policy: policy).record(this, now: now);
  }
}
