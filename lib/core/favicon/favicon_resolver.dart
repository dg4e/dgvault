// dgvault — Favicon resolution (pure URL logic).
//
// Determines *which* URLs to try when fetching a site's favicon for an entry.
// Pure Dart — no network: the platform/data layer performs the actual HTTP GET
// and image decode. This isolates the testable logic (candidate derivation +
// HTML <link rel="icon"> parsing + relative→absolute resolution + size
// ordering) from the I/O.

/// A candidate favicon, with an optional declared pixel size (largest wins).
class FaviconCandidate {
  FaviconCandidate(this.url, {this.size});
  final Uri url;

  /// Largest dimension from a `sizes="WxH"` attribute, or null when unknown.
  final int? size;
}

class FaviconResolver {
  const FaviconResolver();

  /// Normalize [siteUrl] to an http(s) origin URI, or null if it isn't a web
  /// URL. A scheme-less input is assumed https.
  Uri? originOf(String siteUrl) {
    var u = Uri.tryParse(siteUrl.trim());
    if (u == null) return null;
    if (!u.hasScheme) {
      u = Uri.tryParse('https://${siteUrl.trim()}');
    } else if (u.scheme != 'http' && u.scheme != 'https') {
      return null; // not a web URL (ssh://, mailto:, ...)
    }
    if (u == null || u.host.isEmpty) return null;
    return Uri(
      scheme: u.scheme.isEmpty ? 'https' : u.scheme,
      host: u.host,
      port: u.hasPort ? u.port : null,
    );
  }

  /// Well-known fallback icon URLs for a site, most-likely first.
  List<Uri> defaultCandidates(String siteUrl) {
    final origin = originOf(siteUrl);
    if (origin == null) return const [];
    return [
      origin.replace(path: '/favicon.ico'),
      origin.replace(path: '/apple-touch-icon.png'),
      origin.replace(path: '/apple-touch-icon-precomposed.png'),
    ];
  }

  /// Parse `<link rel="...icon...">` elements from [html], resolving each href
  /// to an absolute URL against [pageUrl]. Sorted by declared size descending
  /// (sized icons before unsized), preserving document order within a tier.
  List<FaviconCandidate> parseLinkIcons(String html, String pageUrl) {
    final base = Uri.tryParse(pageUrl);
    final out = <FaviconCandidate>[];
    for (final m in _linkTag.allMatches(html)) {
      final tag = m.group(0)!;
      final rel = _attr(tag, 'rel');
      if (rel == null) continue;
      final relTokens = rel.toLowerCase().split(RegExp(r'\s+'));
      if (!relTokens.contains('icon') &&
          !relTokens.contains('shortcut') && // "shortcut icon"
          !relTokens.any((t) => t.endsWith('-icon') || t == 'mask-icon')) {
        continue;
      }
      final href = _attr(tag, 'href');
      if (href == null || href.isEmpty) continue;
      final resolved = _resolve(base, href);
      if (resolved == null) continue;
      out.add(FaviconCandidate(resolved, size: _largestSize(_attr(tag, 'sizes'))));
    }

    // Stable sort: sized (desc) first, then unsized in document order.
    final indexed = <MapEntry<int, FaviconCandidate>>[
      for (var i = 0; i < out.length; i++) MapEntry(i, out[i]),
    ];
    indexed.sort((a, b) {
      final sa = a.value.size, sb = b.value.size;
      if (sa == null && sb == null) return a.key.compareTo(b.key);
      if (sa == null) return 1;
      if (sb == null) return -1;
      if (sa != sb) return sb.compareTo(sa);
      return a.key.compareTo(b.key);
    });
    return [for (final e in indexed) e.value];
  }

  /// Full ordered candidate list: parsed `<link>` icons (when [html] is given)
  /// first, then the well-known fallbacks, de-duplicated.
  List<Uri> orderedCandidates({required String siteUrl, String? html}) {
    final seen = <String>{};
    final result = <Uri>[];
    void add(Uri u) {
      if (seen.add(u.toString())) result.add(u);
    }

    if (html != null) {
      for (final c in parseLinkIcons(html, siteUrl)) {
        add(c.url);
      }
    }
    for (final u in defaultCandidates(siteUrl)) {
      add(u);
    }
    return result;
  }

  // ---- helpers ----

  static final RegExp _linkTag =
      RegExp(r'<link\b[^>]*>', caseSensitive: false);

  String? _attr(String tag, String name) {
    final m = RegExp(
      '$name' r'''\s*=\s*("([^"]*)"|'([^']*)'|([^\s>]+))''',
      caseSensitive: false,
    ).firstMatch(tag);
    if (m == null) return null;
    return m.group(2) ?? m.group(3) ?? m.group(4);
  }

  int? _largestSize(String? sizes) {
    if (sizes == null) return null;
    var best = 0;
    for (final m in RegExp(r'(\d+)x(\d+)', caseSensitive: false).allMatches(sizes)) {
      final w = int.parse(m.group(1)!);
      final h = int.parse(m.group(2)!);
      final d = w > h ? w : h;
      if (d > best) best = d;
    }
    return best == 0 ? null : best;
  }

  Uri? _resolve(Uri? base, String href) {
    final h = Uri.tryParse(href.trim());
    if (h == null) return null;
    if (h.hasScheme) return h; // already absolute
    if (base == null) return null;
    return base.resolveUri(h);
  }
}
