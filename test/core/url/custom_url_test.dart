import 'package:dgvault/core/core.dart';
import 'package:test/test.dart';

Entry _entry(String? url, {Map<String, String>? custom}) {
  final fields = <String, Field>{};
  if (url != null) {
    fields[Field.url] =
        Field(key: Field.url, value: InMemoryProtectedValue.plain(url));
  }
  custom?.forEach((k, v) {
    fields[k] = Field(key: k, value: InMemoryProtectedValue.plain(v));
  });
  return Entry(uuid: 'e1', fields: fields);
}

PlaceholderResolver _resolverFor(Entry e) =>
    PlaceholderResolver(Database(
      meta: DatabaseMeta(name: 'T'),
      root: Group(uuid: 'r', name: 'Root', entries: [e]),
    ),);

void main() {
  const handler = CustomUrlHandler();

  group('scheme classification + open policy', () {
    void check(String url, UrlScheme scheme, UrlOpenPolicy policy) {
      final r = handler.resolve(_entry(url));
      expect(r.scheme, scheme, reason: url);
      expect(r.policy, policy, reason: url);
    }

    test('web + remote schemes auto-open', () {
      check('https://example.com', UrlScheme.https, UrlOpenPolicy.autoOpen);
      check('http://example.com', UrlScheme.http, UrlOpenPolicy.autoOpen);
      check('ssh://host', UrlScheme.ssh, UrlOpenPolicy.autoOpen);
      check('mailto:a@b.com', UrlScheme.mailto, UrlOpenPolicy.autoOpen);
    });

    test('bare host (no scheme) is treated as implicit https', () {
      check('example.com', UrlScheme.https, UrlOpenPolicy.autoOpen);
      check('example.com:8080/path', UrlScheme.https, UrlOpenPolicy.autoOpen);
    });

    test('command / file / unknown require confirmation', () {
      check('cmd://run a thing', UrlScheme.command, UrlOpenPolicy.confirmFirst);
      check('file:///etc/hosts', UrlScheme.file, UrlOpenPolicy.confirmFirst);
      check('weird://x', UrlScheme.unknown, UrlOpenPolicy.confirmFirst);
    });

    test('script/data URIs are blocked', () {
      expect(handler.resolve(_entry('javascript:alert(1)')).policy,
          UrlOpenPolicy.blocked,);
      expect(handler.resolve(_entry('data:text/html,<x>')).policy,
          UrlOpenPolicy.blocked,);
      expect(CustomUrlHandler.isBlockedScheme('vbscript:msgbox'), isTrue);
    });

    test('empty URL is empty and blocked', () {
      final r = handler.resolve(_entry(null));
      expect(r.isEmpty, isTrue);
      expect(r.scheme, UrlScheme.none);
      expect(r.policy, UrlOpenPolicy.blocked);
    });
  });

  group('override precedence', () {
    test('override replaces the URL field', () {
      final r = handler.resolve(_entry('https://orig.com'),
          override: 'https://override.com',);
      expect(r.value, 'https://override.com');
    });

    test('{URL} token embeds the original URL inside the override', () {
      final r = handler.resolve(_entry('https://target.com'),
          override: 'cmd://open {URL}',);
      expect(r.value, 'cmd://open https://target.com');
      expect(r.scheme, UrlScheme.command);
      expect(r.policy, UrlOpenPolicy.confirmFirst);
    });

    test('empty override falls back to the URL field', () {
      final r = handler.resolve(_entry('https://orig.com'), override: '');
      expect(r.value, 'https://orig.com');
    });
  });

  group('placeholder resolution', () {
    test('expands {S:custom} placeholders against the entry', () {
      final e = _entry('https://{S:host}/login', custom: {'host': 'example.org'});
      final r = handler.resolve(e, resolver: _resolverFor(e));
      expect(r.value, 'https://example.org/login');
      expect(r.policy, UrlOpenPolicy.autoOpen);
    });

    test('without a resolver, placeholders are left intact', () {
      final e = _entry('https://{S:host}/login', custom: {'host': 'example.org'});
      expect(handler.resolve(e).value, 'https://{S:host}/login');
    });
  });
}
