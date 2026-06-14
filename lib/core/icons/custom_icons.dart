// dgvault — Custom Icons & Preset Icon Sets.
//
// KeePass entries/groups reference either a built-in preset icon (an index into
// the standard 69-icon set) or a custom icon (a UUID into a database-level
// custom-icon pool holding the image bytes). This provides:
//   • preset-icon validation (the standard index range),
//   • a custom-icon pool with content de-duplication, and
//   • reference scanning + orphan pruning across a database (so deleting the
//     last entry/group using an icon can reclaim its bytes).
//
// Pure Dart, model-only — no image decoding or I/O.

import 'dart:typed_data';

import '../model/database.dart';
import '../model/entry.dart';
import '../model/group.dart';

/// Number of built-in KeePass preset icons (indices 0..68). This is the fixed
/// KeePass 2.x standard icon set size.
const int kKeePassPresetIconCount = 69;

/// Whether [index] is a valid preset-icon index.
bool isValidPresetIcon(int index) =>
    index >= 0 && index < kKeePassPresetIconCount;

/// A reference to an icon: either a preset index or a custom-pool UUID.
class IconRef {
  IconRef.preset(int index)
      : presetIndex = index,
        customUuid = null {
    if (!isValidPresetIcon(index)) {
      throw ArgumentError.value(index, 'index', 'not a valid preset icon');
    }
  }

  IconRef.custom(String uuid)
      : presetIndex = null,
        customUuid = uuid;

  final int? presetIndex;
  final String? customUuid;

  bool get isCustom => customUuid != null;
}

/// A custom icon: a UUID and its raw image bytes (e.g. PNG).
class CustomIcon {
  CustomIcon({required this.uuid, required this.data});
  final String uuid;
  final Uint8List data;
}

/// Database-level pool of custom icons, keyed by UUID.
class CustomIconPool {
  CustomIconPool([Iterable<CustomIcon>? icons]) {
    if (icons != null) {
      for (final i in icons) {
        _byUuid[i.uuid] = i;
      }
    }
  }

  final Map<String, CustomIcon> _byUuid = {};

  Iterable<CustomIcon> get icons => _byUuid.values;
  int get length => _byUuid.length;
  bool contains(String uuid) => _byUuid.containsKey(uuid);
  CustomIcon? operator [](String uuid) => _byUuid[uuid];

  /// Add [icon]; replaces any existing icon with the same UUID.
  void add(CustomIcon icon) => _byUuid[icon.uuid] = icon;

  bool remove(String uuid) => _byUuid.remove(uuid) != null;

  /// Add [data] under [preferredUuid], de-duplicating by content: if an icon
  /// with identical bytes already exists, its UUID is returned and no new entry
  /// is added. Otherwise the icon is stored and [preferredUuid] returned.
  String addDeduplicated(String preferredUuid, Uint8List data) {
    for (final existing in _byUuid.values) {
      if (_bytesEqual(existing.data, data)) return existing.uuid;
    }
    _byUuid[preferredUuid] = CustomIcon(uuid: preferredUuid, data: data);
    return preferredUuid;
  }
}

/// Reference scanning + orphan management over a database's icon usage.
class CustomIconService {
  const CustomIconService();

  /// Every custom-icon UUID referenced by any group or entry in [db].
  Set<String> referencedUuids(Database db) {
    final refs = <String>{};
    void walk(Group g) {
      final gid = g.customIconUuid;
      if (gid != null) refs.add(gid);
      for (final e in g.entries) {
        final eid = e.customIconUuid;
        if (eid != null) refs.add(eid);
      }
      for (final child in g.groups) {
        walk(child);
      }
    }

    walk(db.root);
    return refs;
  }

  /// Pooled custom icons not referenced anywhere in [db].
  List<String> orphans(Database db, CustomIconPool pool) {
    final refs = referencedUuids(db);
    return pool.icons
        .map((i) => i.uuid)
        .where((u) => !refs.contains(u))
        .toList();
  }

  /// Remove every unreferenced icon from [pool]. Returns the count removed.
  int pruneOrphans(Database db, CustomIconPool pool) {
    final dead = orphans(db, pool);
    for (final u in dead) {
      pool.remove(u);
    }
    return dead.length;
  }
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
