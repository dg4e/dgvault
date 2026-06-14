// dgvault — CSV / 1Password import & export.
//
// Maps between CSV rows and the entry/group model. Supports KeePassXC-style CSV
// and 1Password CSV exports via case-insensitive header detection with common
// column synonyms; unmapped non-empty columns become custom fields. Pure Dart;
// uses the RFC 4180 [CsvCodec]. A uuid generator is injectable for deterministic
// tests.

import 'dart:convert';
import 'dart:math';

import '../../core/io/csv.dart';
import '../../core/model/entry.dart';
import '../../core/model/field.dart';
import '../../core/model/group.dart';
import '../../core/model/protected_value.dart';

/// Synthetic field key used for one-time-password seeds (KeePassXC uses "TOTP").
const String kTotpFieldKey = 'TOTP';

/// Result of a CSV import.
class CsvImportResult {
  CsvImportResult({required this.root, required this.entryCount, required this.warnings});

  /// Root group containing the imported tree (subgroups built from the Group
  /// column, '/'-separated).
  final Group root;
  final int entryCount;
  final List<String> warnings;
}

String _randomUuid(Random rng) {
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  return base64.encode(bytes);
}

/// Maps a CSV header (case-insensitive) to a standard [Field] key, or null when
/// it isn't a standard column.
String? _standardKeyFor(String header) {
  switch (header.trim().toLowerCase()) {
    case 'title':
    case 'name':
      return Field.title;
    case 'username':
    case 'user name':
    case 'login':
    case 'user':
      return Field.userName;
    case 'password':
    case 'pass':
      return Field.password;
    case 'url':
    case 'urls':
    case 'website':
      return Field.url;
    case 'notes':
    case 'note':
      return Field.notes;
  }
  return null;
}

bool _isGroupHeader(String h) {
  final l = h.trim().toLowerCase();
  return l == 'group' || l == 'folder';
}

bool _isTagsHeader(String h) => h.trim().toLowerCase() == 'tags';

bool _isTotpHeader(String h) {
  final l = h.trim().toLowerCase();
  return l == 'totp' ||
      l == 'otp' ||
      l == 'otpauth' ||
      l == 'one-time password' ||
      l == 'one time password';
}

class CsvImporter {
  CsvImporter({Random? random, CsvCodec codec = const CsvCodec()})
      : _rng = random ?? Random.secure(),
        _codec = codec;

  final Random _rng;
  final CsvCodec _codec;

  /// Import [csv]. The first record is treated as the header row. Throws
  /// [FormatException] when there is no header.
  CsvImportResult import(String csv, {String rootName = 'Imported'}) {
    final rows = _codec.decode(csv);
    if (rows.isEmpty) {
      throw const FormatException('CSV is empty — no header row');
    }
    final headers = rows.first;
    final warnings = <String>[];
    final root = Group(uuid: _randomUuid(_rng), name: rootName);
    var count = 0;

    for (var r = 1; r < rows.length; r++) {
      final row = rows[r];
      if (row.every((c) => c.isEmpty)) continue; // skip blank lines
      final fields = <String, Field>{};
      final tags = <String>[];
      var groupPath = '';

      for (var c = 0; c < headers.length; c++) {
        final header = headers[c];
        final value = c < row.length ? row[c] : '';
        if (value.isEmpty) continue;

        if (_isGroupHeader(header)) {
          groupPath = value;
          continue;
        }
        if (_isTagsHeader(header)) {
          tags.addAll(value
              .split(RegExp(r'[;,]'))
              .map((t) => t.trim())
              .where((t) => t.isNotEmpty));
          continue;
        }
        if (_isTotpHeader(header)) {
          fields[kTotpFieldKey] =
              Field(key: kTotpFieldKey, value: InMemoryProtectedValue(value));
          continue;
        }
        final std = _standardKeyFor(header);
        final key = std ?? header.trim();
        final protected = key == Field.password || key == kTotpFieldKey;
        fields[key] = Field(
          key: key,
          value: protected
              ? InMemoryProtectedValue(value)
              : InMemoryProtectedValue.plain(value),
        );
      }

      if (fields.isEmpty && tags.isEmpty) {
        warnings.add('Row ${r + 1} skipped: no mappable data');
        continue;
      }

      final entry = Entry(uuid: _randomUuid(_rng), fields: fields, tags: tags);
      _placeInGroup(root, groupPath, entry);
      count++;
    }

    return CsvImportResult(root: root, entryCount: count, warnings: warnings);
  }

  void _placeInGroup(Group root, String path, Entry entry) {
    if (path.isEmpty) {
      root.entries.add(entry);
      return;
    }
    var current = root;
    for (final segment in path.split('/').map((s) => s.trim())) {
      if (segment.isEmpty) continue;
      var child = current.groups.firstWhere(
        (g) => g.name == segment,
        orElse: () {
          final g = Group(uuid: _randomUuid(_rng), name: segment);
          current.groups.add(g);
          return g;
        },
      );
      current = child;
    }
    current.entries.add(entry);
  }
}

class CsvExporter {
  const CsvExporter({this.codec = const CsvCodec()});

  final CsvCodec codec;

  /// KeePassXC-compatible export columns.
  static const List<String> columns = [
    'Group', 'Title', 'Username', 'Password', 'URL', 'Notes', 'TOTP',
  ];

  /// Export every entry under [root] to a CSV string. Group paths are built from
  /// the tree (the root group's own name is not included in the path).
  String export(Group root) {
    final rows = <List<String>>[columns];
    void walk(Group group, String path) {
      for (final e in group.entries) {
        rows.add([
          path,
          _reveal(e, Field.title),
          _reveal(e, Field.userName),
          _reveal(e, Field.password),
          _reveal(e, Field.url),
          _reveal(e, Field.notes),
          _reveal(e, kTotpFieldKey),
        ]);
      }
      for (final child in group.groups) {
        walk(child, path.isEmpty ? child.name : '$path/${child.name}');
      }
    }

    walk(root, '');
    return codec.encode(rows);
  }

  String _reveal(Entry e, String key) => e.fields[key]?.value.reveal() ?? '';
}
