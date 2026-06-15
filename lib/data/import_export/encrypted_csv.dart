// dgvault — encrypted CSV import/export container.
//
// Wraps the plaintext CSV (see csv_import_export.dart) in a versioned,
// self-describing container so an encrypted export can be re-imported without
// out-of-band metadata: it records the KDF parameters, salt, and IV alongside
// the ciphertext. The actual key derivation and authenticated encryption are
// the injected [KeyDerivation] / [Cipher] (real Argon2id + AES-256/ChaCha20 are
// the toolchain-gated crypto layer). This file owns only the pure container
// (de)serialization + orchestration, which is fully unit-testable with stub
// primitives.
//
// Security: decryption relies on the Cipher being authenticated — a wrong
// password (→ wrong key) or any tampering must surface as a decrypt failure,
// never as silently-wrong plaintext. The container itself adds no confidentiality.

import 'dart:convert';
import 'dart:typed_data';

import '../../core/crypto/cipher.dart';
import '../../core/crypto/key_derivation.dart';
import '../../core/crypto/secure_key.dart';
import '../../core/model/group.dart';
import '../../core/model/kdf_params.dart';
import 'csv_import_export.dart';

class EncryptedCsvException implements Exception {
  EncryptedCsvException(this.message);
  final String message;
  @override
  String toString() => 'EncryptedCsvException: $message';
}

class EncryptedCsv {
  EncryptedCsv({required this.cipher, required this.kdf});

  final Cipher cipher;
  final KeyDerivation kdf;

  static const List<int> _magic = [0x44, 0x47, 0x45, 0x4E, 0x43]; // "DGENC"
  static const int _version = 1;

  /// Encrypt every entry under [root] to a self-describing container.
  /// [salt] and [iv] are supplied by the caller (from a secure RNG).
  Future<Uint8List> export(
    Group root, {
    required CompositeCredential credential,
    required KdfParams params,
    required Uint8List salt,
    required Uint8List iv,
  }) async {
    final csv = const CsvExporter().export(root);
    final plaintext = Uint8List.fromList(utf8.encode(csv));

    final SecureKey key = await kdf.deriveKey(credential, params, salt);
    final Uint8List ciphertext;
    try {
      ciphertext = await cipher.encrypt(key: key, iv: iv, plaintext: plaintext);
    } finally {
      key.destroy();
    }

    final w = _Writer()
      ..bytes(_magic)
      ..u8(_version)
      ..u8(cipher.algorithm.index)
      ..u8(params.algorithm.index)
      ..u64(params.iterations)
      ..u64(params.memoryKib ?? 0)
      ..u32(params.parallelism ?? 0)
      ..u32(params.version)
      ..lenBytes(salt)
      ..lenBytes(iv)
      ..lenBytes(ciphertext);
    return w.take();
  }

  /// Decrypt + parse a container produced by [export]. Throws
  /// [EncryptedCsvException] on a malformed container; the [Cipher] throws on
  /// authentication failure (wrong password / tampering).
  Future<CsvImportResult> import(
    Uint8List container, {
    required CompositeCredential credential,
  }) async {
    final r = _Reader(container);
    if (!r.matchBytes(_magic)) {
      throw EncryptedCsvException('not an encrypted-CSV container (bad magic)');
    }
    final version = r.u8();
    if (version != _version) {
      throw EncryptedCsvException('unsupported container version $version');
    }
    r.u8(); // cipher algorithm index (informational; this.cipher is authoritative)
    final kdfAlgoIndex = r.u8();
    if (kdfAlgoIndex < 0 || kdfAlgoIndex >= KdfAlgorithm.values.length) {
      throw EncryptedCsvException('unknown KDF algorithm index $kdfAlgoIndex');
    }
    final kdfAlgo = KdfAlgorithm.values[kdfAlgoIndex];
    final params = KdfParams(
      algorithm: kdfAlgo,
      iterations: r.u64(),
      memoryKib: () {
        final m = r.u64();
        return m == 0 ? null : m;
      }(),
      parallelism: () {
        final p = r.u32();
        return p == 0 ? null : p;
      }(),
      version: r.u32(),
    );
    final salt = r.lenBytes();
    final iv = r.lenBytes();
    final ciphertext = r.lenBytes();

    final SecureKey key = await kdf.deriveKey(credential, params, salt);
    final Uint8List plaintext;
    try {
      plaintext = await cipher.decrypt(key: key, iv: iv, ciphertext: ciphertext);
    } finally {
      key.destroy();
    }

    final csv = utf8.decode(plaintext);
    return CsvImporter().import(csv);
  }
}

// ---- little-endian byte helpers (kept private to the container) ----

class _Writer {
  final BytesBuilder _b = BytesBuilder(copy: false);

  void u8(int v) => _b.addByte(v & 0xff);
  void u32(int v) => _b.add((ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());
  void u64(int v) => _b.add((ByteData(8)..setUint64(0, v, Endian.little)).buffer.asUint8List());
  void bytes(List<int> v) => _b.add(v);
  void lenBytes(Uint8List v) {
    u32(v.length);
    _b.add(v);
  }

  Uint8List take() => _b.toBytes();
}

class _Reader {
  _Reader(this._d) : _bd = ByteData.sublistView(_d);
  final Uint8List _d;
  final ByteData _bd;
  int _p = 0;

  int u8() {
    _need(1);
    return _bd.getUint8(_p++);
  }

  int u32() {
    _need(4);
    final v = _bd.getUint32(_p, Endian.little);
    _p += 4;
    return v;
  }

  int u64() {
    _need(8);
    final v = _bd.getUint64(_p, Endian.little);
    _p += 8;
    return v;
  }

  bool matchBytes(List<int> expected) {
    _need(expected.length);
    for (var i = 0; i < expected.length; i++) {
      if (_d[_p + i] != expected[i]) return false;
    }
    _p += expected.length;
    return true;
  }

  Uint8List lenBytes() {
    final n = u32();
    _need(n);
    final out = Uint8List.fromList(_d.sublist(_p, _p + n));
    _p += n;
    return out;
  }

  void _need(int n) {
    if (_p + n > _d.length) {
      throw EncryptedCsvException('truncated container at $_p (need $n)');
    }
  }
}
