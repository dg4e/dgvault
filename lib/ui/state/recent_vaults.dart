// dgvault — most-recently-accessed vaults, for one-tap reopen on the landing
// screen. Persisted as a small JSON file in the app-support directory. A
// "location" is whatever the vault was opened with: a filesystem path (desktop),
// an Android SAF content:// URI, or an iOS bookmark token — all reopenable
// because the picker grants (SAF) / bookmarks persist across launches.

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class RecentVault {
  const RecentVault(this.location, this.name);
  final String location;
  final String name;
}

class RecentVaults {
  static const _fileName = 'recent_vaults.json';
  static const maxEntries = 4;

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Most-recent first. Never throws — a corrupt/missing file yields empty.
  static Future<List<RecentVault>> list() async {
    try {
      final f = await _file();
      if (!f.existsSync()) return const [];
      return _decode(await f.readAsString());
    } catch (_) {
      return const [];
    }
  }

  /// Record [location] as the newest entry (deduped, capped).
  static Future<void> remember(String location, String name) async {
    if (location.isEmpty) return;
    final next = merged(await list(), location, name);
    await _write(next);
  }

  /// Drop [location] (e.g. the file moved/was deleted).
  static Future<void> forget(String location) async {
    final next = (await list()).where((r) => r.location != location).toList();
    await _write(next);
  }

  /// Forget every recent vault (Settings → clear recents). Never throws.
  static Future<void> clear() async {
    try {
      final f = await _file();
      if (f.existsSync()) await f.delete();
    } catch (_) {
      // Nothing to clear / already gone.
    }
  }

  // ---- pure helpers (unit-tested) -----------------------------------------

  /// The new list after promoting [location] to the front: deduped by location,
  /// most-recent first, capped to [maxEntries].
  static List<RecentVault> merged(
    List<RecentVault> current,
    String location,
    String name,
  ) =>
      <RecentVault>[
        RecentVault(location, name),
        ...current.where((r) => r.location != location),
      ].take(maxEntries).toList();

  static List<RecentVault> _decode(String raw) {
    final data = jsonDecode(raw);
    if (data is! List) return const [];
    return data
        .whereType<Map<String, dynamic>>()
        .where((m) => m['location'] is String)
        .map(
          (m) => RecentVault(
            m['location'] as String,
            m['name'] as String? ?? 'vault.kdbx',
          ),
        )
        .where((r) => r.location.isNotEmpty)
        .toList();
  }

  static Future<void> _write(List<RecentVault> items) async {
    final f = await _file();
    await f.writeAsString(
      jsonEncode([
        for (final r in items) {'location': r.location, 'name': r.name},
      ]),
    );
  }
}
