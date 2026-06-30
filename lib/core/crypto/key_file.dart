// dgvault — KeePass key-file parser.
//
// Converts a key file's raw bytes into the 32-byte key material that feeds the
// composite master key (see [CompositeCredential.keyFile]). KeePass / KeePassXC
// recognise four forms, detected in this order:
//
//   1. KeePass 2.x XML key file  — <KeyFile><Key><Data Hash="..">…</Data></Key>
//        • v2.0: Data is hex of the 32-byte key; Hash = first 4 bytes of
//          SHA-256(key), verified for integrity.
//        • v1.0: Data is Base64 of the 32-byte key (no hash).
//   2. 32 raw bytes              — used verbatim as the key.
//   3. 64 hex characters         — decoded to 32 bytes.
//   4. anything else             — SHA-256 of the whole file.
//
// SHA-256 is the one cryptographic primitive needed; it is **injected** via
// [Sha256Hasher] so this parser stays pure/testable and the real hash comes
// from a vetted library at the platform layer. No hand-rolled crypto here.

import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import '../util/bytes.dart';

class KeyFileException implements Exception {
  KeyFileException(this.message);
  final String message;
  @override
  String toString() => 'KeyFileException: $message';
}

/// Injected SHA-256. A real implementation wraps a vetted crypto library.
abstract interface class Sha256Hasher {
  /// Returns the 32-byte SHA-256 digest of [data].
  Uint8List hash(Uint8List data);
}

enum KeyFileFormat { keepass2Xml, binary32, hex64, hashed }

class ParsedKeyFile {
  ParsedKeyFile(this.key, this.format);

  /// The 32-byte key material.
  final Uint8List key;
  final KeyFileFormat format;
}

class KeyFile {
  const KeyFile(this.hasher);

  final Sha256Hasher hasher;

  ParsedKeyFile parse(Uint8List bytes) {
    // 1. XML key file (checked first; XML files are never 32/64 raw-byte forms).
    final xmlKey = _tryParseXml(bytes);
    if (xmlKey != null) {
      return ParsedKeyFile(xmlKey, KeyFileFormat.keepass2Xml);
    }
    // 2. Exactly 32 raw bytes → used directly.
    if (bytes.length == 32) {
      return ParsedKeyFile(Uint8List.fromList(bytes), KeyFileFormat.binary32);
    }
    // 3. Exactly 64 hex characters → decode to 32 bytes.
    if (bytes.length == 64 && _isAllHex(bytes)) {
      return ParsedKeyFile(
          _hexDecode(ascii.decode(bytes)), KeyFileFormat.hex64,);
    }
    // 4. Fallback: SHA-256 of the whole file.
    return ParsedKeyFile(_hash32(bytes), KeyFileFormat.hashed);
  }

  Uint8List? _tryParseXml(Uint8List bytes) {
    final String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      return null; // not text → not an XML key file
    }
    if (!text.contains('<KeyFile')) return null;

    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(text);
    } on XmlException {
      throw KeyFileException('malformed XML key file');
    }
    final keyEl = doc.rootElement.getElement('Key');
    final dataEl = keyEl?.getElement('Data');
    if (dataEl == null) {
      throw KeyFileException('XML key file has no <Key><Data>');
    }
    final version =
        doc.rootElement.getElement('Meta')?.getElement('Version')?.innerText ??
            '1.0';
    final raw = dataEl.innerText;

    if (version.startsWith('2')) {
      final key = _hexDecode(raw.replaceAll(RegExp(r'\s+'), ''));
      if (key.length != 32) {
        throw KeyFileException('XML(v2) key is ${key.length} bytes, need 32');
      }
      final hashAttr = dataEl.getAttribute('Hash');
      if (hashAttr != null) {
        final expected = _hexDecode(hashAttr.trim());
        final actual = _hash32(key).sublist(0, expected.length);
        if (!bytesEqual(actual, expected)) {
          throw KeyFileException('XML key file hash mismatch (corrupt file)');
        }
      }
      return key;
    } else {
      final Uint8List key;
      try {
        key = base64.decode(raw.trim());
      } on FormatException {
        throw KeyFileException('XML(v1) key data is not valid base64');
      }
      if (key.length != 32) {
        throw KeyFileException('XML(v1) key is ${key.length} bytes, need 32');
      }
      return Uint8List.fromList(key);
    }
  }

  Uint8List _hash32(Uint8List data) {
    final digest = hasher.hash(data);
    if (digest.length != 32) {
      throw KeyFileException('Sha256Hasher returned ${digest.length} bytes');
    }
    return digest;
  }

  static bool _isAllHex(Uint8List bytes) {
    for (final b in bytes) {
      final isDigit = b >= 0x30 && b <= 0x39;
      final isLower = b >= 0x61 && b <= 0x66;
      final isUpper = b >= 0x41 && b <= 0x46;
      if (!isDigit && !isLower && !isUpper) return false;
    }
    return true;
  }

  static Uint8List _hexDecode(String hex) {
    if (hex.length.isOdd) {
      throw KeyFileException('hex string has odd length');
    }
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      final byte = int.tryParse(hex.substring(i * 2, i * 2 + 2), radix: 16);
      if (byte == null) {
        throw KeyFileException('invalid hex in key file');
      }
      out[i] = byte;
    }
    return out;
  }
}
