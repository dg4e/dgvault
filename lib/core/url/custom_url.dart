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

    final (scheme, policy) = _analyze(effective);
    return ResolvedUrl(value: effective, scheme: scheme, policy: policy);
  }

  static final RegExp _schemeGrammar = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*$');
  static final RegExp _startsWithDigit = RegExp(r'^[0-9]');

  /// Classifies [url] and assigns an open policy, hardened against scheme
  /// obfuscation. The scheme is sanitized (ASCII control + whitespace removed)
  /// BEFORE block-list matching — because browsers/OS launchers strip `\t\n\r`
  /// from schemes, so `java\tscript:` really runs `javascript:`. A colon-bearing
  /// string whose scheme isn't a clean RFC-3986 token never auto-opens.
  (UrlScheme, UrlOpenPolicy) _analyze(String url) {
    if (url.isEmpty) return (UrlScheme.none, UrlOpenPolicy.blocked);

    final colon = url.indexOf(':');
    if (colon <= 0) {
      // No scheme → bare host → implicit https (browser/KeePass behaviour).
      return (UrlScheme.https, UrlOpenPolicy.autoOpen);
    }

    final rawScheme = url.substring(0, colon);
    final rest = url.substring(colon + 1);
    final sanitized = _sanitizeScheme(rawScheme);

    // Block-list match on the SANITIZED scheme — catches `java\tscript`,
    // `javascript\t`, mixed case, etc.
    if (_blockedSchemes.contains(sanitized)) {
      return (UrlScheme.unknown, UrlOpenPolicy.blocked);
    }

    // A scheme token containing control/whitespace/invalid chars is obfuscated
    // or malformed: never auto-open it (and never fall through to implicit-https).
    if (!_schemeGrammar.hasMatch(rawScheme)) {
      return (UrlScheme.unknown, UrlOpenPolicy.confirmFirst);
    }

    // `example.com:8080/x` — colon introduces a port, not a scheme body.
    if (rest.isNotEmpty && _startsWithDigit.hasMatch(rest) &&
        !rest.startsWith('//')) {
      return (UrlScheme.https, UrlOpenPolicy.autoOpen);
    }

    final scheme = _knownScheme(sanitized);
    return (scheme, _policyFor(scheme));
  }

  /// Strips ASCII control characters and whitespace, then lowercases.
  static String _sanitizeScheme(String raw) {
    final sb = StringBuffer();
    for (final u in raw.codeUnits) {
      if (u > 0x20 && u != 0x7f) sb.writeCharCode(u);
    }
    return sb.toString().toLowerCase();
  }

  static UrlScheme _knownScheme(String name) {
    switch (name) {
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

  /// True when [url]'s scheme is on the hard block-list (script/data URIs),
  /// evaluated after stripping control/whitespace obfuscation.
  static bool isBlockedScheme(String url) {
    final colon = url.indexOf(':');
    if (colon <= 0) return false;
    return _blockedSchemes.contains(_sanitizeScheme(url.substring(0, colon)));
  }
}
