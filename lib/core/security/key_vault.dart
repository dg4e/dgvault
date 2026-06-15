// dgvault — key vault: wrap the database master key behind a short unlock
// secret (PIN / biometric-released secret), stored in the OS keystore.
//
// Lets the user unlock with a PIN instead of re-deriving from the full master
// password each time: the master key is AEAD-encrypted under a key derived from
// the unlock secret and persisted via [SecureStore]. A wrong PIN fails
// authenticated decryption (no plaintext leaks, comparison is the AEAD tag —
// constant-time). Biometric unlock reuses this with the same wrapping; only the
// secret's release is device-gated.
//
// Injected [Cipher]/[KeyDerivation] are the vetted real primitives; this file
// owns only the self-describing blob + orchestration.

import 'dart:typed_data';

import '../crypto/cipher.dart';
import '../crypto/key_derivation.dart';
import '../crypto/secure_key.dart';
import '../model/kdf_params.dart';
import 'secure_store.dart';

class KeyVaultException implements Exception {
  KeyVaultException(this.message);
  final String message;
  @override
  String toString() => 'KeyVaultException: $message';
}

class KeyVault {
  KeyVault({
    required this.store,
    required this.cipher,
    required this.kdf,
    this.slot = 'dgvault.masterkey',
  });

  final SecureStore store;
  final Cipher cipher;
  final KeyDerivation kdf;

  /// Keystore entry name for this wrapped key.
  final String slot;

  static const List<int> _magic = [0x44, 0x47, 0x4B, 0x56]; // "DGKV"
  static const int _version = 1;

  Future<bool> get isEnrolled => store.contains(slot);

  /// Remove the wrapped key (e.g. on logout / disable-PIN).
  Future<void> reset() => store.delete(slot);

  /// Wrap [masterKey] under [unlockSecret] and persist it. [salt]/[iv] come from
  /// the caller's secure RNG.
  Future<void> enroll({
    required SecureKey masterKey,
    required CompositeCredential unlockSecret,
    required KdfParams params,
    required Uint8List salt,
    required Uint8List iv,
  }) async {
    final wrapKey = await kdf.deriveKey(unlockSecret, params, salt);
    final Uint8List ciphertext;
    try {
      ciphertext =
          await cipher.encrypt(key: wrapKey, iv: iv, plaintext: masterKey.bytes());
    } finally {
      wrapKey.destroy();
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
    await store.write(slot, w.take());
  }

  /// Unwrap the master key using [unlockSecret]. Throws on a missing/corrupt
  /// blob; the [Cipher] throws [CipherAuthenticationException] on a wrong PIN.
  Future<SecureKey> unlock(CompositeCredential unlockSecret) async {
    final blob = await store.read(slot);
    if (blob == null) {
      throw KeyVaultException('no wrapped key enrolled in "$slot"');
    }
    final r = _Reader(blob);
    if (!r.matchBytes(_magic)) {
      throw KeyVaultException('not a key-vault blob (bad magic)');
    }
    final version = r.u8();
    if (version != _version) {
      throw KeyVaultException('unsupported key-vault version $version');
    }
    r.u8(); // cipher algorithm index (informational; this.cipher is authoritative)
    final kdfAlgoIndex = r.u8();
    if (kdfAlgoIndex < 0 || kdfAlgoIndex >= KdfAlgorithm.values.length) {
      throw KeyVaultException('unknown KDF algorithm index $kdfAlgoIndex');
    }
    final params = KdfParams(
      algorithm: KdfAlgorithm.values[kdfAlgoIndex],
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

    final wrapKey = await kdf.deriveKey(unlockSecret, params, salt);
    final Uint8List plaintext;
    try {
      plaintext =
          await cipher.decrypt(key: wrapKey, iv: iv, ciphertext: ciphertext);
    } finally {
      wrapKey.destroy();
    }
    return HeapSecureKey(plaintext);
  }
}

// ---- little-endian byte helpers (private to the blob) ----

class _Writer {
  final BytesBuilder _b = BytesBuilder(copy: false);
  void u8(int v) => _b.addByte(v & 0xff);
  void u32(int v) =>
      _b.add((ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());
  void u64(int v) =>
      _b.add((ByteData(8)..setUint64(0, v, Endian.little)).buffer.asUint8List());
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
      throw KeyVaultException('truncated key-vault blob at $_p (need $n)');
    }
  }
}
