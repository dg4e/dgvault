import 'package:dgvault/core/core.dart';
import 'package:test/test.dart';

Entry _entry(String uuid, Map<String, String> fields,
    {Map<String, bool>? protect,}) {
  final map = <String, Field>{};
  fields.forEach((k, v) {
    final isProt = protect?[k] ?? (k == Field.password);
    map[k] = Field(
      key: k,
      value: InMemoryProtectedValue(v, isProtected: isProt),
    );
  });
  return Entry(uuid: uuid, fields: map);
}

Database _db(List<Entry> entries) {
  final root = Group(uuid: 'root', name: 'Root', entries: entries);
  return Database(meta: DatabaseMeta(name: 'T'), root: root);
}

void main() {
  group('local placeholders', () {
    test('substitutes standard fields of the context entry', () {
      final e = _entry('u1', {
        Field.title: 'GitHub',
        Field.userName: 'octocat',
        Field.password: 's3cret',
        Field.url: 'https://github.com',
      });
      final r = PlaceholderResolver(_db([e]));
      expect(r.resolve('{USERNAME}@{TITLE}', e), 'octocat@GitHub');
      expect(r.resolve('login {USERNAME} / {PASSWORD}', e),
          'login octocat / s3cret',);
      expect(r.resolve('{UUID}', e), 'u1');
    });

    test('leaves unknown placeholders untouched', () {
      final e = _entry('u1', {Field.title: 'X'});
      final r = PlaceholderResolver(_db([e]));
      expect(r.resolve('{DT_YEAR}-{TITLE}', e), '{DT_YEAR}-X');
    });
  });

  group('custom string placeholders', () {
    test('resolves {S:Name} from custom fields', () {
      final e = _entry('u1', {
        Field.title: 'API',
        'Token': 'abc123',
      }, protect: {'Token': true},);
      final r = PlaceholderResolver(_db([e]));
      expect(r.resolve('Bearer {S:Token}', e), 'Bearer abc123');
      expect(r.resolve('{S:Missing}', e), '{S:Missing}');
    });
  });

  group('field references {REF:W@S:text}', () {
    test('resolves password by UUID reference', () {
      final target = _entry('AAAA1111', {
        Field.title: 'Shared',
        Field.password: 'shared-pw',
      });
      final context = _entry('u2', {Field.title: 'Uses shared'});
      final r = PlaceholderResolver(_db([target, context]));
      expect(r.resolve('{REF:P@I:AAAA1111}', context), 'shared-pw');
    });

    test('resolves username by title substring (case-insensitive)', () {
      final target = _entry('t1', {
        Field.title: 'Mail Server',
        Field.userName: 'admin',
      });
      final context = _entry('c1', {Field.title: 'ctx'});
      final r = PlaceholderResolver(_db([target, context]));
      expect(r.resolve('{REF:U@T:mail}', context), 'admin');
    });

    test('unresolvable reference is left verbatim', () {
      final e = _entry('e1', {Field.title: 'X'});
      final r = PlaceholderResolver(_db([e]));
      expect(r.resolve('{REF:P@I:DOESNOTEXIST}', e), '{REF:P@I:DOESNOTEXIST}');
    });
  });

  group('recursion & cycle safety', () {
    test('recursively expands a reference whose value has a placeholder', () {
      final a = _entry('A1', {
        Field.title: 'A',
        Field.password: '{REF:P@I:B1}',
      });
      final b = _entry('B1', {
        Field.title: 'B',
        Field.password: 'final-secret',
      });
      final r = PlaceholderResolver(_db([a, b]));
      expect(r.resolve('{PASSWORD}', a), 'final-secret');
    });

    test('terminates on a reference cycle instead of looping', () {
      final a = _entry('A1', {Field.password: '{REF:P@I:B1}'});
      final b = _entry('B1', {Field.password: '{REF:P@I:A1}'});
      final r = PlaceholderResolver(_db([a, b]));
      // Should return within maxDepth without throwing; value is unresolved.
      final out = r.resolve('{PASSWORD}', a, maxDepth: 5);
      expect(out, contains('{REF:P@I:'));
    });
  });

  group('URL component placeholders {URL:...}', () {
    Entry urlEntry(String url) => _entry('u1', {Field.url: url});

    test('decomposes a full URL', () {
      final e = urlEntry('https://user:pw@host.example:8443/path?q=1');
      final r = PlaceholderResolver(_db([e]));
      expect(r.resolve('{URL:SCM}', e), 'https');
      expect(r.resolve('{URL:HOST}', e), 'host.example');
      expect(r.resolve('{URL:PORT}', e), '8443');
      expect(r.resolve('{URL:PATH}', e), '/path');
      expect(r.resolve('{URL:QUERY}', e), '?q=1');
      expect(r.resolve('{URL:USERNAME}', e), 'user');
      expect(r.resolve('{URL:PASSWORD}', e), 'pw');
      expect(r.resolve('{URL:USERINFO}', e), 'user:pw');
      expect(r.resolve('{URL:RMVSCM}', e),
          'user:pw@host.example:8443/path?q=1',);
    });

    test('{URL} (no component) is unaffected by the component pass', () {
      final e = urlEntry('https://host.example/');
      final r = PlaceholderResolver(_db([e]));
      expect(r.resolve('{URL}', e), 'https://host.example/');
      expect(r.resolve('{URL:PORT}', e), ''); // absent port → empty
    });

    test('unknown component is left verbatim', () {
      final e = urlEntry('https://host.example/');
      final r = PlaceholderResolver(_db([e]));
      expect(r.resolve('{URL:BOGUS}', e), '{URL:BOGUS}');
    });
  });
}
