// dgvault — KDBX4 outer-header binary codec (crypto-free).
//
// Parses/serializes the unencrypted KDBX4 outer header: magic signature,
// format version, and the type-length-value header fields (cipher id,
// compression, master seed, encryption IV, KDF parameters as a
// VariantDictionary). It deliberately stops at the header boundary — the
// header SHA-256/HMAC integrity checks and the encrypted+HMAC'd block stream
// are the crypto layer's job (computed over the exact header bytes this codec
// reads/writes via [KdbxHeader.length] / [serialize]).
//
// This is the structural container the Argon2/AES-KDF and AES/ChaCha cipher
// layers plug into. Pure binary, fully unit-testable.

import 'dart:typed_data';

import '../model/database.dart';
import '../model/kdf_params.dart';
import 'variant_dictionary.dart';

class KdbxFormatException implements Exception {
  KdbxFormatException(this.message);
  final String message;
  @override
  String toString() => 'KdbxFormatException: $message';
}

/// Well-known 16-byte identifiers used in the header / KDF parameters.
class KdbxUuids {
  static final Uint8List aes256 = Uint8List.fromList([
    0x31, 0xC1, 0xF2, 0xE6, 0xBF, 0x71, 0x43, 0x50, //
    0xBE, 0x58, 0x05, 0x21, 0x6A, 0xFC, 0x5A, 0xFF,
  ]);
  static final Uint8List chacha20 = Uint8List.fromList([
    0xD6, 0x03, 0x8A, 0x2B, 0x8B, 0x6F, 0x4C, 0xB5, //
    0xA5, 0x24, 0x33, 0x9A, 0x31, 0xDB, 0xB5, 0x9A,
  ]);
  static final Uint8List aesKdf = Uint8List.fromList([
    0xC9, 0xD9, 0xF3, 0x9A, 0x62, 0x8A, 0x44, 0x60, //
    0xBF, 0x74, 0x0D, 0x08, 0xC1, 0x8A, 0x4F, 0xEA,
  ]);
  static final Uint8List argon2d = Uint8List.fromList([
    0xEF, 0x63, 0x6D, 0xDF, 0x8C, 0x29, 0x44, 0x4B, //
    0x91, 0xF7, 0xA9, 0xA4, 0x03, 0xE3, 0x0A, 0x0C,
  ]);
  static final Uint8List argon2id = Uint8List.fromList([
    0x9E, 0x29, 0x8B, 0x19, 0x56, 0xDB, 0x47, 0x73, //
    0xB2, 0x3D, 0xFC, 0x3E, 0xC6, 0xF0, 0xA1, 0xE6,
  ]);
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Maps the KDBX4 `KdfParameters` VariantDictionary to/from [KdfParams].
class KdfParameters {
  /// Builds the VariantDictionary KeePass persists for [params] with [salt].
  static VariantDictionary toVariantDictionary(
      KdfParams params, Uint8List salt,) {
    final vd = VariantDictionary();
    switch (params.algorithm) {
      case KdfAlgorithm.argon2d:
        vd.setBytes(r'$UUID', KdbxUuids.argon2d);
      case KdfAlgorithm.argon2id:
        vd.setBytes(r'$UUID', KdbxUuids.argon2id);
      case KdfAlgorithm.aesKdf:
        vd.setBytes(r'$UUID', KdbxUuids.aesKdf);
    }
    if (params.isArgon2) {
      vd.setUInt64('I', params.iterations);
      vd.setUInt64('M', (params.memoryKib ?? 0) * 1024); // KeePass stores BYTES
      vd.setUInt32('P', params.parallelism ?? 1);
      vd.setUInt32('V', params.version);
      vd.setBytes('S', salt);
    } else {
      vd.setUInt64('R', params.iterations); // transform rounds
      vd.setBytes('S', salt); // transform seed
    }
    return vd;
  }

  /// Parses a KDF VariantDictionary into [KdfParams] plus the raw salt/seed.
  static (KdfParams, Uint8List) fromVariantDictionary(VariantDictionary vd) {
    final uuid = vd.getBytes(r'$UUID');
    if (uuid == null) {
      throw KdbxFormatException('KdfParameters missing \$UUID');
    }
    final salt = vd.getBytes('S') ?? Uint8List(0);
    if (_bytesEqual(uuid, KdbxUuids.aesKdf)) {
      return (
        KdfParams(
          algorithm: KdfAlgorithm.aesKdf,
          iterations: vd.getUInt64('R') ?? 1,
        ),
        salt,
      );
    }
    final algo = _bytesEqual(uuid, KdbxUuids.argon2d)
        ? KdfAlgorithm.argon2d
        : KdfAlgorithm.argon2id;
    final memBytes = vd.getUInt64('M') ?? 0;
    return (
      KdfParams(
        algorithm: algo,
        iterations: vd.getUInt64('I') ?? 1,
        memoryKib: memBytes ~/ 1024,
        parallelism: vd.getUInt32('P') ?? 1,
        version: vd.getUInt32('V') ?? 0x13,
      ),
      salt,
    );
  }
}

class KdbxHeader {
  KdbxHeader({
    required this.cipher,
    required this.compressed,
    required this.masterSeed,
    required this.encryptionIv,
    required this.kdfParameters,
    this.publicCustomData,
    this.versionMajor = 4,
    this.versionMinor = 1,
  });

  static const int sig1 = 0x9AA2D903;
  static const int sig2 = 0xB54BFB67;

  /// Validate the KDBX magic and return the major version (3 or 4). Throws
  /// [KdbxFormatException] if the magic is wrong — used to detect the format
  /// before choosing a v3/v4 reader.
  static int majorVersion(Uint8List bytes) {
    if (bytes.length < 12) {
      throw KdbxFormatException('file too short for KDBX header');
    }
    final bd = ByteData.sublistView(bytes);
    if (bd.getUint32(0, Endian.little) != sig1 ||
        bd.getUint32(4, Endian.little) != sig2) {
      throw KdbxFormatException('bad KDBX magic signature');
    }
    return bd.getUint16(10, Endian.little);
  }

  // Header field ids.
  static const int _fEndOfHeader = 0;
  static const int _fCipherId = 2;
  static const int _fCompression = 3;
  static const int _fMasterSeed = 4;
  static const int _fEncryptionIv = 7;
  static const int _fKdfParameters = 11;
  static const int _fPublicCustomData = 12;

  DatabaseCipher cipher;
  bool compressed; // gzip when true
  Uint8List masterSeed;
  Uint8List encryptionIv;
  VariantDictionary kdfParameters;
  VariantDictionary? publicCustomData;
  int versionMajor;
  int versionMinor;

  /// Number of bytes the serialized header occupies (set on read; the crypto
  /// layer hashes exactly `fileBytes.sublist(0, length)`).
  int length = 0;

  /// The exact header bytes as read from the file (set by [read]). The KDBX4
  /// header SHA-256 / HMAC must cover these original bytes — re-serializing can
  /// differ from a third-party writer's byte layout. Null for a freshly-built
  /// header (then [serialize] is authoritative).
  Uint8List? headerBytes;

  KdfParams get kdf => KdfParameters.fromVariantDictionary(kdfParameters).$1;

  Uint8List serialize() {
    final out = BytesBuilder();
    final sig = ByteData(12)
      ..setUint32(0, sig1, Endian.little)
      ..setUint32(4, sig2, Endian.little)
      ..setUint16(8, versionMinor, Endian.little)
      ..setUint16(10, versionMajor, Endian.little);
    out.add(sig.buffer.asUint8List());

    void field(int id, Uint8List data) {
      out.addByte(id);
      final len = ByteData(4)..setUint32(0, data.length, Endian.little);
      out.add(len.buffer.asUint8List());
      out.add(data);
    }

    field(_fCipherId, _cipherUuid(cipher));
    final comp = ByteData(4)..setUint32(0, compressed ? 1 : 0, Endian.little);
    field(_fCompression, comp.buffer.asUint8List());
    field(_fMasterSeed, masterSeed);
    field(_fEncryptionIv, encryptionIv);
    field(_fKdfParameters, kdfParameters.serialize());
    if (publicCustomData != null) {
      field(_fPublicCustomData, publicCustomData!.serialize());
    }
    field(_fEndOfHeader, Uint8List.fromList([0x0D, 0x0A, 0x0D, 0x0A]));

    final bytes = out.toBytes();
    length = bytes.length;
    return bytes;
  }

  Uint8List _cipherUuid(DatabaseCipher c) =>
      c == DatabaseCipher.chacha20 ? KdbxUuids.chacha20 : KdbxUuids.aes256;

  static KdbxHeader read(Uint8List bytes) {
    final bd = ByteData.sublistView(bytes);
    if (bytes.length < 12) {
      throw KdbxFormatException('file too short for KDBX header');
    }
    if (bd.getUint32(0, Endian.little) != sig1 ||
        bd.getUint32(4, Endian.little) != sig2) {
      throw KdbxFormatException('bad KDBX magic signature');
    }
    final minor = bd.getUint16(8, Endian.little);
    final major = bd.getUint16(10, Endian.little);
    if (major != 4) {
      throw KdbxFormatException('unsupported KDBX major version $major (need 4)');
    }

    var offset = 12;
    DatabaseCipher? cipher;
    var compressed = false;
    Uint8List? masterSeed;
    Uint8List? iv;
    VariantDictionary? kdf;
    VariantDictionary? publicCustom;

    while (true) {
      final id = bd.getUint8(offset);
      offset += 1;
      final len = bd.getUint32(offset, Endian.little);
      offset += 4;
      final data = bytes.sublist(offset, offset + len);
      offset += len;

      switch (id) {
        case _fEndOfHeader:
          final header = KdbxHeader(
            cipher: cipher ?? DatabaseCipher.aes256,
            compressed: compressed,
            masterSeed: masterSeed ?? Uint8List(0),
            encryptionIv: iv ?? Uint8List(0),
            kdfParameters: kdf ?? VariantDictionary(),
            publicCustomData: publicCustom,
            versionMajor: major,
            versionMinor: minor,
          );
          header.length = offset;
          header.headerBytes = Uint8List.sublistView(bytes, 0, offset);
          return header;
        case _fCipherId:
          cipher = _bytesEqual(data, KdbxUuids.chacha20)
              ? DatabaseCipher.chacha20
              : DatabaseCipher.aes256;
        case _fCompression:
          compressed =
              ByteData.sublistView(data).getUint32(0, Endian.little) == 1;
        case _fMasterSeed:
          masterSeed = data;
        case _fEncryptionIv:
          iv = data;
        case _fKdfParameters:
          kdf = VariantDictionary.parse(data);
        case _fPublicCustomData:
          publicCustom = VariantDictionary.parse(data);
        default:
          // Unknown/ignored header field (forward-compatible).
          break;
      }
    }
  }
}
