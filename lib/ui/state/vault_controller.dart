// dgvault — app state, wired to the REAL engine.
//
// The unlock flow is genuine, not faked: a demo database is encrypted to KDBX
// bytes in memory; the master password is wrapped under a PIN in a KeyVault.
// Unlocking runs PinUnlock → KeyVault unwraps the master password → KdbxCodec
// decrypts the KDBX → the Database is shown. Wrong PINs drive AppLockPolicy.
//
// Persistence to a real .kdbx file (file picker / autosave) is a follow-up; the
// in-memory blob keeps the slice self-contained while exercising the crypto.

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:dgvault/core/core.dart';
import 'package:dgvault/core/crypto/impl/aead_cipher.dart';
import 'package:dgvault/core/crypto/impl/argon2_kdf.dart';
import 'package:dgvault/core/crypto/impl/kdbx4_body_cipher.dart';
import 'package:dgvault/data/format/gzip_compressor.dart';

import 'demo_vault.dart';

enum VaultStatus { booting, locked, unlocking, unlocked }

class VaultController extends ChangeNotifier {
  VaultController();

  static const String demoPin = '1337';
  static const String _masterPassword = 'correct horse battery staple';
  static const _kdf = Argon2KeyDerivation();

  // Light Argon2 so unlock is snappy in the demo; still the real primitive.
  static const _params = KdfParams(
      algorithm: KdfAlgorithm.argon2id, iterations: 2, memoryKib: 8192, parallelism: 1,);

  final _store = InMemorySecureStore();
  late final KeyVault _vault = KeyVault(
      store: _store, cipher: AesGcmCipher(), kdf: _kdf,);
  final AppLockPolicy _lock = AppLockPolicy(
      store: InMemoryFailedAttemptStore(), maxAttempts: 5, wipeOnExhaustion: false,);
  late final PinUnlock _pin = PinUnlock(vault: _vault, lock: _lock);

  final KdbxCodec _codec = KdbxCodec(
      bodyCipher: Kdbx4BodyCipher(kdf: _kdf), compressor: const GzipCompressor(),);

  Uint8List _vaultBytes = Uint8List(0);

  VaultStatus status = VaultStatus.booting;
  Database? _db;
  String? error;
  int remainingAttempts = 5;
  bool get lockedOut => _lock.isLockedOut;

  Database? get database => _db;
  int get entryCount => _db?.root.allEntries.length ?? 0;

  Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

  /// Encrypt a demo vault and enrol the demo PIN. Call once before runApp.
  Future<void> bootstrap() async {
    final demo = buildDemoDatabase();
    final header = demoHeader(_params);
    _vaultBytes = await _codec.write(
        demo, header, CompositeCredential(password: _b(_masterPassword)),);

    await _vault.enroll(
      masterKey: HeapSecureKey(_b(_masterPassword)),
      unlockSecret: CompositeCredential(password: _b(demoPin)),
      params: _params,
      salt: Uint8List.fromList(List.generate(16, (i) => i * 5 + 1)),
      iv: Uint8List.fromList(List.generate(12, (i) => i * 7 + 3)),
    );
    status = VaultStatus.locked;
    notifyListeners();
  }

  /// Try [pin]. Real path: PinUnlock → master password → KDBX decrypt.
  Future<void> attempt(String pin) async {
    if (status == VaultStatus.unlocking) return;
    status = VaultStatus.unlocking;
    error = null;
    notifyListeners();

    try {
      final result = await _pin.attempt(_b(pin));
      if (result.unlocked) {
        final pw = result.masterKey!;
        try {
          _db = await _codec.read(
              _vaultBytes, CompositeCredential(password: pw.bytes()),);
        } finally {
          pw.destroy();
        }
        status = VaultStatus.unlocked;
        remainingAttempts = 5;
      } else {
        status = VaultStatus.locked;
        remainingAttempts = result.remainingAttempts;
        error = result.lockedOut
            ? 'LOCKED OUT — too many failed attempts'
            : 'ACCESS DENIED — $remainingAttempts attempt(s) left';
      }
    } catch (e) {
      status = VaultStatus.locked;
      error = 'unlock error: $e';
    }
    notifyListeners();
  }

  void lock() {
    _db = null;
    error = null;
    status = VaultStatus.locked;
    notifyListeners();
  }

  /// Reset the lockout counter (demo affordance).
  void resetLockout() {
    _lock.reset();
    remainingAttempts = 5;
    error = null;
    notifyListeners();
  }

  /// Entries matching [query] (empty → all), via the real search engine.
  List<Entry> search(String query) {
    final db = _db;
    if (db == null) return const [];
    return EntrySearch.searchGroup(db.root, SearchQuery(query))
        .map((m) => m.entry)
        .toList();
  }
}
