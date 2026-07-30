// dgvault — powerful all-fields search.
//
// Pure Dart query engine over the decrypted in-memory model. Searches across
// title, username, URL, notes, tags, and custom fields. Protected values
// (the password and any protected custom string) are excluded by default and
// only searched when [SearchQuery.searchProtected] is set — mirroring KeePass,
// where searching secret strings is an explicit opt-in.
//
// Multiple whitespace-separated terms are AND-combined: an entry matches only
// if every term is found in at least one in-scope field (terms may match
// different fields). Matching is substring-based and case-insensitive by
// default.

import '../model/entry.dart';
import '../model/field.dart';
import '../model/group.dart';

/// Logical field groups a query can target.
enum SearchField { title, username, url, notes, tags, customFields, password }

class SearchQuery {
  const SearchQuery(
    this.text, {
    this.fields = standardFields,
    this.caseSensitive = false,
    this.searchProtected = false,
  });

  /// Raw query string; split into AND-terms on whitespace.
  final String text;

  /// Fields to search. Defaults to all non-secret fields.
  final Set<SearchField> fields;

  final bool caseSensitive;

  /// When true, protected values (password / protected custom strings) are
  /// included in the search. Off by default.
  final bool searchProtected;

  /// All non-secret fields (KeePass default scope).
  static const Set<SearchField> standardFields = {
    SearchField.title,
    SearchField.username,
    SearchField.url,
    SearchField.notes,
    SearchField.tags,
    SearchField.customFields,
  };

  /// Every field, including protected ones (used with [searchProtected]).
  static const Set<SearchField> allFields = {
    ...standardFields,
    SearchField.password,
  };

  List<String> get terms =>
      text.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
}

class SearchMatch {
  SearchMatch(this.entry, this.matchedFields);

  final Entry entry;

  /// The in-scope fields in which at least one query term was found.
  final Set<SearchField> matchedFields;
}

class EntrySearch {
  /// Searches every entry in [group]'s subtree. A blank query returns all
  /// entries (so a cleared search box shows everything) with no matched fields.
  ///
  /// Groups whose UUID is in [nonSearchable] contribute none of their own
  /// entries (e.g. the Recycle Bin or an archive folder marked
  /// `EnableSearching=false`), but the walk still descends into their children
  /// so a re-enabled subfolder is still found.
  static List<SearchMatch> searchGroup(
    Group group,
    SearchQuery query, {
    Set<String> nonSearchable = const {},
  }) =>
      search(
        nonSearchable.isEmpty
            ? group.allEntries
            : group.searchableEntries(nonSearchable),
        query,
      );

  static List<SearchMatch> search(Iterable<Entry> entries, SearchQuery query) {
    final terms = query.terms;
    if (terms.isEmpty) {
      return [for (final e in entries) SearchMatch(e, <SearchField>{})];
    }
    final needles =
        query.caseSensitive ? terms : terms.map((t) => t.toLowerCase()).toList();

    final results = <SearchMatch>[];
    for (final entry in entries) {
      final values = _searchableValues(entry, query);
      final matchedFields = <SearchField>{};
      var allTermsMatched = true;

      for (var i = 0; i < needles.length; i++) {
        final needle = needles[i];
        var termMatched = false;
        for (final v in values) {
          final hay = query.caseSensitive ? v.text : v.text.toLowerCase();
          if (hay.contains(needle)) {
            termMatched = true;
            matchedFields.add(v.field);
          }
        }
        if (!termMatched) {
          allTermsMatched = false;
          break;
        }
      }

      if (allTermsMatched) {
        results.add(SearchMatch(entry, matchedFields));
      }
    }
    return results;
  }

  /// Collects the (field, text) pairs that are in scope for [query].
  static List<_FieldText> _searchableValues(Entry entry, SearchQuery query) {
    final out = <_FieldText>[];
    void addStd(SearchField field, String key) {
      final v = entry.fields[key]?.value.reveal();
      if (v != null && v.isNotEmpty) out.add(_FieldText(field, v));
    }

    for (final field in query.fields) {
      switch (field) {
        case SearchField.title:
          addStd(field, Field.title);
        case SearchField.username:
          addStd(field, Field.userName);
        case SearchField.url:
          addStd(field, Field.url);
        case SearchField.notes:
          addStd(field, Field.notes);
        case SearchField.tags:
          if (entry.tags.isNotEmpty) {
            out.add(_FieldText(field, entry.tags.join(' ')));
          }
        case SearchField.password:
          if (query.searchProtected) addStd(field, Field.password);
        case SearchField.customFields:
          for (final f in entry.fields.values) {
            if (!f.isCustom) continue;
            // The field NAME is not secret, so it is always searchable.
            out.add(_FieldText(field, f.key));
            // The VALUE is searched only when non-protected, or opted-in.
            if (f.isProtected && !query.searchProtected) continue;
            final v = f.value.reveal();
            if (v.isNotEmpty) out.add(_FieldText(field, v));
          }
      }
    }
    return out;
  }
}

class _FieldText {
  _FieldText(this.field, this.text);
  final SearchField field;
  final String text;
}
