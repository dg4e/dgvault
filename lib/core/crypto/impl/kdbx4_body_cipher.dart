// dgvault — real KDBX4 body cipher (vetted primitives: pointycastle).
//
// Implements [KdbxBodyCipher] with the genuine KDBX4 construction, so the
// pipeline in kdbx_file.dart reads/writes real encrypted `.kdbx` bodies:
//
//   transformedKey = Argon2(compositeKey(credential), kdfSalt)         (via KDF)
//   masterKey      = SHA-256(masterSeed ++ transformedKey)             (cipher key)
//   hmacBase       = SHA-512(masterSeed ++ transformedKey ++ 0x01)
//   blockKey(i)    = SHA-512(LE64(i) ++ hmacBase)
//
//   body = SHA-256(header)                       // header integrity hash
//        ++ HMAC-SHA-256(blockKey(0xFFFF…FF), header)   // keyed header MAC
//        ++ HMAC-block-stream( cipher(masterKey, iv, inner) )
//
// The block stream frames the ciphertext as `HMAC(32) ++ LEN(4) ++ DATA`
// repeated, terminated by a zero-length block; each block's HMAC is keyed with
// blockKey(blockIndex) over `LE64(index) ++ LE32(len) ++ data`. The body cipher
// is AES-256-CBC (PKCS7) or ChaCha20 (RFC 7539); integrity comes from the HMAC
// stream, not the cipher.
//
// No hand-rolled crypto: AES/ChaCha/SHA/HMAC are pointycastle; this file owns
// only the KDBX framing + key-tree, which is format serialization, not a
// primitive.
//
// Interop note: header verification re-serializes [KdbxHeader]; that reproduces
// dgvault's own files exactly (round-trip). Byte-exact verification of a
// third-party file would require hashing its original header bytes.

import 'dart:typed_data';

import 'package:pointycastle/export.dart' as pc;

import '../../format/kdbx_file.dart';
import '../../format/kdbx_header.dart';
import '../../model/database.dart';
import '../key_derivation.dart';

class KdbxIntegrityException implements Exception {
  KdbxIntegrityException(this.message);
  final String message;
  @override
  String toString() => 'KdbxIntegrityException: $message';
}

class Kdbx4BodyCipher implements KdbxBodyCipher {
  Kdbx4BodyCipher({required this.kdf});

  /// Argon2/AES-KDF implementation deriving the transformed key.
  final KeyDerivation kdf;

  static const int _hashLen = 32;
  static final Uint8List _headerIndex = Uint8List.fromList(List.filled(8, 0xFF));

  @override
  Future<Uint8List> encryptBody(
    KdbxHeader header,
    Uint8List inner,
    CompositeCredential credential,
  ) async {
    final keys = await _deriveKeys(header, credential);
    final headerBytes = header.serialize();

    final cipherText =
        _transform(true, header.cipher, keys.masterKey, header.encryptionIv, inner);

    final out = BytesBuilder()
      ..add(_sha256(headerBytes))
      ..add(_hmac(_blockKey(_headerIndex, keys.hmacBase), headerBytes))
      ..add(_writeBlockStream(cipherText, keys.hmacBase));
    return out.toBytes();
  }

  @override
  Future<Uint8List> decryptBody(
    KdbxHeader header,
    Uint8List body,
    CompositeCredential credential,
  ) async {
    if (body.length < 2 * _hashLen) {
      throw KdbxIntegrityException('body too short for KDBX4 header MAC');
    }
    final keys = await _deriveKeys(header, credential);
    final headerBytes = header.serialize();

    final storedHash = Uint8List.sublistView(body, 0, _hashLen);
    if (!_constEq(storedHash, _sha256(headerBytes))) {
      throw KdbxIntegrityException('header hash mismatch (corrupt header)');
    }
    final storedMac = Uint8List.sublistView(body, _hashLen, 2 * _hashLen);
    final wantMac = _hmac(_blockKey(_headerIndex, keys.hmacBase), headerBytes);
    if (!_constEq(storedMac, wantMac)) {
      // Wrong credential or tampered header.
      throw KdbxIntegrityException('header HMAC mismatch (wrong key or tamper)');
    }

    final cipherText = _readBlockStream(
        Uint8List.sublistView(body, 2 * _hashLen), keys.hmacBase,);
    return _transform(
        false, header.cipher, keys.masterKey, header.encryptionIv, cipherText,);
  }

  // ---- key tree -----------------------------------------------------------

  Future<_KdbxKeys> _deriveKeys(
      KdbxHeader header, CompositeCredential credential,) async {
    final (params, salt) =
        KdfParameters.fromVariantDictionary(header.kdfParameters);
    final transformed = await kdf.deriveKey(credential, params, salt);
    final seed = header.masterSeed;
    try {
      final tk = transformed.bytes();
      final masterKey = _sha256(_concat([seed, tk]));
      final hmacBase = _sha512(_concat([seed, tk, Uint8List.fromList([0x01])]));
      return _KdbxKeys(masterKey, hmacBase);
    } finally {
      transformed.destroy();
    }
  }

  static Uint8List _blockKey(Uint8List index8, Uint8List hmacBase) =>
      _sha512(_concat([index8, hmacBase]));

  // ---- body cipher --------------------------------------------------------

  Uint8List _transform(bool encrypt, DatabaseCipher algo, Uint8List key,
      Uint8List iv, Uint8List data,) {
    switch (algo) {
      case DatabaseCipher.aes256:
        final cbc = pc.PaddedBlockCipherImpl(
            pc.PKCS7Padding(), pc.CBCBlockCipher(pc.AESEngine()),)
          ..init(
              encrypt,
              pc.PaddedBlockCipherParameters<pc.ParametersWithIV<pc.KeyParameter>,
                  Null>(
                pc.ParametersWithIV(pc.KeyParameter(key), iv),
                null,
              ),);
        return cbc.process(data);
      case DatabaseCipher.chacha20:
        final cha = pc.ChaCha7539Engine()
          ..init(encrypt, pc.ParametersWithIV(pc.KeyParameter(key), iv));
        return cha.process(data);
    }
  }

  // ---- HMAC block stream --------------------------------------------------

  Uint8List _writeBlockStream(Uint8List data, Uint8List hmacBase) {
    final out = BytesBuilder();
    // Single data block (index 0) + terminating empty block (index 1). KDBX
    // permits any block sizing; one block is spec-valid for our DB sizes.
    if (data.isNotEmpty) {
      _emitBlock(out, 0, data, hmacBase);
    }
    final termIndex = data.isEmpty ? 0 : 1;
    _emitBlock(out, termIndex, Uint8List(0), hmacBase);
    return out.toBytes();
  }

  void _emitBlock(BytesBuilder out, int index, Uint8List data, Uint8List hmacBase) {
    final idx = _le64(index);
    final len = _le32(data.length);
    final mac = _hmac(_blockKey(idx, hmacBase), _concat([idx, len, data]));
    out
      ..add(mac)
      ..add(len)
      ..add(data);
  }

  Uint8List _readBlockStream(Uint8List stream, Uint8List hmacBase) {
    final out = BytesBuilder();
    var offset = 0;
    var index = 0;
    while (true) {
      if (offset + _hashLen + 4 > stream.length) {
        throw KdbxIntegrityException('truncated block stream');
      }
      final mac = Uint8List.sublistView(stream, offset, offset + _hashLen);
      offset += _hashLen;
      final lenBytes = Uint8List.sublistView(stream, offset, offset + 4);
      final len = ByteData.sublistView(lenBytes).getUint32(0, Endian.little);
      offset += 4;
      if (offset + len > stream.length) {
        throw KdbxIntegrityException('block length exceeds stream');
      }
      final data = Uint8List.sublistView(stream, offset, offset + len);
      offset += len;

      final idx = _le64(index);
      final want = _hmac(_blockKey(idx, hmacBase), _concat([idx, lenBytes, data]));
      if (!_constEq(mac, want)) {
        throw KdbxIntegrityException('block $index HMAC mismatch (tamper)');
      }
      if (len == 0) break; // terminating block
      out.add(data);
      index++;
    }
    return out.toBytes();
  }

  // ---- primitives ---------------------------------------------------------

  static Uint8List _sha256(Uint8List b) => pc.SHA256Digest().process(b);
  static Uint8List _sha512(Uint8List b) => pc.SHA512Digest().process(b);

  static Uint8List _hmac(Uint8List key, Uint8List data) =>
      (pc.HMac(pc.SHA256Digest(), 64)..init(pc.KeyParameter(key))).process(data);

  static Uint8List _le32(int v) =>
      (ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List();
  static Uint8List _le64(int v) =>
      (ByteData(8)..setUint64(0, v, Endian.little)).buffer.asUint8List();

  static Uint8List _concat(List<Uint8List> parts) {
    final b = BytesBuilder();
    for (final p in parts) {
      b.add(p);
    }
    return b.toBytes();
  }

  static bool _constEq(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

class _KdbxKeys {
  _KdbxKeys(this.masterKey, this.hmacBase);
  final Uint8List masterKey;
  final Uint8List hmacBase;
}
