import 'package:flutter_test/flutter_test.dart';
import 'package:dgvault/core/model/entry.dart';
import 'package:dgvault/core/model/field.dart';
import 'package:dgvault/core/model/protected_value.dart';
import 'package:dgvault/core/template/placeholder_resolver.dart';

Entry entry(
  String uuid, {
  String? title,
  String? username,
  String? password,
  String? url,
  String? notes,
  Map<String, String> custom = const {},
}) {
  final fields = <String, Field>{};
  void put(String key, String? v, {bool protected = false}) {
    if (v == null) return;
    fields[key] = Field(
      key: key,
      value: protected
          ? InMemoryProtectedValue(v)
          : InMemoryProtectedValue.plain(v),
    );
  }

  put(Field.title, title);
  put(Field.userName, username);
  put(Field.password, password, protected: true);
  put(Field.url, url);
  put(Field.notes, notes);
  custom.forEach((k, v) => put(k, v));
  return Entry(uuid: uuid, fields: fields);
}

void main() {
  group('PlaceholderResolver — standard placeholders', () {
    final e = entry('U1',
        title: 'Acme',
        username: 'alice',
        password: 's3cret',
        url: 'https://acme.example/login',
        notes: 'hello');
    final r = PlaceholderResolver(universe: [e]);

    test('expands each standard field', () {
      expect(r.resolve('{TITLE}', e), 'Acme');
      expect(r.resolve('{USERNAME}', e), 'alice');
      expect(r.resolve('{PASSWORD}', e), 's3cret');
      expect(r.resolve('{URL}', e), 'https://acme.example/login');
      expect(r.resolve('{NOTES}', e), 'hello');
      expect(r.resolve('{UUID}', e), 'U1');
    });

    test('is case-insensitive on token names', () {
      expect(r.resolve('{title} {UserName}', e), 'Acme alice');
    });

    test('mixes literal text and placeholders', () {
      expect(r.resolve('user=[{USERNAME}] host', e), 'user=[alice] host');
    });

    test('missing field resolves to empty string', () {
      final bare = entry('U2', title: 'x');
      final br = PlaceholderResolver(universe: [bare]);
      expect(br.resolve('[{PASSWORD}]', bare), '[]');
    });

    test('unknown token is left verbatim', () {
      expect(r.resolve('{NOPE} {TITLE}', e), '{NOPE} Acme');
    });
  });

  group('PlaceholderResolver — custom fields {S:Name}', () {
    final e = entry('C1', title: 't', custom: {'API_Key': 'abc123'});
    final r = PlaceholderResolver(universe: [e]);

    test('resolves custom string field, case-insensitive name', () {
      expect(r.resolve('{S:API_Key}', e), 'abc123');
      expect(r.resolve('{S:api_key}', e), 'abc123');
    });

    test('unknown custom field left verbatim', () {
      expect(r.resolve('{S:Missing}', e), '{S:Missing}');
    });
  });

  group('PlaceholderResolver — URL components', () {
    final e = entry('Ur', url: 'https://user:pw@host.example:8443/path?q=1');
    final r = PlaceholderResolver(universe: [e]);

    test('decomposes the URL', () {
      expect(r.resolve('{URL:SCM}', e), 'https');
      expect(r.resolve('{URL:HOST}', e), 'host.example');
      expect(r.resolve('{URL:PORT}', e), '8443');
      expect(r.resolve('{URL:PATH}', e), '/path');
      expect(r.resolve('{URL:QUERY}', e), '?q=1');
      expect(r.resolve('{URL:USERNAME}', e), 'user');
      expect(r.resolve('{URL:PASSWORD}', e), 'pw');
      expect(r.resolve('{URL:RMVSCM}', e), 'user:pw@host.example:8443/path?q=1');
    });

    test('port empty when absent', () {
      final e2 = entry('Ur2', url: 'https://host.example/');
      final r2 = PlaceholderResolver(universe: [e2]);
      expect(r2.resolve('{URL:PORT}', e2), '');
    });
  });

  group('PlaceholderResolver — field references {REF:W@S:Text}', () {
    final bank = entry('B1',
        title: 'My Bank', username: 'admin', password: 'hunter2');
    final mail = entry('M1', title: 'Mail', username: 'alice');
    final r = PlaceholderResolver(universe: [bank, mail]);

    test('REF P@U returns password of entry matched by username', () {
      expect(r.resolve('{REF:P@U:admin}', mail), 'hunter2');
    });

    test('REF U@T matches by title substring (case-insensitive)', () {
      expect(r.resolve('{REF:U@T:bank}', mail), 'admin');
    });

    test('REF T@I matches by exact UUID', () {
      expect(r.resolve('{REF:T@I:B1}', mail), 'My Bank');
      // wrong-case uuid does not match (uuids are case-sensitive)
      expect(r.resolve('{REF:T@I:b1}', mail), '');
    });

    test('REF with O search scans custom fields', () {
      final svc = entry('S1', title: 'Svc', custom: {'token': 'XYZ'});
      final rr = PlaceholderResolver(universe: [svc, mail]);
      expect(rr.resolve('{REF:T@O:XYZ}', mail), 'Svc');
    });

    test('no match resolves to empty string', () {
      expect(r.resolve('{REF:P@U:nobody}', mail), '');
    });
  });

  group('PlaceholderResolver — recursion & cycles', () {
    test('resolved value is itself resolved (recursion)', () {
      // username embeds {TITLE}
      final e = entry('R1', title: 'acme', username: 'svc-{TITLE}');
      final r = PlaceholderResolver(universe: [e]);
      expect(r.resolve('{USERNAME}', e), 'svc-acme');
    });

    test('cross-entry reference chains resolve', () {
      final a = entry('A', title: 'A', password: 'pa');
      // b's password references a's password
      final b = entry('B', title: 'B', password: '{REF:P@I:A}');
      final r = PlaceholderResolver(universe: [a, b]);
      expect(r.resolve('{REF:P@T:B}', a), 'pa');
    });

    test('self-referential cycle terminates without hang', () {
      final c = entry('C', title: 'C', notes: '{REF:N@I:C}');
      final r = PlaceholderResolver(universe: [c]);
      // Should resolve to empty (cycle guard) rather than loop forever.
      expect(r.resolve('{NOTES}', c), '');
    });

    test('depth bound stops runaway expansion', () {
      final d = entry('D', title: 'D', notes: '{NOTES}');
      final r = PlaceholderResolver(universe: [d], maxDepth: 5);
      // Terminates; result is bounded (not asserting exact value, just no hang).
      final out = r.resolve('{NOTES}', d);
      expect(out, isA<String>());
    });
  });

  group('PlaceholderResolver — resolveField helper', () {
    test('resolves placeholders within a chosen field', () {
      final e = entry('F1',
          title: 'Acme', url: 'https://{S:host}/app', custom: {'host': 'x.io'});
      final r = PlaceholderResolver(universe: [e]);
      expect(r.resolveField(e, Field.url), 'https://x.io/app');
    });
  });
}
