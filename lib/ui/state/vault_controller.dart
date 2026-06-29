// dgvault — app state, wired to real .kdbx files.
//
// Open a KDBX file → enter the master password → KdbxCodec.read decrypts it →
// the Database is shown. Save re-encrypts (with a fresh master seed / IV / KDF
// salt) and writes back to the same file. New creates an empty encrypted vault.
// No demo data — everything here operates on actual files on disk.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:dgvault/core/core.dart';
import 'package:dgvault/core/crypto/impl/argon2_kdf.dart';
import 'package:dgvault/core/crypto/impl/kdbx4_body_cipher.dart';
import 'package:dgvault/data/format/gzip_compressor.dart';

enum VaultStatus { noVault, locked, unlocking, unlocked, saving }

class VaultController extends ChangeNotifier {
  VaultController();

  static const _kdf = Argon2KeyDerivation();
  final KdbxCodec _codec = KdbxCodec(
    bodyCipher: Kdbx4BodyCipher(kdf: _kdf),
    compressor: const GzipCompressor(),
  );

  // Hooks the VaultScreen registers while mounted (for the app-level menu).
  VoidCallback? onGenerate;
  VoidCallback? onCopyPassword;

  VaultStatus status = VaultStatus.noVault;
  String? path; // file on disk (null for an in-memory/test vault)
  String? fileName; // for display
  String? error;

  Uint8List? _bytes; // the encrypted file contents
  KdbxHeader? _header; // parsed header of the loaded file (cipher + KDF)
  CompositeCredential? _cred; // master password, kept while unlocked (for save)
  Database? _db;

  Database? get database => _db;
  bool get hasVault => _bytes != null;
  bool get isDirty => _dirty;
  bool _dirty = false;
  int get entryCount => _db?.root.allEntries.length ?? 0;

  Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

  // ---- open ---------------------------------------------------------------

  /// Load an encrypted KDBX file from disk; transitions to the password prompt.
  Future<void> openFile(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    loadBytes(bytes,
        path: filePath, name: filePath.split(Platform.pathSeparator).last,);
  }

  /// Load already-read KDBX bytes (used by tests / non-file sources).
  void loadBytes(Uint8List bytes, {String? path, required String name}) {
    // Validate it's a KDBX before prompting (fail fast on a bad file).
    try {
      KdbxHeader.read(bytes);
    } on KdbxFormatException catch (e) {
      error = 'not a KDBX file: ${e.message}';
      notifyListeners();
      return;
    }
    _bytes = bytes;
    this.path = path;
    fileName = name;
    error = null;
    status = VaultStatus.locked;
    notifyListeners();
  }

  /// Decrypt the loaded file with [password].
  Future<void> unlock(String password) async {
    final bytes = _bytes;
    if (bytes == null || status == VaultStatus.unlocking) return;
    status = VaultStatus.unlocking;
    error = null;
    notifyListeners();

    try {
      final cred = CompositeCredential(password: _b(password));
      _db = await _codec.read(bytes, cred);
      _header = KdbxHeader.read(bytes);
      _cred = cred;
      _dirty = false;
      status = VaultStatus.unlocked;
    } on KdbxIntegrityException {
      status = VaultStatus.locked;
      error = 'ACCESS DENIED — wrong master password';
    } catch (e) {
      status = VaultStatus.locked;
      error = 'open failed: $e';
    }
    notifyListeners();
  }

  // ---- save / new ---------------------------------------------------------

  /// Re-encrypt the open database (fresh seed/IV/salt) and write it to [path].
  Future<void> save() async {
    final db = _db, cred = _cred, p = path, h = _header;
    if (db == null || cred == null || p == null || h == null) return;
    status = VaultStatus.saving;
    notifyListeners();
    try {
      final header = _freshHeader(h.kdf, h.cipher);
      final out = await _codec.write(db, header, cred);
      await File(p).writeAsBytes(out, flush: true);
      _bytes = out;
      _header = header;
      _dirty = false;
      error = null;
    } catch (e) {
      error = 'save failed: $e';
    }
    status = VaultStatus.unlocked;
    notifyListeners();
  }

  /// Create a new empty vault at [filePath] protected by [password], and open it.
  Future<void> createNew(String filePath, String password) async {
    status = VaultStatus.unlocking;
    notifyListeners();
    try {
      final name = filePath.split(Platform.pathSeparator).last;
      final db = Database(
        meta: DatabaseMeta(name: name.replaceAll('.kdbx', '')),
        root: Group(uuid: _uuid(), name: 'Root'),
      );
      final cred = CompositeCredential(password: _b(password));
      final header =
          _freshHeader(KdfParams.argon2idDefault(), DatabaseCipher.aes256);
      final out = await _codec.write(db, header, cred);
      await File(filePath).writeAsBytes(out, flush: true);

      _bytes = out;
      _header = header;
      _cred = cred;
      _db = db;
      path = filePath;
      fileName = name;
      _dirty = false;
      error = null;
      status = VaultStatus.unlocked;
    } catch (e) {
      status = VaultStatus.noVault;
      error = 'create failed: $e';
    }
    notifyListeners();
  }

  // ---- lifecycle ----------------------------------------------------------

  /// Lock the open database (keep the file loaded for re-unlock).
  void lock() {
    _db = null;
    _cred = null;
    error = null;
    status = _bytes != null ? VaultStatus.locked : VaultStatus.noVault;
    notifyListeners();
  }

  /// Close the file entirely (back to the landing screen).
  void close() {
    _bytes = null;
    _header = null;
    _db = null;
    _cred = null;
    path = null;
    fileName = null;
    error = null;
    status = VaultStatus.noVault;
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

  // ---- helpers ------------------------------------------------------------

  KdbxHeader _freshHeader(KdfParams params, DatabaseCipher cipher) =>
      KdbxHeader(
        cipher: cipher,
        compressed: true,
        masterSeed: _rand(32),
        encryptionIv: _rand(cipher == DatabaseCipher.chacha20 ? 12 : 16),
        kdfParameters: KdfParameters.toVariantDictionary(params, _rand(32)),
      );

  final Random _rng = Random.secure();
  Uint8List _rand(int n) =>
      Uint8List.fromList(List.generate(n, (_) => _rng.nextInt(256)));

  String _uuid() => base64.encode(_rand(16));
}
