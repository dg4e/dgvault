import 'package:dgvault/core/core.dart';
import 'package:test/test.dart';

Entry _e(
  String uuid, {
  String? title,
  String? user,
  String? url,
  String? notes,
  String? password,
  List<String>? tags,
  Map<String, String>? custom,
  Map<String, String>? protectedCustom,
}) {
  final fields = <String, Field>{};
  void put(String key, String? v, {bool prot = false}) {
    if (v != null) {
      fields[key] = Field(key: key, value: InMemoryProtectedValue(v, isProtected: prot));
    }
  }

  put(Field.title, title);
  put(Field.userName, user);
  put(Field.url, url);
  put(Field.notes, notes);
  put(Field.password, password, prot: true);
  custom?.forEach((k, v) => put(k, v));
  protectedCustom?.forEach((k, v) => put(k, v, prot: true));
  return Entry(uuid: uuid, fields: fields, tags: tags);
}

Group _group(List<Entry> entries) =>
    Group(uuid: 'r', name: 'Root', entries: entries);

void main() {
  group('field coverage', () {
    final entries = [
      _e('a', title: 'GitHub', user: 'octocat', url: 'https://github.com'),
      _e('b', notes: 'recovery codes for bank', tags: ['finance', 'bank']),
      _e('c', title: 'Mail', custom: {'Recovery Email': 'help@example.com'}),
    ];

    test('matches across title/username/url', () {
      expect(EntrySearch.search(entries, const SearchQuery('octocat'))
          .map((m) => m.entry.uuid), ['a'],);
      expect(EntrySearch.search(entries, const SearchQuery('github.com'))
          .map((m) => m.entry.uuid), ['a'],);
    });

    test('matches notes and tags', () {
      expect(EntrySearch.search(entries, const SearchQuery('recovery'))
          .map((m) => m.entry.uuid).toSet(), {'b', 'c'},);
      expect(EntrySearch.search(entries, const SearchQuery('finance'))
          .map((m) => m.entry.uuid), ['b'],);
    });

    test('matches custom fields and reports matched field', () {
      final r = EntrySearch.search(entries, const SearchQuery('example.com'));
      expect(r.map((m) => m.entry.uuid), ['c']);
      expect(r.single.matchedFields, contains(SearchField.customFields));
    });
  });

  group('protected values', () {
    final entries = [
      _e('a', title: 'Acct', password: 'hunter2-secret'),
      _e('b', title: 'Tok', protectedCustom: {'TOTP': 'JBSWY3DP'}),
    ];

    test('passwords are NOT searched by default', () {
      expect(EntrySearch.search(entries, const SearchQuery('hunter2')), isEmpty);
    });

    test('searchProtected opts into password + protected custom fields', () {
      final pw = EntrySearch.search(
        entries,
        const SearchQuery('hunter2',
            fields: SearchQuery.allFields, searchProtected: true,),
      );
      expect(pw.map((m) => m.entry.uuid), ['a']);

      final totp = EntrySearch.search(
        entries,
        const SearchQuery('JBSWY3DP', searchProtected: true),
      );
      expect(totp.map((m) => m.entry.uuid), ['b']);
    });
  });

  group('multi-term AND and options', () {
    final entries = [
      _e('a', title: 'AWS Production', user: 'admin'),
      _e('b', title: 'AWS Staging', user: 'admin'),
    ];

    test('all terms must match (across any fields)', () {
      expect(EntrySearch.search(entries, const SearchQuery('aws production'))
          .map((m) => m.entry.uuid), ['a'],);
      expect(EntrySearch.search(entries, const SearchQuery('aws admin'))
          .map((m) => m.entry.uuid).toSet(), {'a', 'b'},);
      expect(EntrySearch.search(entries, const SearchQuery('aws nonexistent')),
          isEmpty,);
    });

    test('case sensitivity is configurable', () {
      expect(EntrySearch.search(entries, const SearchQuery('aws')).length, 2);
      expect(
        EntrySearch.search(
            entries, const SearchQuery('aws', caseSensitive: true),),
        isEmpty,
      );
    });

    test('blank query returns all entries', () {
      expect(EntrySearch.search(entries, const SearchQuery('   ')).length, 2);
    });
  });

  group('searchGroup traverses the tree', () {
    test('finds entries in nested groups', () {
      final child = _group([_e('deep', title: 'Buried Treasure')]);
      final root = Group(uuid: 'root', name: 'Root', groups: [child]);
      final r = EntrySearch.searchGroup(root, const SearchQuery('treasure'));
      expect(r.map((m) => m.entry.uuid), ['deep']);
    });
  });

  group('non-searchable groups (Recycle Bin / Backup) stay out of results', () {
    // A live "gmail" plus an archived copy in a folder marked non-searchable.
    final backup = Group(
      uuid: 'backup',
      name: 'Backup',
      entries: [_e('archived', title: 'gmail')],
    );
    final root = Group(
      uuid: 'root',
      name: 'Root',
      entries: [_e('live', title: 'gmail')],
      groups: [backup],
    );

    test('without exclusion, the archived copy leaks into search', () {
      final r = EntrySearch.searchGroup(root, const SearchQuery('gmail'));
      expect(r.map((m) => m.entry.uuid).toSet(), {'live', 'archived'});
    });

    test('excluding the folder returns only the live entry', () {
      final r = EntrySearch.searchGroup(
        root,
        const SearchQuery('gmail'),
        nonSearchable: {'backup'},
      );
      expect(r.map((m) => m.entry.uuid), ['live']);
    });

    test('a blank query also skips the excluded folder', () {
      final r = EntrySearch.searchGroup(
        root,
        const SearchQuery(''),
        nonSearchable: {'backup'},
      );
      expect(r.map((m) => m.entry.uuid), ['live']);
    });

    test('a re-enabled subfolder under an excluded parent is still reached',
        () {
      // Excluded parent, but a child NOT in the set contributes its entries.
      final child = _group([_e('kept', title: 'gmail')]);
      final parent = Group(
        uuid: 'parent',
        name: 'Archive',
        entries: [_e('hidden', title: 'gmail')],
        groups: [child],
      );
      final r = EntrySearch.searchGroup(
        Group(uuid: 'root', name: 'Root', groups: [parent]),
        const SearchQuery('gmail'),
        nonSearchable: {'parent'}, // 'r' (child) not excluded
      );
      expect(r.map((m) => m.entry.uuid), ['kept']);
    });
  });
}
