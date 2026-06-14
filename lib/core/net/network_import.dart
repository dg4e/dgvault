// dgvault — Direct URL import + local-network-only access control (pure logic).
//
// Two related pieces, both pure (the actual network fetch is the platform layer):
//   • HostClassifier — is a host on the local network (loopback / RFC1918 /
//     link-local / IPv6 ULA / mDNS .local / single-label LAN name)? This is the
//     decision behind "Local Network Only Import & Export": when enabled, only
//     local targets are allowed, so a backup/import can never silently reach the
//     public internet.
//   • DirectImportUrl — validate an import URL's scheme and detect its format
//     so the right importer (CSV / 1Password / KDBX) is chosen.

class LocalNetworkViolation implements Exception {
  LocalNetworkViolation(this.host);
  final String host;
  @override
  String toString() =>
      'LocalNetworkViolation: "$host" is not on the local network';
}

class HostClassifier {
  const HostClassifier._();

  /// True when [host] is loopback / private / link-local / mDNS / a single-label
  /// LAN name — i.e. not a public-internet destination. Conservative: anything
  /// that looks like a public FQDN or public IP returns false.
  static bool isLocal(String host) {
    var h = host.trim().toLowerCase();
    if (h.isEmpty) return false;
    // Strip brackets from IPv6 literals: [::1] → ::1
    if (h.startsWith('[') && h.endsWith(']')) {
      h = h.substring(1, h.length - 1);
    }

    if (h == 'localhost' || h.endsWith('.localhost')) return true;
    if (h.endsWith('.local')) return true; // mDNS / Bonjour

    if (_ipv4.hasMatch(h)) return _isLocalIpv4(h);
    if (h.contains(':')) return _isLocalIpv6(h);

    // Bare single-label host (no dot). A genuine LAN hostname has at least one
    // non-digit; a purely numeric / 0x-hex / 0-octal host is an integer-encoded
    // IPv4 that HTTP stacks (curl, many libs) resolve as a real IP — e.g.
    // 134744072 == public 8.8.8.8. Such a host MUST be parsed as a 32-bit IPv4
    // and range-checked, never blanket-classified local (that was the SSRF/leak
    // bypass; Critic R20). Anything numeric-looking we can't confidently place in
    // a local range fails safe → not local.
    if (!h.contains('.')) {
      final asInt = _parseIntHost(h);
      if (asInt != null) return _isLocalIpv4Int(asInt);
      return true; // non-numeric single-label LAN name
    }

    return false; // dotted public FQDN
  }

  static final RegExp _ipv4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$');
  static final RegExp _digits = RegExp(r'^\d+$');

  /// Parse a dotless integer-encoded host (decimal / 0x-hex / 0-octal, per
  /// inet_aton) to its numeric value, or null if it is not a pure integer host.
  static int? _parseIntHost(String h) {
    if (h.isEmpty) return null;
    if (h.startsWith('0x') || h.startsWith('0X')) {
      if (h.length == 2) return null;
      return int.tryParse(h.substring(2), radix: 16);
    }
    if (!_digits.hasMatch(h)) return null;
    // A leading zero means octal under inet_aton; honour that so we range-check
    // the IP a fetch would actually reach.
    if (h.length > 1 && h.startsWith('0')) return int.tryParse(h, radix: 8);
    return int.tryParse(h);
  }

  static bool _isLocalIpv4(String ip) {
    final m = _ipv4.firstMatch(ip)!;
    final o = [for (var i = 1; i <= 4; i++) int.parse(m.group(i)!)];
    if (o.any((b) => b > 255)) return false; // malformed → not local
    return _isLocalOctets(o);
  }

  /// Range-check an integer-encoded IPv4 (single 32-bit value, inet_aton form).
  static bool _isLocalIpv4Int(int v) {
    if (v < 0 || v > 0xFFFFFFFF) return false; // out of IPv4 range → not local
    final o = [
      (v >> 24) & 0xff,
      (v >> 16) & 0xff,
      (v >> 8) & 0xff,
      v & 0xff,
    ];
    return _isLocalOctets(o);
  }

  static bool _isLocalOctets(List<int> o) {
    if (o[0] == 127) return true; // 127.0.0.0/8 loopback
    if (o[0] == 10) return true; // 10.0.0.0/8
    if (o[0] == 192 && o[1] == 168) return true; // 192.168.0.0/16
    if (o[0] == 172 && o[1] >= 16 && o[1] <= 31) return true; // 172.16.0.0/12
    if (o[0] == 169 && o[1] == 254) return true; // 169.254.0.0/16 link-local
    return false;
  }

  static bool _isLocalIpv6(String ip) {
    final h = ip;
    if (h == '::1') return true; // loopback
    // fe80::/10 link-local
    if (h.startsWith('fe8') || h.startsWith('fe9') ||
        h.startsWith('fea') || h.startsWith('feb')) {
      return true;
    }
    // fc00::/7 unique local addresses (fc.. / fd..)
    if (h.startsWith('fc') || h.startsWith('fd')) return true;
    return false;
  }
}

/// Guards transfers when "local network only" is enabled.
class LocalOnlyPolicy {
  const LocalOnlyPolicy({this.enabled = false});

  final bool enabled;

  /// Whether a transfer to [url] is permitted. Always true when disabled; when
  /// enabled, only local-network hosts pass.
  bool allows(String url) {
    if (!enabled) return true;
    final host = _hostOf(url);
    if (host == null) return false; // unparseable → deny under local-only
    return HostClassifier.isLocal(host);
  }

  /// Throws [LocalNetworkViolation] when [url] is not permitted.
  void enforce(String url) {
    if (!allows(url)) {
      throw LocalNetworkViolation(_hostOf(url) ?? url);
    }
  }

  static String? _hostOf(String url) {
    final u = Uri.tryParse(url.trim());
    if (u == null) return null;
    if (u.host.isNotEmpty) return u.host;
    // bare host with no scheme: Uri puts it in path
    if (!u.hasScheme && u.path.isNotEmpty) {
      return u.path.split('/').first;
    }
    return null;
  }
}

/// Format of a directly-imported resource.
enum ImportFormat { csv, onePassword, kdbx, unknown }

class DirectImportException implements Exception {
  DirectImportException(this.message);
  final String message;
  @override
  String toString() => 'DirectImportException: $message';
}

class DirectImportUrl {
  const DirectImportUrl._();

  /// Schemes a direct import may be fetched from.
  static const Set<String> allowedSchemes = {'http', 'https', 'file'};

  /// Validate [url]: must parse, have an allowed scheme, and (for http/https) a
  /// host. Returns the parsed [Uri].
  static Uri validate(String url) {
    final u = Uri.tryParse(url.trim());
    if (u == null || !u.hasScheme) {
      throw DirectImportException('not an absolute URL: "$url"');
    }
    if (!allowedSchemes.contains(u.scheme)) {
      throw DirectImportException('scheme "${u.scheme}" not allowed for import');
    }
    if ((u.scheme == 'http' || u.scheme == 'https') && u.host.isEmpty) {
      throw DirectImportException('missing host in "$url"');
    }
    return u;
  }

  /// Detect the import format from a file path/URL and/or HTTP content type.
  static ImportFormat detectFormat({String? path, String? contentType}) {
    final ct = contentType?.toLowerCase() ?? '';
    if (ct.contains('csv')) return ImportFormat.csv;

    final p = (path ?? '').toLowerCase();
    final dot = p.lastIndexOf('.');
    final ext = dot >= 0 ? p.substring(dot + 1) : '';
    switch (ext) {
      case 'csv':
        return ImportFormat.csv;
      case '1pif':
      case '1pux':
        return ImportFormat.onePassword;
      case 'kdbx':
        return ImportFormat.kdbx;
    }
    return ImportFormat.unknown;
  }
}
