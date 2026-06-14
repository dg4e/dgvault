// dgvault — KDBX4 VariantDictionary binary codec.
//
// KDBX 4 stores KDF parameters (and public custom data) as a "VariantDictionary":
// a length-prefixed, typed key/value map. This is pure binary serialization with
// no cryptography — it is the structural container the Argon2/AES-KDF layer reads
// its parameters from. Fully unit-testable round-trip.
//
// Wire format (all integers little-endian):
//   uint16 version (0x0100)
//   repeated: uint8 type, int32 keyLen, key(UTF-8), int32 valueLen, value
//   uint8 0x00 terminator
//
// Value types: UInt32 0x04, UInt64 0x05, Bool 0x08, Int32 0x0C, Int64 0x0D,
//              String 0x18 (UTF-8), ByteArray 0x42.

import 'dart:convert';
import 'dart:typed_data';

class VariantDictionaryException implements Exception {
  VariantDictionaryException(this.message);
  final String message;
  @override
  String toString() => 'VariantDictionaryException: $message';
}

class VariantDictionary {
  VariantDictionary();

  static const int _version = 0x0100;

  static const int typeUInt32 = 0x04;
  static const int typeUInt64 = 0x05;
  static const int typeBool = 0x08;
  static const int typeInt32 = 0x0C;
  static const int typeInt64 = 0x0D;
  static const int typeString = 0x18;
  static const int typeByteArray = 0x42;

  // Insertion order preserved (KeePass writes keys in a stable order).
  final Map<String, _Entry> _entries = <String, _Entry>{};

  Iterable<String> get keys => _entries.keys;
  bool containsKey(String key) => _entries.containsKey(key);

  // ---- typed getters (return null when absent) ----
  int? getUInt32(String key) => _entries[key]?.value as int?;
  int? getUInt64(String key) => _entries[key]?.value as int?;
  bool? getBool(String key) => _entries[key]?.value as bool?;
  String? getString(String key) => _entries[key]?.value as String?;
  Uint8List? getBytes(String key) => _entries[key]?.value as Uint8List?;

  // ---- typed setters ----
  void setUInt32(String key, int v) => _entries[key] = _Entry(typeUInt32, v);
  void setUInt64(String key, int v) => _entries[key] = _Entry(typeUInt64, v);
  void setBool(String key, bool v) => _entries[key] = _Entry(typeBool, v);
  void setString(String key, String v) =>
      _entries[key] = _Entry(typeString, v);
  void setBytes(String key, Uint8List v) =>
      _entries[key] = _Entry(typeByteArray, v);

  Uint8List serialize() {
    final out = BytesBuilder();
    final hdr = ByteData(2)..setUint16(0, _version, Endian.little);
    out.add(hdr.buffer.asUint8List());

    _entries.forEach((key, entry) {
      out.addByte(entry.type);
      final keyBytes = utf8.encode(key);
      _addInt32(out, keyBytes.length);
      out.add(keyBytes);
      final valueBytes = _encodeValue(entry);
      _addInt32(out, valueBytes.length);
      out.add(valueBytes);
    });

    out.addByte(0x00); // terminator
    return out.toBytes();
  }

  static VariantDictionary parse(Uint8List bytes) {
    final bd = ByteData.sublistView(bytes);
    var offset = 0;
    final version = bd.getUint16(offset, Endian.little);
    offset += 2;
    if ((version >> 8) != 0x01) {
      throw VariantDictionaryException(
          'unsupported VariantDictionary version 0x${version.toRadixString(16)}');
    }
    final vd = VariantDictionary();
    while (offset < bytes.length) {
      final type = bd.getUint8(offset);
      offset += 1;
      if (type == 0x00) break; // terminator
      final keyLen = bd.getInt32(offset, Endian.little);
      offset += 4;
      final key = utf8.decode(bytes.sublist(offset, offset + keyLen));
      offset += keyLen;
      final valueLen = bd.getInt32(offset, Endian.little);
      offset += 4;
      final value = bytes.sublist(offset, offset + valueLen);
      offset += valueLen;
      vd._entries[key] = _decodeEntry(type, value);
    }
    return vd;
  }

  static void _addInt32(BytesBuilder out, int v) {
    final b = ByteData(4)..setInt32(0, v, Endian.little);
    out.add(b.buffer.asUint8List());
  }

  Uint8List _encodeValue(_Entry entry) {
    switch (entry.type) {
      case typeUInt32:
        return (ByteData(4)..setUint32(0, entry.value as int, Endian.little))
            .buffer
            .asUint8List();
      case typeInt32:
        return (ByteData(4)..setInt32(0, entry.value as int, Endian.little))
            .buffer
            .asUint8List();
      case typeUInt64:
        return (ByteData(8)..setUint64(0, entry.value as int, Endian.little))
            .buffer
            .asUint8List();
      case typeInt64:
        return (ByteData(8)..setInt64(0, entry.value as int, Endian.little))
            .buffer
            .asUint8List();
      case typeBool:
        return Uint8List.fromList([(entry.value as bool) ? 1 : 0]);
      case typeString:
        return Uint8List.fromList(utf8.encode(entry.value as String));
      case typeByteArray:
        return entry.value as Uint8List;
      default:
        throw VariantDictionaryException('unknown type 0x${entry.type}');
    }
  }

  static _Entry _decodeEntry(int type, Uint8List value) {
    final bd = ByteData.sublistView(value);
    switch (type) {
      case typeUInt32:
        return _Entry(type, bd.getUint32(0, Endian.little));
      case typeInt32:
        return _Entry(type, bd.getInt32(0, Endian.little));
      case typeUInt64:
        return _Entry(type, bd.getUint64(0, Endian.little));
      case typeInt64:
        return _Entry(type, bd.getInt64(0, Endian.little));
      case typeBool:
        return _Entry(type, value.isNotEmpty && value[0] != 0);
      case typeString:
        return _Entry(type, utf8.decode(value));
      case typeByteArray:
        return _Entry(type, value);
      default:
        throw VariantDictionaryException('unknown type 0x$type');
    }
  }
}

class _Entry {
  _Entry(this.type, this.value);
  final int type;
  final Object value;
}
