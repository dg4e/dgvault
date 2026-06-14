// dgvault — KeePass field references & placeholder resolver.
//
// Implements the KeePass 2.x placeholder/field-reference syntax used in entry
// fields (most often URL / Notes), resolved at access time. Pure Dart, builds
// only on the core model — no crypto, no I/O — so it is fully unit-testable.
//
// Supported placeholders (case-insensitive token names):
//   {TITLE} {USERNAME} {PASSWORD} {URL} {NOTES} {UUID}   — fields of the entry
//   {S:Name}                                             — custom string field
//   {URL:RMVSCM|SCM|HOST|PORT|PATH|QUERY|USERINFO|USERNAME|PASSWORD}
//   {REF:W@S:Text}                                       — cross-entry reference
//
// Field codes (for {REF:W@S:Text}): T=Title U=UserName P=Password A=URL
//   N=Notes I=UUID O=other (any custom string, search side only).
//
// Resolution is recursive (a resolved value may itself contain placeholders),
// bounded by [maxDepth] with cycle protection so malformed/looping references
// cannot hang. Unknown tokens are left verbatim, matching KeePass behavior.

import '../model/entry.dart';
import '../model/field.dart';

/// Default recursion bound (KeePass uses ~20).
const int kDefaultMaxResolveDepth = 20;

class PlaceholderResolver {
  PlaceholderResolver({
    required Iterable<Entry> universe,
    this.maxDepth = kDefaultMaxResolveDepth,
  }) : _universe = List<Entry>.of(universe);

  /// All entries that {REF:...} may search across (typically the whole DB).
  final List<Entry> _universe;
  final int maxDepth;

  // Matches a single placeholder token with no nested braces. Placeholders do
  // not nest syntactically in KeePass — recursion happens through field values.
  static final RegExp _token = RegExp(r'\{([^{}]+)\}');

  /// Resolve all placeholders in [text] in the context of [context].
  String resolve(String text, Entry context) =>
      _resolve(text, context, 0, <String>{});

  /// Convenience: resolve a single field of [entry] (e.g. its URL).
  String? resolveField(Entry entry, String fieldKey) {
    final raw = entry.fields[fieldKey]?.value.reveal();
    if (raw == null) return null;
    return resolve(raw, entry);
  }

  String _resolve(String text, Entry context, int depth, Set<String> active) {
    if (depth >= maxDepth) return text;
    return text.replaceAllMapped(_token, (m) {
      final token = m.group(1)!;
      final replacement = _expand(token, context, depth, active);
      return replacement ?? m.group(0)!; // unknown → leave literal
    });
  }

  /// Returns the fully-resolved replacement for [token], or null when [token]
  /// is not a recognized placeholder.
  String? _expand(String token, Entry context, int depth, Set<String> active) {
    final upper = token.toUpperCase();

    // {REF:W@S:Text}
    if (upper.startsWith('REF:')) {
      return _expandRef(token.substring(4), context, depth, active);
    }

    // {S:CustomName}
    if (upper.startsWith('S:')) {
      final name = token.substring(2);
      final value = _customFieldValue(context, name);
      if (value == null) return null;
      return _resolve(value, context, depth + 1, active);
    }

    // {URL:COMPONENT}
    if (upper.startsWith('URL:')) {
      final urlRaw = _standardValue(context, 'A');
      return _expandUrlComponent(upper.substring(4), urlRaw ?? '');
    }

    // Standard single-field placeholders.
    final code = _standardCode(upper);
    if (code != null) {
      final value = _standardValue(context, code);
      if (value == null) return '';
      return _resolve(value, context, depth + 1, active);
    }

    return null;
  }

  String? _expandRef(String body, Entry context, int depth, Set<String> active) {
    final at = body.indexOf('@');
    if (at < 0) return null;
    final wanted = body.substring(0, at).trim().toUpperCase();
    final rest = body.substring(at + 1);
    final colon = rest.indexOf(':');
    if (colon < 0) return null;
    final searchCode = rest.substring(0, colon).trim().toUpperCase();
    final searchText = rest.substring(colon + 1);

    final match = _findEntry(searchCode, searchText);
    if (match == null) return null;

    // Cycle guard: keyed by the entry we are about to read from + wanted field.
    final key = '${match.uuid}#$wanted';
    if (active.contains(key)) return '';
    final nextActive = {...active, key};

    final value = wanted == 'I' ? match.uuid : _standardValue(match, wanted);
    if (value == null) return '';
    // Resolve the referenced value in the *referenced* entry's context.
    return _resolve(value, match, depth + 1, nextActive);
  }

  /// First entry whose [searchCode] field matches [text]. UUID (I) matches
  /// exactly; all others use case-insensitive substring search. 'O' searches
  /// every custom string field.
  Entry? _findEntry(String searchCode, String text) {
    for (final e in _universe) {
      if (searchCode == 'I') {
        if (e.uuid == text) return e;
        continue;
      }
      if (searchCode == 'O') {
        for (final f in e.fields.values) {
          if (f.isCustom &&
              f.value.reveal().toLowerCase().contains(text.toLowerCase())) {
            return e;
          }
        }
        continue;
      }
      final v = _standardValue(e, searchCode);
      if (v != null && v.toLowerCase().contains(text.toLowerCase())) {
        return e;
      }
    }
    return null;
  }

  /// Map a placeholder word ({TITLE}, etc.) to a single-letter field code.
  String? _standardCode(String upper) {
    switch (upper) {
      case 'TITLE':
        return 'T';
      case 'USERNAME':
        return 'U';
      case 'PASSWORD':
        return 'P';
      case 'URL':
        return 'A';
      case 'NOTES':
        return 'N';
      case 'UUID':
        return 'I';
    }
    return null;
  }

  String? _standardValue(Entry e, String code) {
    switch (code) {
      case 'T':
        return e.fields[Field.title]?.value.reveal();
      case 'U':
        return e.fields[Field.userName]?.value.reveal();
      case 'P':
        return e.fields[Field.password]?.value.reveal();
      case 'A':
        return e.fields[Field.url]?.value.reveal();
      case 'N':
        return e.fields[Field.notes]?.value.reveal();
      case 'I':
        return e.uuid;
    }
    return null;
  }

  String? _customFieldValue(Entry e, String name) {
    final lower = name.toLowerCase();
    for (final f in e.fields.values) {
      if (f.isCustom && f.key.toLowerCase() == lower) {
        return f.value.reveal();
      }
    }
    return null;
  }

  String _expandUrlComponent(String component, String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return '';
    switch (component) {
      case 'RMVSCM': // URL without scheme://
        if (!uri.hasScheme) return url;
        final s = '${uri.scheme}://';
        return url.startsWith(s) ? url.substring(s.length) : url;
      case 'SCM':
        return uri.scheme;
      case 'HOST':
        return uri.host;
      case 'PORT':
        return uri.hasPort ? '${uri.port}' : '';
      case 'PATH':
        return uri.path;
      case 'QUERY':
        return uri.hasQuery ? '?${uri.query}' : '';
      case 'USERINFO':
        return uri.userInfo;
      case 'USERNAME':
        final ui = uri.userInfo;
        if (ui.isEmpty) return '';
        final c = ui.indexOf(':');
        return c < 0 ? ui : ui.substring(0, c);
      case 'PASSWORD':
        final ui = uri.userInfo;
        final c = ui.indexOf(':');
        return c < 0 ? '' : ui.substring(c + 1);
    }
    return '';
  }
}
