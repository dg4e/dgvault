// dgvault — KeePass field-reference & placeholder resolver.
//
// Pure Dart. Resolves the subset of KeePass placeholders that operate purely on
// database contents (no environment / date-time / spawn placeholders, which are
// platform concerns and left untouched):
//
//   Local fields:   {TITLE} {USERNAME} {PASSWORD} {URL} {NOTES} {UUID}
//   Custom strings: {S:Name}
//   References:     {REF:<wanted>@<searchin>:<text>}
//                   where <wanted>/<searchin> ∈ {T,U,P,A,N,I,O}
//                   (Title, UserName, Password, URL, Notes, UUID, Other)
//
// Resolution is recursive (a referenced value may itself contain placeholders)
// with a depth guard so reference cycles terminate instead of looping forever.
// Unknown placeholders are left verbatim, matching KeePass behaviour.

import '../model/database.dart';
import '../model/entry.dart';
import '../model/field.dart';
import '../model/group.dart';

/// Maps a KeePass field code letter to a [Field] key (or the synthetic UUID).
class _FieldCode {
  static const Map<String, String> _toKey = <String, String>{
    'T': Field.title,
    'U': Field.userName,
    'P': Field.password,
    'A': Field.url,
    'N': Field.notes,
  };

  /// Reads the value addressed by a single-letter code from [entry].
  /// `I` → UUID, `O` → first custom string, otherwise a standard field.
  static String? read(Entry entry, String code) {
    final upper = code.toUpperCase();
    if (upper == 'I') return entry.uuid;
    if (upper == 'O') {
      for (final f in entry.fields.values) {
        if (f.isCustom) return f.value.reveal();
      }
      return null;
    }
    final key = _toKey[upper];
    if (key == null) return null;
    return entry.fields[key]?.value.reveal();
  }

  static bool isValid(String code) {
    final upper = code.toUpperCase();
    return upper == 'I' || upper == 'O' || _toKey.containsKey(upper);
  }
}

class PlaceholderResolver {
  PlaceholderResolver(this.database);

  final Database database;

  // {REF:W@S:text} — letters captured separately so we can validate them.
  static final RegExp _refPattern = RegExp(
    r'\{REF:([A-Za-z])@([A-Za-z]):([^}]*)\}',
    caseSensitive: false,
  );

  // {S:Custom Field Name}
  static final RegExp _customPattern = RegExp(r'\{S:([^}]+)\}');

  // {TITLE} etc. — only the known local field placeholders.
  static final RegExp _localPattern = RegExp(
    r'\{(TITLE|USERNAME|PASSWORD|URL|NOTES|UUID)\}',
    caseSensitive: false,
  );

  /// Fully resolves [input] in the scope of [context].
  ///
  /// [maxDepth] bounds recursive expansion; on exhaustion the partially
  /// resolved string is returned rather than throwing, so a malicious or
  /// accidental reference cycle degrades gracefully.
  String resolve(String input, Entry context, {int maxDepth = 10}) {
    var current = input;
    for (var depth = 0; depth < maxDepth; depth++) {
      final next = _resolveOnce(current, context);
      if (next == current) return next; // fixed point reached
      current = next;
    }
    return current;
  }

  String _resolveOnce(String input, Entry context) {
    var out = input;
    out = out.replaceAllMapped(_refPattern, (m) {
      final wanted = m.group(1)!;
      final searchIn = m.group(2)!;
      final text = m.group(3)!;
      if (!_FieldCode.isValid(wanted) || !_FieldCode.isValid(searchIn)) {
        return m.group(0)!; // leave malformed refs untouched
      }
      final target = _findEntry(searchIn, text);
      if (target == null) return m.group(0)!;
      return _FieldCode.read(target, wanted) ?? '';
    });
    out = out.replaceAllMapped(_localPattern, (m) {
      final name = m.group(1)!.toUpperCase();
      final value = _localValue(context, name);
      return value ?? m.group(0)!;
    });
    out = out.replaceAllMapped(_customPattern, (m) {
      final name = m.group(1)!;
      final field = context.fields[name];
      return field != null ? field.value.reveal() : m.group(0)!;
    });
    return out;
  }

  String? _localValue(Entry entry, String placeholder) {
    switch (placeholder) {
      case 'TITLE':
        return _FieldCode.read(entry, 'T');
      case 'USERNAME':
        return _FieldCode.read(entry, 'U');
      case 'PASSWORD':
        return _FieldCode.read(entry, 'P');
      case 'URL':
        return _FieldCode.read(entry, 'A');
      case 'NOTES':
        return _FieldCode.read(entry, 'N');
      case 'UUID':
        return entry.uuid;
      default:
        return null;
    }
  }

  /// Finds the first entry whose [searchIn] field matches [text]. The UUID code
  /// (`I`) requires an exact, case-insensitive match; all other codes use a
  /// case-insensitive substring match, mirroring KeePass.
  Entry? _findEntry(String searchIn, String text) {
    final needle = text.toLowerCase();
    final byUuid = searchIn.toUpperCase() == 'I';
    for (final entry in _allEntries(database.root)) {
      final value = _FieldCode.read(entry, searchIn);
      if (value == null) continue;
      final hay = value.toLowerCase();
      if (byUuid ? hay == needle : hay.contains(needle)) {
        return entry;
      }
    }
    return null;
  }

  Iterable<Entry> _allEntries(Group group) => group.allEntries;
}
