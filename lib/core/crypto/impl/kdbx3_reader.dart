// dgvault — KDBX 3.1 reader (legacy KeePass 2.x format).
//
// KDBX3 predates KDBX4 and differs substantially:
//   • outer header uses 2-byte (uint16) TLV lengths; KDF is always AES-KDF with
//     a TransformSeed + TransformRounds (no Argon2 / VariantDictionary).
//   • master key = SHA-256(MasterSeed ++ AES-KDF(compositeKey)).
//   • body = AES-256-CBC(masterKey, IV) over: StreamStartBytes(32) ++ a SHA-256
//     "hashed block stream" (index ++ SHA-256(block) ++ len ++ data, len=0 ends).
//     A correct password is confirmed by the decrypted StreamStartBytes matching
//     the header; there is no HMAC.
//   • the de-blocked payload (optionally gzip) is the inner XML directly — there
//     is NO inner header; the protected-value stream key lives in the OUTER
//     header (ProtectedStreamKey), and KDBX3.1 uses Salsa20.
//
// Vetted primitives only (pointycastle); this owns the v3 framing + key tree.
// Read-only: dgvault writes KDBX4. Reuses the AES-KDF, inner-stream, and XML
// codecs already built for KDBX4.

import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart' as pc;

import '../../format/kdbx_file.dart';
import '../../format/kdbx_header.dart';
import '../../format/kdbx_inner.dart';
import '../../format/keepass_xml.dart';
import '../../model/database.dart';
import '../../model/kdf_params.dart';
import '../key_derivation.dart';
import 'aes_kdf.dart';
import 'kdbx4_body_cipher.dart' show KdbxIntegrityException;

class Kdbx3Reader {
  const Kdbx3Reader();

  static const _aesKdf = AesKdfKeyDerivation();

  // Outer-header field ids (KDBX3).
  static const int _fEnd = 0;
  static const int _fCompression = 3;
  static const int _fMasterSeed = 4;
  static const int _fTransformSeed = 5;
  static const int _fTransformRounds = 6;
  static const int _fEncryptionIv = 7;
  static const int _fProtectedStreamKey = 8;
  static const int _fStreamStartBytes = 9;
  static const int _fInnerRandomStreamId = 10;

  Future<Database> read(
    Uint8List bytes,
    CompositeCredential credential, {
    required Compressor compressor,
    KeePassXml xml = const KeePassXml(),
  }) async {
    final h = _parseHeader(bytes);

    // AES-KDF transform + master key.
    final transformed = await _aesKdf.deriveKey(
      credential,
      KdfParams(algorithm: KdfAlgorithm.aesKdf, iterations: h.transformRounds),
      h.transformSeed,
    );
    final Uint8List masterKey;
    try {
      masterKey = _sha256(_concat([h.masterSeed, transformed.bytes()]));
    } finally {
      transformed.destroy();
    }

    // AES-256-CBC decrypt the body.
    final cipherText = Uint8List.sublistView(bytes, h.length);
    final plain = _aesCbcDecrypt(masterKey, h.encryptionIv, cipherText);

    // Confirm the password: the first 32 bytes must equal StreamStartBytes.
    if (plain.length < 32 ||
        !_constEq(Uint8List.sublistView(plain, 0, 32), h.streamStartBytes)) {
      throw KdbxIntegrityException(
          'wrong master password (stream-start mismatch)',);
    }

    // SHA-256 hashed block stream → payload.
    var payload =
        _readHashedBlocks(Uint8List.sublistView(plain, 32));
    if (h.compressed) payload = compressor.decompress(payload);

    // No inner header in v3 — payload is the XML; protected values use the
    // outer-header stream key.
    var xmlString = utf8.decode(payload);
    if (h.innerStreamId != InnerStreamId.none) {
      xmlString = unprotectXml(
        xmlString,
        InnerRandomStream.fromId(h.innerStreamId, h.protectedStreamKey),
      );
    }
    return xml.decode(xmlString);
  }

  _V3Header _parseHeader(Uint8List bytes) {
    if (KdbxHeader.majorVersion(bytes) != 3) {
      throw KdbxFormatException('not a KDBX3 file');
    }
    final bd = ByteData.sublistView(bytes);
    var offset = 12; // after sig1/sig2/minor/major
    Uint8List? masterSeed, transformSeed, encIv, streamKey, streamStart;
    var rounds = 0, innerId = InnerStreamId.salsa20;
    var compressed = false;

    while (true) {
      // Untrusted, pre-authentication: bounds-check the 3-byte TLV header and
      // the declared length, and require a terminating field.
      if (offset + 3 > bytes.length) {
        throw KdbxFormatException('truncated KDBX3 header (no end field)');
      }
      final id = bd.getUint8(offset);
      offset += 1;
      final len = bd.getUint16(offset, Endian.little); // v3: 2-byte length
      offset += 2;
      if (offset + len > bytes.length) {
        throw KdbxFormatException('KDBX3 header field $id length $len overruns');
      }
      final data = Uint8List.sublistView(bytes, offset, offset + len);
      offset += len;
      switch (id) {
        case _fEnd:
          return _V3Header(
            length: offset,
            compressed: compressed,
            masterSeed: masterSeed ?? Uint8List(0),
            transformSeed: transformSeed ?? Uint8List(0),
            transformRounds: rounds,
            encryptionIv: encIv ?? Uint8List(0),
            protectedStreamKey: streamKey ?? Uint8List(0),
            streamStartBytes: streamStart ?? Uint8List(0),
            innerStreamId: innerId,
          );
        case _fCompression:
          _need(data, 4, 'compression');
          compressed = ByteData.sublistView(data).getUint32(0, Endian.little) == 1;
        case _fMasterSeed:
          masterSeed = data;
        case _fTransformSeed:
          transformSeed = data;
        case _fTransformRounds:
          _need(data, 8, 'transform rounds');
          rounds = ByteData.sublistView(data).getUint64(0, Endian.little);
          if (rounds < 1 || rounds > _maxTransformRounds) {
            throw KdbxFormatException('implausible KDBX3 transform rounds');
          }
        case _fEncryptionIv:
          encIv = data;
        case _fProtectedStreamKey:
          streamKey = data;
        case _fStreamStartBytes:
          streamStart = data;
        case _fInnerRandomStreamId:
          _need(data, 4, 'inner stream id');
          innerId = ByteData.sublistView(data).getUint32(0, Endian.little);
        default:
          break; // cipher id / comment / unknown — ignored
      }
    }
  }

  /// Sanity cap on AES-KDF rounds so a malicious header can't pin the CPU
  /// forever (legitimate vaults are well under this).
  static const int _maxTransformRounds = 100000000;

  static void _need(Uint8List data, int n, String what) {
    if (data.length < n) {
      throw KdbxFormatException('KDBX3 $what field needs $n bytes');
    }
  }

  /// Parse the SHA-256 hashed block stream (KDBX3): repeated
  /// `index(4) ++ hash(32) ++ size(4) ++ data(size)`, terminated by size 0.
  Uint8List _readHashedBlocks(Uint8List stream) {
    final out = BytesBuilder();
    var offset = 0;
    while (true) {
      if (offset + 40 > stream.length) {
        throw KdbxIntegrityException('truncated hashed block stream');
      }
      // index (4) — not validated beyond ordering
      offset += 4;
      final hash = Uint8List.sublistView(stream, offset, offset + 32);
      offset += 32;
      final size = ByteData.sublistView(stream, offset, offset + 4)
          .getUint32(0, Endian.little);
      offset += 4;
      if (size == 0) break; // terminating block
      if (offset + size > stream.length) {
        throw KdbxIntegrityException('block size exceeds stream');
      }
      final data = Uint8List.sublistView(stream, offset, offset + size);
      offset += size;
      if (!_constEq(_sha256(data), hash)) {
        throw KdbxIntegrityException('hashed block integrity failure');
      }
      out.add(data);
    }
    return out.toBytes();
  }

  Uint8List _aesCbcDecrypt(Uint8List key, Uint8List iv, Uint8List data) {
    final cbc = pc.PaddedBlockCipherImpl(
      pc.PKCS7Padding(),
      pc.CBCBlockCipher(pc.AESEngine()),
    )..init(
        false,
        pc.PaddedBlockCipherParameters<pc.ParametersWithIV<pc.KeyParameter>,
            Null>(
          pc.ParametersWithIV(pc.KeyParameter(key), iv),
          null,
        ),
      );
    try {
      return cbc.process(data);
    } on pc.InvalidCipherTextException {
      // Corrupt PKCS7 padding ⇒ a wrong master key.
      throw KdbxIntegrityException('wrong master password (decrypt failed)');
    } on ArgumentError {
      throw KdbxIntegrityException('wrong master password (decrypt failed)');
    }
  }

  static Uint8List _sha256(Uint8List b) => pc.SHA256Digest().process(b);

  static Uint8List _concat(List<Uint8List> parts) {
    final b = BytesBuilder();
    for (final p in parts) {
      b.add(p);
    }
    return b.toBytes();
  }

  static bool _constEq(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var d = 0;
    for (var i = 0; i < a.length; i++) {
      d |= a[i] ^ b[i];
    }
    return d == 0;
  }
}

class _V3Header {
  _V3Header({
    required this.length,
    required this.compressed,
    required this.masterSeed,
    required this.transformSeed,
    required this.transformRounds,
    required this.encryptionIv,
    required this.protectedStreamKey,
    required this.streamStartBytes,
    required this.innerStreamId,
  });
  final int length;
  final bool compressed;
  final Uint8List masterSeed;
  final Uint8List transformSeed;
  final int transformRounds;
  final Uint8List encryptionIv;
  final Uint8List protectedStreamKey;
  final Uint8List streamStartBytes;
  final int innerStreamId;
}
