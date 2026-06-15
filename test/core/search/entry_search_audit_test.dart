// Critic-owned adversarial audit for all-fields search — security edges.
//
// Composer's suite covers field coverage, password-excluded-by-default,
// searchProtected opt-in, AND terms, case sensitivity, and tree traversal.
// These add the subtle protection edges: a protected custom field's NAME stays
// searchable while its VALUE is gated, and an AND term that only exists in a
// protected field must not leak a match by default.
//
// Toolchain not installed here; assertions traced against source by hand
// (see reviews/Critic-round-10.md).

import 'package:dgvault/core/core.dart';
import 'package:test/test.dart';

Entry _e(
  String uuid, {
  String? title,
  String? username,
  String? password,
  Map<String, String>? custom,
  Map<String, String>? protectedCustom,
}) {
  final fields = <String, Field>{};
  void put(String k, String? v, {bool prot = false}) {
    if (v == null) return;
    fields[k] = Field(key: k, value: InMemoryProtectedValue(v, isProtected: prot));
  }

  put(Field.title, title);
  put(Field.userName, username);
  put(Field.password, password, prot: true);
  custom?.forEach((k, v) => put(k, v));
  protectedCustom?.forEach((k, v) => put(k, v, prot: true));
  return Entry(uuid: uuid, fields: fields);
}

void main() {
  group('protected custom field — name searchable, value gated', () {
    final e = _e('x', title: 'Bank', protectedCustom: {'RecoveryKey': 'ZZZ-SECRET'});

    test('the field NAME matches by default (names are not secret)', () {
      expect(EntrySearch.search([e], const SearchQuery('RecoveryKey')).length, 1);
    });

    test('the protected VALUE does NOT match by default', () {
      expect(EntrySearch.search([e], const SearchQuery('ZZZ-SECRET')), isEmpty,
          reason: 'protected custom value must be excluded without opt-in',);
    });

    test('the protected VALUE matches with searchProtected', () {
      expect(
        EntrySearch.search([e], const SearchQuery('ZZZ-SECRET', searchProtected: true)).length,
        1,
      );
    });
  });

  group('AND terms × protection', () {
    final e = _e('y', title: 'GitHub', password: 'octocat-pw');

    test('a term that exists only in the password blocks the match by default', () {
      // 'GitHub' is in title, but 'octocat' lives only in the protected password.
      expect(EntrySearch.search([e], const SearchQuery('GitHub octocat')), isEmpty,
          reason: 'default search must not satisfy an AND term from a secret field',);
    });

    test('with allFields + searchProtected the same query matches', () {
      final r = EntrySearch.search(
        [e],
        const SearchQuery('GitHub octocat',
            fields: SearchQuery.allFields, searchProtected: true,),
      );
      expect(r.length, 1);
      expect(r.single.matchedFields, containsAll(<SearchField>{
        SearchField.title,
        SearchField.password,
      }),);
    });
  });
}
