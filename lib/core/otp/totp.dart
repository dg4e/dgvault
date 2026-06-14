// dgvault — TOTP / HOTP (RFC 6238 / RFC 4226) with Steam variant + otpauth URIs.
//
// HOTP = truncate(HMAC(key, counter)); TOTP = HOTP with counter = floor(unix/period).
// The only cryptographic primitive is the HMAC, which is **injected** via
// [OtpHmac] (real HMAC-SHA1/256/512 from a vetted library at the platform
// layer). Everything else — counter framing, dynamic truncation, decimal/Steam
// encoding, Base32 secret decoding, and otpauth:// (QR) parsing — is pure Dart
// and validated headlessly against the RFC 4226 truncation vectors.

import 'dart:convert';
import 'dart:typed_data';

enum OtpAlgorithm { sha1, sha256, sha512 }

enum OtpEncoding { decimal, steam }

/// Injected keyed-hash. `algorithm` selects the digest; returns the raw MAC.
abstract interface class OtpHmac {
  Uint8List compute(OtpAlgorithm algorithm, Uint8List key, Uint8List message);
}

class OtpConfig {
  const OtpConfig({
    required this.secret,
    this.digits = 6,
    this.period = 30,
    this.algorithm = OtpAlgorithm.sha1,
    this.encoding = OtpEncoding.decimal,
    this.issuer,
    this.account,
  });

  /// Raw secret key bytes (already Base32-decoded).
  final Uint8List secret;
  final int digits;
  final int period; // seconds
  final OtpAlgorithm algorithm;
  final OtpEncoding encoding;
  final String? issuer;
  final String? account;

  /// Parses an `otpauth://totp/...` URI (the payload a TOTP QR code encodes).
  factory OtpConfig.fromUri(String uri) {
    final u = Uri.parse(uri);
    if (u.scheme != 'otpauth' || u.host.toLowerCase() != 'totp') {
      throw FormatException('not an otpauth://totp URI: $uri');
    }
    final q = u.queryParameters;
    final secretParam = q['secret'];
    if (secretParam == null || secretParam.isEmpty) {
      throw FormatException('otpauth URI missing secret');
    }
    final label = u.pathSegments.isNotEmpty ? u.pathSegments.last : '';
    final issuer = q['issuer'] ??
        (label.contains(':') ? label.split(':').first : null);
    final account = label.contains(':') ? label.split(':').last : label;

    final isSteam = (q['encoder']?.toLowerCase() == 'steam') ||
        (issuer?.toLowerCase() == 'steam');

    return OtpConfig(
      secret: base32Decode(secretParam),
      digits: isSteam ? 5 : int.tryParse(q['digits'] ?? '') ?? 6,
      period: int.tryParse(q['period'] ?? '') ?? 30,
      algorithm: _algoFromName(q['algorithm']),
      encoding: isSteam ? OtpEncoding.steam : OtpEncoding.decimal,
      issuer: issuer,
      account: account.isEmpty ? null : account,
    );
  }

  static OtpAlgorithm _algoFromName(String? name) {
    switch (name?.toUpperCase()) {
      case 'SHA256':
        return OtpAlgorithm.sha256;
      case 'SHA512':
        return OtpAlgorithm.sha512;
      default:
        return OtpAlgorithm.sha1;
    }
  }
}

class Totp {
  const Totp(this.hmac);

  final OtpHmac hmac;

  static const String _steamAlphabet = '23456789BCDFGHJKMNPQRTVWXY';

  /// The current TOTP code for [config] at [now].
  String generate(OtpConfig config, DateTime now) {
    final counter = (now.millisecondsSinceEpoch ~/ 1000) ~/ config.period;
    return generateHotp(config, counter);
  }

  /// Seconds until the current code rolls over.
  int remainingSeconds(OtpConfig config, DateTime now) {
    final unix = now.millisecondsSinceEpoch ~/ 1000;
    return config.period - (unix % config.period);
  }

  /// HOTP for an explicit [counter] (also the TOTP building block).
  String generateHotp(OtpConfig config, int counter) {
    final message = Uint8List(8);
    ByteData.sublistView(message).setUint64(0, counter, Endian.big);
    final digest = hmac.compute(config.algorithm, config.secret, message);
    final binary = _truncate(digest);
    return config.encoding == OtpEncoding.steam
        ? _encodeSteam(binary, config.digits)
        : _encodeDecimal(binary, config.digits);
  }

  /// RFC 4226 dynamic truncation → a 31-bit integer.
  static int _truncate(Uint8List digest) {
    final offset = digest[digest.length - 1] & 0x0f;
    return ((digest[offset] & 0x7f) << 24) |
        ((digest[offset + 1] & 0xff) << 16) |
        ((digest[offset + 2] & 0xff) << 8) |
        (digest[offset + 3] & 0xff);
  }

  static String _encodeDecimal(int binary, int digits) {
    final mod = binary % _pow10(digits);
    return mod.toString().padLeft(digits, '0');
  }

  static String _encodeSteam(int binary, int digits) {
    var x = binary;
    final sb = StringBuffer();
    for (var i = 0; i < digits; i++) {
      sb.write(_steamAlphabet[x % _steamAlphabet.length]);
      x ~/= _steamAlphabet.length;
    }
    return sb.toString();
  }

  static int _pow10(int n) {
    var r = 1;
    for (var i = 0; i < n; i++) {
      r *= 10;
    }
    return r;
  }
}

/// RFC 4648 Base32 decode (upper/lower-case, padding & whitespace tolerant).
Uint8List base32Decode(String input) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  final clean =
      input.toUpperCase().replaceAll('=', '').replaceAll(RegExp(r'\s'), '');
  var bits = 0;
  var value = 0;
  final out = <int>[];
  for (final unit in clean.codeUnits) {
    final idx = alphabet.indexOf(String.fromCharCode(unit));
    if (idx < 0) {
      throw FormatException('invalid base32 character: ${String.fromCharCode(unit)}');
    }
    value = (value << 5) | idx;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      out.add((value >> bits) & 0xff);
    }
  }
  return Uint8List.fromList(out);
}

/// Encodes raw bytes back to Base32 (used when generating otpauth URIs / QR).
String base32Encode(Uint8List data) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  final sb = StringBuffer();
  var bits = 0;
  var value = 0;
  for (final b in data) {
    value = (value << 8) | b;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      sb.write(alphabet[(value >> bits) & 0x1f]);
    }
  }
  if (bits > 0) {
    sb.write(alphabet[(value << (5 - bits)) & 0x1f]);
  }
  return sb.toString();
}

/// Convenience: ASCII bytes of [s] (RFC 4226 vectors use an ASCII secret).
Uint8List asciiSecret(String s) => Uint8List.fromList(ascii.encode(s));
