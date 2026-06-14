import 'package:dgvault/core/favicon/favicon_resolver.dart';
import 'package:test/test.dart';

void main() {
  const r = FaviconResolver();

  group('originOf / defaultCandidates', () {
    test('derives well-known candidates from a full URL', () {
      final c = r.defaultCandidates('https://example.com/login?x=1');
      expect(c.map((u) => u.toString()), [
        'https://example.com/favicon.ico',
        'https://example.com/apple-touch-icon.png',
        'https://example.com/apple-touch-icon-precomposed.png',
      ]);
    });

    test('scheme-less input is assumed https', () {
      expect(r.originOf('example.com').toString(), 'https://example.com');
    });

    test('preserves explicit port', () {
      expect(r.originOf('http://host.local:8080/x').toString(),
          'http://host.local:8080');
    });

    test('non-web schemes yield no candidates', () {
      expect(r.originOf('ssh://host'), isNull);
      expect(r.defaultCandidates('mailto:a@b.com'), isEmpty);
    });
  });

  group('parseLinkIcons', () {
    const html = '''
      <head>
        <link rel="icon" href="/favicon-16.png" sizes="16x16">
        <link rel="apple-touch-icon" href="https://cdn.example.com/touch.png" sizes="180x180">
        <link rel="stylesheet" href="/style.css">
        <link rel="shortcut icon" href="favrel.ico">
      </head>''';

    test('extracts only icon links, resolves to absolute, orders by size', () {
      final icons = r.parseLinkIcons(html, 'https://example.com/page');
      final urls = icons.map((c) => c.url.toString()).toList();
      // 180x180 first, then 16x16, then the unsized shortcut icon.
      expect(urls, [
        'https://cdn.example.com/touch.png',
        'https://example.com/favicon-16.png',
        'https://example.com/favrel.ico', // relative resolved against page
      ]);
      expect(icons.first.size, 180);
      expect(icons.last.size, isNull);
    });

    test('ignores non-icon rel (stylesheet)', () {
      final icons = r.parseLinkIcons(html, 'https://example.com/');
      expect(icons.any((c) => c.url.toString().endsWith('style.css')), isFalse);
    });
  });

  group('orderedCandidates', () {
    test('parsed link icons precede well-known fallbacks, de-duplicated', () {
      const html = '<link rel="icon" href="/favicon.ico" sizes="32x32">';
      final c = r.orderedCandidates(siteUrl: 'https://example.com', html: html);
      expect(c.first.toString(), 'https://example.com/favicon.ico');
      // /favicon.ico from defaults is de-duplicated against the parsed one.
      final favCount =
          c.where((u) => u.toString() == 'https://example.com/favicon.ico').length;
      expect(favCount, 1);
      // fallbacks still present
      expect(c.any((u) => u.path == '/apple-touch-icon.png'), isTrue);
    });

    test('no html → just the fallbacks', () {
      final c = r.orderedCandidates(siteUrl: 'https://example.com');
      expect(c.length, 3);
    });
  });
}
