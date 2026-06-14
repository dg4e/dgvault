// dgvault — Compare Databases + advanced merge.
//
// Pure Dart, model-only. Two capabilities:
//   • [DatabaseComparator] produces a structural [DatabaseDiff] between two
//     databases keyed by KDBX UUID — added / removed / modified / moved entries
//     and added / removed / renamed / moved groups, with per-field change detail.
//   • [DatabaseMerger] performs a last-write-wins merge (KeePass-style: match by
//     UUID, newer `modified` timestamp wins) — the core primitive behind
//     Advanced Sync & Merge. Deletions are NOT propagated (conservative: a
//     missing entry on one side is treated as "not yet synced", never a delete),
//     matching KeePass behaviour absent a deleted-objects ledger.

import '../model/database.dart';
import '../model/entry.dart';
import '../model/field.dart';
import '../model/group.dart';
import '../model/protected_value.dart';

/// A single changed field between two versions of an entry.
class FieldChange {
  FieldChange({
    required this.key,
    required this.oldValue,
    required this.newValue,
    required this.isProtected,
  });

  final String key;
  final String? oldValue; // null = field absent on the old side
  final String? newValue; // null = field absent on the new side
  final bool isProtected;
}

/// An entry that exists on both sides but differs.
class EntryModification {
  EntryModification({
    required this.uuid,
    required this.fieldChanges,
    required this.tagsChanged,
    required this.moved,
    required this.oldParentUuid,
    required this.newParentUuid,
  });

  final String uuid;
  final List<FieldChange> fieldChanges;
  final bool tagsChanged;

  /// True when the entry's parent group changed.
  final bool moved;
  final String? oldParentUuid;
  final String? newParentUuid;

  bool get contentChanged => fieldChanges.isNotEmpty || tagsChanged;
}

class GroupRename {
  GroupRename({required this.uuid, required this.oldName, required this.newName});
  final String uuid;
  final String oldName;
  final String newName;
}

class DatabaseDiff {
  DatabaseDiff({
    required this.addedEntries,
    required this.removedEntries,
    required this.modifiedEntries,
    required this.addedGroups,
    required this.removedGroups,
    required this.renamedGroups,
  });

  /// UUIDs present in `b` but not `a`.
  final List<String> addedEntries;

  /// UUIDs present in `a` but not `b`.
  final List<String> removedEntries;

  /// Entries present in both with differing content or location.
  final List<EntryModification> modifiedEntries;

  final List<String> addedGroups;
  final List<String> removedGroups;
  final List<GroupRename> renamedGroups;

  bool get hasDifferences =>
      addedEntries.isNotEmpty ||
      removedEntries.isNotEmpty ||
      modifiedEntries.isNotEmpty ||
      addedGroups.isNotEmpty ||
      removedGroups.isNotEmpty ||
      renamedGroups.isNotEmpty;
}

/// Flattened view of a database keyed by UUID, with parent pointers.
class _Indexed {
  final Map<String, Entry> entries = {};
  final Map<String, String?> entryParent = {}; // entry uuid -> parent group uuid
  final Map<String, Group> groups = {};
  final Map<String, String?> groupParent = {}; // group uuid -> parent group uuid

  _Indexed(Group root) {
    void walk(Group g, String? parent) {
      groups[g.uuid] = g;
      groupParent[g.uuid] = parent;
      for (final e in g.entries) {
        entries[e.uuid] = e;
        entryParent[e.uuid] = g.uuid;
      }
      for (final child in g.groups) {
        walk(child, g.uuid);
      }
    }

    walk(root, null);
  }
}

class DatabaseComparator {
  const DatabaseComparator();

  DatabaseDiff compare(Database a, Database b) {
    final ia = _Indexed(a.root);
    final ib = _Indexed(b.root);

    final addedEntries = <String>[];
    final removedEntries = <String>[];
    final modified = <EntryModification>[];

    for (final uuid in ib.entries.keys) {
      if (!ia.entries.containsKey(uuid)) addedEntries.add(uuid);
    }
    for (final uuid in ia.entries.keys) {
      if (!ib.entries.containsKey(uuid)) removedEntries.add(uuid);
    }
    for (final uuid in ia.entries.keys) {
      final eb = ib.entries[uuid];
      if (eb == null) continue;
      final ea = ia.entries[uuid]!;
      final changes = _diffFields(ea, eb);
      final tagsChanged = !_sameTags(ea.tags, eb.tags);
      final pa = ia.entryParent[uuid];
      final pb = ib.entryParent[uuid];
      final moved = pa != pb;
      if (changes.isNotEmpty || tagsChanged || moved) {
        modified.add(EntryModification(
          uuid: uuid,
          fieldChanges: changes,
          tagsChanged: tagsChanged,
          moved: moved,
          oldParentUuid: pa,
          newParentUuid: pb,
        ));
      }
    }

    final addedGroups = <String>[];
    final removedGroups = <String>[];
    final renamed = <GroupRename>[];
    for (final uuid in ib.groups.keys) {
      if (!ia.groups.containsKey(uuid)) addedGroups.add(uuid);
    }
    for (final uuid in ia.groups.keys) {
      if (!ib.groups.containsKey(uuid)) removedGroups.add(uuid);
      final gb = ib.groups[uuid];
      if (gb != null && gb.name != ia.groups[uuid]!.name) {
        renamed.add(GroupRename(
          uuid: uuid,
          oldName: ia.groups[uuid]!.name,
          newName: gb.name,
        ));
      }
    }

    return DatabaseDiff(
      addedEntries: addedEntries,
      removedEntries: removedEntries,
      modifiedEntries: modified,
      addedGroups: addedGroups,
      removedGroups: removedGroups,
      renamedGroups: renamed,
    );
  }

  List<FieldChange> _diffFields(Entry a, Entry b) {
    final keys = <String>{...a.fields.keys, ...b.fields.keys};
    final out = <FieldChange>[];
    for (final k in keys) {
      final fa = a.fields[k];
      final fb = b.fields[k];
      final va = fa?.value.reveal();
      final vb = fb?.value.reveal();
      if (va != vb) {
        out.add(FieldChange(
          key: k,
          oldValue: va,
          newValue: vb,
          isProtected: (fa?.isProtected ?? false) || (fb?.isProtected ?? false),
        ));
      }
    }
    return out;
  }

  bool _sameTags(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    final sa = a.toSet();
    return sa.length == b.toSet().length && sa.containsAll(b);
  }
}

/// Outcome of a merge: which entries were added/updated into the target.
class MergeResult {
  MergeResult({required this.added, required this.updated});
  final List<String> added; // uuids added from source
  final List<String> updated; // uuids whose content was replaced by source
  int get changeCount => added.length + updated.length;
}

class DatabaseMerger {
  const DatabaseMerger();

  /// Merge [source] into [target] in place, last-write-wins by `modified`.
  ///
  /// - Entry in source but not target → added under a mirror of its source
  ///   group path (created as needed).
  /// - Entry in both → if source.modified is strictly newer, target's content
  ///   is replaced with a snapshot of source's.
  /// - Entry only in target → left untouched (no deletions propagated).
  MergeResult merge(Database target, Database source) {
    final it = _Indexed(target.root);
    final isrc = _Indexed(source.root);
    final added = <String>[];
    final updated = <String>[];

    for (final entry in isrc.entries.entries) {
      final uuid = entry.key;
      final se = entry.value;
      final te = it.entries[uuid];
      if (te == null) {
        final parentPath = _groupPath(isrc, isrc.entryParent[uuid]);
        final dest = _ensurePath(target.root, parentPath);
        dest.entries.add(_copyEntry(se));
        added.add(uuid);
      } else if (_isNewer(se.modified, te.modified)) {
        _replaceContent(te, se);
        updated.add(uuid);
      }
    }
    return MergeResult(added: added, updated: updated);
  }

  bool _isNewer(DateTime? source, DateTime? target) {
    if (source == null) return false;
    if (target == null) return true;
    return source.isAfter(target);
  }

  /// Names from root (exclusive) down to [groupUuid].
  List<String> _groupPath(_Indexed idx, String? groupUuid) {
    final names = <String>[];
    var cur = groupUuid;
    while (cur != null && idx.groupParent[cur] != null) {
      names.add(idx.groups[cur]!.name);
      cur = idx.groupParent[cur];
    }
    return names.reversed.toList();
  }

  Group _ensurePath(Group root, List<String> path) {
    var cur = root;
    for (final name in path) {
      cur = cur.groups.firstWhere(
        (g) => g.name == name,
        orElse: () {
          final g = Group(uuid: 'merged:$name:${cur.uuid}', name: name);
          cur.groups.add(g);
          return g;
        },
      );
    }
    return cur;
  }

  Entry _copyEntry(Entry e) {
    final fields = <String, Field>{};
    e.fields.forEach((k, f) {
      fields[k] = Field(key: f.key, value: _copyValue(f));
    });
    return Entry(
      uuid: e.uuid,
      fields: fields,
      tags: List<String>.of(e.tags),
      attachments: List.of(e.attachments),
      iconId: e.iconId,
      customIconUuid: e.customIconUuid,
      created: e.created,
      modified: e.modified,
    );
  }

  void _replaceContent(Entry target, Entry source) {
    target.fields
      ..clear()
      ..addAll({
        for (final e in source.fields.entries)
          e.key: Field(key: e.value.key, value: _copyValue(e.value)),
      });
    target.tags
      ..clear()
      ..addAll(source.tags);
    target.attachments
      ..clear()
      ..addAll(source.attachments);
    target.iconId = source.iconId;
    target.customIconUuid = source.customIconUuid;
    target.modified = source.modified;
  }

  ProtectedValue _copyValue(Field f) =>
      InMemoryProtectedValue(f.value.reveal(), isProtected: f.isProtected);
}
