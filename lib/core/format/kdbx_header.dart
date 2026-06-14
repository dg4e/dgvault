// dgvault — KDBX4 outer binary header + VariantDictionary codec (structural).
//
// Pure Dart byte (de)serialization of the *unencrypted* KDBX4 outer header:
// file signatures, format version, and the TLV header fields (cipher UUID,
// compression flags, master seed, encryption IV, KDF parameters as a
// VariantDictionary, public custom data). This is the structural glue between
// the KeePass XML inner codec and the crypto layer — it deliberately does NOT
// perform any cryptography. The header SHA-256 / HMAC-SHA-256 integrity block
// that follows the header in a real file, and the KDF/cipher transform, are the
// crypto layer's responsibility (toolchain-gated) and are out of scope here.
//
// All integers are little-endian, per the KDBX spec. Verifiable by round-trip
// and against the well-known signature/version constants and KDF type codes.

import 'dart:convert';
import 'dart:typed_data';

/// KDBX file magic. `signature1` is shared by all KeePass files; `signature2`
/// identifies the KDBX (KeePass 2) family.
const int kKdbxSignature1 = 0x9AA2D903;
const int kKdbxSignature2 = 0xB54BFB67;

/// Outer-header field identifiers (KDBX4).
class KdbxHeaderField {
  static const int endOfHeader = 0;
  static const int comment = 1;
  static const int cipherId = 2;
  static const int compressionFlags = 3;
  static const int masterSeed = 4;
  static const int encryptionIv = 7;
  static const int kdfParameters = 11;
  static const int publicCustomData = 12;
}

/// Compression algorithms (CompressionFlags field).
class KdbxCompression {
  static const int none = 0;
  static const int gzip = 1;
}

class KdbxFormatException implements Exception {
  KdbxFormatException(this.message);
  final String message;
  @override
  String toString() => 'KdbxFormatException: $message';
}

// ---------------------------------------------------------------------------
// Little-endian byte cursor helpers.
// ---------------------------------------------------------------------------

class _ByteReader {
  _ByteReader(this._bytes) : _data = ByteData.sublistView(_bytes);
  final Uint8List _bytes;
  final ByteData _data;
  int _pos = 0;

  int get position => _pos;
  bool get atEnd => _pos >= _bytes.length;

  int readUint8() {
    _need(1);
    return _data.getUint8(_pos++);
  }

  int readUint16() {
    _need(2);
    final v = _data.getUint16(_pos, Endian.little);
    _pos += 2;
    return v;
  }

  int readUint32() {
    _need(4);
    final v = _data.getUint32(_pos, Endian.little);
    _pos += 4;
    return v;
  }

  int readUint64() {
    _need(8);
    final v = _data.getUint64(_pos, Endian.little);
    _pos += 8;
    return v;
  }

  Uint8List readBytes(int n) {
    _need(n);
    final out = Uint8List.sublistView(_bytes, _pos, _pos + n);
    _pos += n;
    return Uint8List.fromList(out);
  }

  void _need(int n) {
    if (_pos + n > _bytes.length) {
      throw KdbxFormatException('unexpected end of data at $_pos (need $n)');
    }
  }
}

class _ByteWriter {
  final BytesBuilder _b = BytesBuilder(copy: false);

  void writeUint8(int v) => _b.addByte(v & 0xff);

  void writeUint16(int v) {
    final d = ByteData(2)..setUint16(0, v, Endian.little);
    _b.add(d.buffer.asUint8List());
  }

  void writeUint32(int v) {
    final d = ByteData(4)..setUint32(0, v, Endian.little);
    _b.add(d.buffer.asUint8List());
  }

  void writeUint64(int v) {
    final d = ByteData(8)..setUint64(0, v, Endian.little);
    _b.add(d.buffer.asUint8List());
  }

  void writeBytes(List<int> v) => _b.add(v);

  Uint8List toBytes() => _b.toBytes();
}

// ---------------------------------------------------------------------------
// VariantDictionary — the KDBX4 KDF-parameter container.
// ---------------------------------------------------------------------------

/// Value types in a KDBX VariantDictionary (the byte is the on-disk type tag).
enum VdType {
  uint32(0x04),
  uint64(0x05),
  boolean(0x08),
  int32(0x0C),
  int64(0x0D),
  string(0x18),
  bytes(0x42);

  const VdType(this.code);
  final int code;

  static VdType fromCode(int code) =>
      values.firstWhere((t) => t.code == code,
          orElse: () => throw KdbxFormatException(
              'unknown VariantDictionary type 0x${code.toRadixString(16)}'));
}

/// A typed value. [value] is `int` for the integer types, `bool` for boolean,
/// `String` for string, and `Uint8List` for bytes.
class VdValue {
  VdValue(this.type, this.value);
  VdValue.uint32(int v) : this(VdType.uint32, v);
  VdValue.uint64(int v) : this(VdType.uint64, v);
  VdValue.boolean(bool v) : this(VdType.boolean, v);
  VdValue.string(String v) : this(VdType.string, v);
  VdValue.bytes(Uint8List v) : this(VdType.bytes, v);

  final VdType type;
  final Object value;

  int get asInt => value as int;
  bool get asBool => value as bool;
  String get asString => value as String;
  Uint8List get asBytes => value as Uint8List;
}

/// KDBX VariantDictionary: an ordered map of typed values. Version is 0x0100.
class VariantDictionary {
  VariantDictionary([Map<String, VdValue>? entries])
      : _entries = entries ?? <String, VdValue>{};

  static const int version = 0x0100;

  final Map<String, VdValue> _entries;

  Map<String, VdValue> get entries => Map.unmodifiable(_entries);
  VdValue? operator [](String key) => _entries[key];
  void operator []=(String key, VdValue v) => _entries[key] = v;

  Uint8List encode() {
    final w = _ByteWriter()..writeUint16(version);
    _entries.forEach((key, val) {
      w.writeUint8(val.type.code);
      final keyBytes = utf8.encode(key);
      w.writeUint32(keyBytes.length);
      w.writeBytes(keyBytes);
      final valBytes = _encodeValue(val);
      w.writeUint32(valBytes.length);
      w.writeBytes(valBytes);
    });
    w.writeUint8(0); // end marker
    return w.toBytes();
  }

  static VariantDictionary decode(Uint8List bytes) {
    final r = _ByteReader(bytes);
    final ver = r.readUint16();
    // Only the major version must match (high byte).
    if ((ver >> 8) != (version >> 8)) {
      throw KdbxFormatException(
          'unsupported VariantDictionary version 0x${ver.toRadixString(16)}');
    }
    final out = <String, VdValue>{};
    while (true) {
      final typeCode = r.readUint8();
      if (typeCode == 0) break; // end marker
      final type = VdType.fromCode(typeCode);
      final keyLen = r.readUint32();
      final key = utf8.decode(r.readBytes(keyLen));
      final valLen = r.readUint32();
      final valBytes = r.readBytes(valLen);
      out[key] = _decodeValue(type, valBytes);
    }
    return VariantDictionary(out);
  }

  static Uint8List _encodeValue(VdValue v) {
    switch (v.type) {
      case VdType.uint32:
      case VdType.int32:
        return (ByteData(4)..setUint32(0, v.asInt & 0xFFFFFFFF, Endian.little))
            .buffer
            .asUint8List();
      case VdType.uint64:
      case VdType.int64:
        return (ByteData(8)..setUint64(0, v.asInt, Endian.little))
            .buffer
            .asUint8List();
      case VdType.boolean:
        return Uint8List.fromList([v.asBool ? 1 : 0]);
      case VdType.string:
        return Uint8List.fromList(utf8.encode(v.asString));
      case VdType.bytes:
        return v.asBytes;
    }
  }

  static VdValue _decodeValue(VdType type, Uint8List bytes) {
    final d = ByteData.sublistView(bytes);
    switch (type) {
      case VdType.uint32:
        return VdValue(type, d.getUint32(0, Endian.little));
      case VdType.int32:
        return VdValue(type, d.getInt32(0, Endian.little));
      case VdType.uint64:
        return VdValue(type, d.getUint64(0, Endian.little));
      case VdType.int64:
        return VdValue(type, d.getInt64(0, Endian.little));
      case VdType.boolean:
        return VdValue(type, bytes.isNotEmpty && bytes[0] != 0);
      case VdType.string:
        return VdValue(type, utf8.decode(bytes));
      case VdType.bytes:
        return VdValue(type, Uint8List.fromList(bytes));
    }
  }
}

// ---------------------------------------------------------------------------
// KdbxHeader — signatures, version, and the outer TLV header fields.
// ---------------------------------------------------------------------------

class KdbxHeader {
  KdbxHeader({
    this.signature1 = kKdbxSignature1,
    this.signature2 = kKdbxSignature2,
    this.versionMajor = 4,
    this.versionMinor = 0,
    Map<int, Uint8List>? fields,
  }) : fields = fields ?? <int, Uint8List>{};

  int signature1;
  int signature2;
  int versionMajor;
  int versionMinor;

  /// Raw header fields keyed by [KdbxHeaderField] id (excludes end-of-header).
  final Map<int, Uint8List> fields;

  bool get isKdbx4 => versionMajor == 4;

  // Typed convenience accessors over the raw fields.
  Uint8List? get cipherId => fields[KdbxHeaderField.cipherId];
  Uint8List? get masterSeed => fields[KdbxHeaderField.masterSeed];
  Uint8List? get encryptionIv => fields[KdbxHeaderField.encryptionIv];

  int? get compressionFlags {
    final f = fields[KdbxHeaderField.compressionFlags];
    if (f == null) return null;
    return ByteData.sublistView(f).getUint32(0, Endian.little);
  }

  VariantDictionary? get kdfParameters {
    final f = fields[KdbxHeaderField.kdfParameters];
    return f == null ? null : VariantDictionary.decode(f);
  }

  void setCompressionFlags(int v) => fields[KdbxHeaderField.compressionFlags] =
      (ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List();

  void setKdfParameters(VariantDictionary vd) =>
      fields[KdbxHeaderField.kdfParameters] = vd.encode();

  /// Serialize signatures + version + TLV fields. KDBX4 uses a 4-byte length
  /// prefix per field and terminates with an end-of-header field.
  Uint8List encode() {
    final w = _ByteWriter()
      ..writeUint32(signature1)
      ..writeUint32(signature2)
      ..writeUint16(versionMinor)
      ..writeUint16(versionMajor);
    fields.forEach((id, data) {
      w.writeUint8(id);
      w.writeUint32(data.length);
      w.writeBytes(data);
    });
    // End-of-header marker (KeePass writes 4 bytes of payload, conventionally
    // \r\n\r\n); a single terminator field with that payload round-trips.
    w.writeUint8(KdbxHeaderField.endOfHeader);
    const eoh = [0x0d, 0x0a, 0x0d, 0x0a];
    w.writeUint32(eoh.length);
    w.writeBytes(eoh);
    return w.toBytes();
  }

  /// Parse a KDBX4 header from [bytes]. Returns the header and the byte offset
  /// immediately after the end-of-header field (where the encrypted payload /
  /// integrity block begins).
  static KdbxHeaderParseResult parse(Uint8List bytes) {
    final r = _ByteReader(bytes);
    final sig1 = r.readUint32();
    final sig2 = r.readUint32();
    if (sig1 != kKdbxSignature1 || sig2 != kKdbxSignature2) {
      throw KdbxFormatException('not a KDBX file (bad signature)');
    }
    final minor = r.readUint16();
    final major = r.readUint16();
    if (major != 4) {
      throw KdbxFormatException('unsupported KDBX major version $major');
    }
    final fields = <int, Uint8List>{};
    while (true) {
      final id = r.readUint8();
      final len = r.readUint32();
      final data = r.readBytes(len);
      if (id == KdbxHeaderField.endOfHeader) break;
      fields[id] = data;
    }
    return KdbxHeaderParseResult(
      header: KdbxHeader(
        signature1: sig1,
        signature2: sig2,
        versionMajor: major,
        versionMinor: minor,
        fields: fields,
      ),
      headerLength: r.position,
    );
  }
}

class KdbxHeaderParseResult {
  KdbxHeaderParseResult({required this.header, required this.headerLength});
  final KdbxHeader header;

  /// Number of bytes consumed by the header (signatures..end-of-header). The
  /// integrity hashes / encrypted payload begin here.
  final int headerLength;
}
