// dgvault — custom URL handling.
//
// Resolves the URL dgvault should actually open for an entry and decides how
// safe it is to open. KeePass-faithful behaviour:
//   • An optional URL override replaces the entry's URL field; the override may
//     embed the original via the `{URL}` token (e.g. `cmd://ssh {URL}`).
//   • Field-reference / placeholder tokens ({USERNAME}, {S:Name}, …) are
//     expanded via the shared [PlaceholderResolver] when one is supplied.
//   • The resulting scheme is classified and assigned an open policy so the UI
//     never silently launches a dangerous handler (javascript:, data:) and
//     always confirms before running a `cmd://` command or opening a file.
//
// Pure Dart, model-only.

import '../model/entry.dart';
import '../model/field.dart';
import '../template/placeholder_resolver.dart';

enum UrlScheme {
  http,
  https,
  ssh,
  sftp,
  ftp,
  mailto,
  file,
  command, // KeePass cmd:// — runs a command line
  otpauth,
  unknown,
  none,
}

/// How the UI should treat the resolved URL.
enum UrlOpenPolicy {
  /// Safe to open directly (web/mail/remote-shell schemes).
  autoOpen,

  /// Open only after explicit user confirmation (commands, files, unknown).
  confirmFirst,

  /// Never open automatically (script/data URIs — injection risk).
  blocked,
}

class ResolvedUrl {
  const ResolvedUrl({
    required this.value,
    required this.scheme,
    required this.policy,
  });

  /// The final URL string after override + placeholder resolution.
  final String value;
  final UrlScheme scheme;
  final UrlOpenPolicy policy;

  bool get isEmpty => value.isEmpty;
}

class CustomUrlHandler {
  const CustomUrlHandler();

  static const Set<String> _blockedSchemes = {
    'javascript',
    'data',
    'vbscript',
  };
  static const Set<String> _autoOpenSchemes = {
    'http',
    'https',
    'mailto',
    'ssh',
    'sftp',
    'ftp',
  };

  /// Resolves the effective URL for [entry].
  ///
  /// [override] (if non-empty) replaces the URL field; `{URL}` inside it is
  /// substituted with the original URL field first. [resolver] expands the
  /// remaining KeePass placeholders against [entry]; when null, tokens are left
  /// as-is.
  ResolvedUrl resolve(
    Entry entry, {
    String? override,
    PlaceholderResolver? resolver,
  }) {
    final base = entry.fields[Field.url]?.value.reveal() ?? '';

    var effective = (override != null && override.isNotEmpty)
        ? override.replaceAll('{URL}', base)
        : base;

    if (resolver != null && effective.isNotEmpty) {
      effective = resolver.resolve(effective, entry);
    }
    effective = effective.trim();

    final scheme = _classify(effective);
    // Script/data URIs are hard-blocked regardless of how they classify.
    final policy = isBlockedScheme(effective)
        ? UrlOpenPolicy.blocked
        : _policyFor(scheme);
    return ResolvedUrl(value: effective, scheme: scheme, policy: policy);
  }

  UrlScheme _classify(String url) {
    if (url.isEmpty) return UrlScheme.none;
    final schemeName = _schemeName(url);
    if (schemeName == null) {
      // No scheme → treat as an implicit https web link (KeePass/browser behaviour).
      return UrlScheme.https;
    }
    switch (schemeName) {
      case 'http':
        return UrlScheme.http;
      case 'https':
        return UrlScheme.https;
      case 'ssh':
        return UrlScheme.ssh;
      case 'sftp':
        return UrlScheme.sftp;
      case 'ftp':
        return UrlScheme.ftp;
      case 'mailto':
        return UrlScheme.mailto;
      case 'file':
        return UrlScheme.file;
      case 'cmd':
        return UrlScheme.command;
      case 'otpauth':
        return UrlScheme.otpauth;
      default:
        return UrlScheme.unknown;
    }
  }

  /// Extracts a lowercased scheme name (the part before `:`), or null when the
  /// string has no scheme. Guards against treating a bare `host:port` as a
  /// scheme by requiring the scheme to match the RFC 3986 grammar.
  String? _schemeName(String url) {
    final colon = url.indexOf(':');
    if (colon <= 0) return null;
    final candidate = url.substring(0, colon);
    final valid = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*$').hasMatch(candidate);
    if (!valid) return null;
    // `example.com:8080/x` — the "scheme" is followed by digits (a port), not a
    // URL body. Heuristic: a real scheme is followed by `//`, `mailto:`-style
    // path, or a non-numeric char.
    final rest = url.substring(colon + 1);
    if (rest.isNotEmpty && RegExp(r'^[0-9]').hasMatch(rest) &&
        !rest.startsWith('//')) {
      return null;
    }
    return candidate.toLowerCase();
  }

  UrlOpenPolicy _policyFor(UrlScheme scheme) {
    switch (scheme) {
      case UrlScheme.http:
      case UrlScheme.https:
      case UrlScheme.ssh:
      case UrlScheme.sftp:
      case UrlScheme.ftp:
      case UrlScheme.mailto:
        return UrlOpenPolicy.autoOpen;
      case UrlScheme.command:
      case UrlScheme.file:
      case UrlScheme.otpauth:
      case UrlScheme.unknown:
        return UrlOpenPolicy.confirmFirst;
      case UrlScheme.none:
        return UrlOpenPolicy.blocked;
    }
  }

  /// True when [url]'s scheme is on the hard block-list (script/data URIs).
  static bool isBlockedScheme(String url) {
    final colon = url.indexOf(':');
    if (colon <= 0) return false;
    return _blockedSchemes.contains(url.substring(0, colon).toLowerCase());
  }
}
