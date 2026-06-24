// dgvault — minimal CBOR decoder (RFC 8949 subset for WebAuthn/COSE).
//
// WebAuthn carries the attestation object and COSE keys as CBOR. This decodes
// the definite-length subset they use: unsigned/negative integers, byte and
// text strings, arrays, and maps. It tracks the read offset so callers can find
// where an embedded item (e.g. the credential public key inside authenticator
// data) ends. Not a general CBOR codec — indefinite lengths, tags, floats, and
// simple values beyond what WebAuthn needs are intentionally unsupported.

import 'dart:convert';
import 'dart:typed_data';

class CborException implements Exception {
  CborException(this.message);
  final String message;
  @override
  String toString() => 'CborException: $message';
}

class CborReader {
  CborReader(this.bytes);
  final Uint8List bytes;
  int offset = 0;

  /// Decode a single CBOR data item, advancing [offset].
  Object? readItem() {
    final initial = _u8();
    final major = initial >> 5;
    final info = initial & 0x1f;
    switch (major) {
      case 0: // unsigned int
        return _argument(info);
      case 1: // negative int: -1 - n
        return -1 - _argument(info);
      case 2: // byte string
        return _take(_argument(info));
      case 3: // text string
        return utf8.decode(_take(_argument(info)));
      case 4: // array
        final n = _argument(info);
        return [for (var i = 0; i < n; i++) readItem()];
      case 5: // map
        final n = _argument(info);
        final map = <Object?, Object?>{};
        for (var i = 0; i < n; i++) {
          final k = readItem();
          map[k] = readItem();
        }
        return map;
      default:
        throw CborException('unsupported CBOR major type $major');
    }
  }

  int _argument(int info) {
    if (info < 24) return info;
    switch (info) {
      case 24:
        return _u8();
      case 25:
        return _uint(2);
      case 26:
        return _uint(4);
      case 27:
        return _uint(8);
      default:
        throw CborException('unsupported CBOR additional info $info');
    }
  }

  int _u8() {
    if (offset >= bytes.length) throw CborException('truncated CBOR');
    return bytes[offset++];
  }

  int _uint(int n) {
    var v = 0;
    for (var i = 0; i < n; i++) {
      v = (v << 8) | _u8();
    }
    return v;
  }

  Uint8List _take(int n) {
    if (offset + n > bytes.length) throw CborException('truncated CBOR string');
    final out = Uint8List.sublistView(bytes, offset, offset + n);
    offset += n;
    return out;
  }
}

/// Decode a single top-level CBOR item from [bytes].
Object? cborDecode(Uint8List bytes) => CborReader(bytes).readItem();
