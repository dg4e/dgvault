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
import 'package:dgvault/core/crypto/impl/kdbx3_reader.dart';
import 'package:dgvault/core/crypto/impl/kdbx4_body_cipher.dart';
import 'package:dgvault/core/crypto/impl/kdf_registry.dart';
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
  Group? get rootGroup => _db?.root;
  String? get recycleBinUuid => _db?.meta.recycleBinUuid;
  bool get hasVault => _bytes != null;
  bool get isDirty => _dirty;
  bool _dirty = false;
  int get entryCount => _db?.root.allEntries.length ?? 0;

  Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

  // ---- open ---------------------------------------------------------------

  /// Load an encrypted KDBX file from disk; transitions to the password prompt.
  Future<void> openFile(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    loadBytes(
      bytes,
      path: filePath,
      name: filePath.split(Platform.pathSeparator).last,
    );
  }

  /// Load already-read KDBX bytes (used by tests / non-file sources).
  void loadBytes(Uint8List bytes, {String? path, required String name}) {
    // Validate it's a supported KDBX (v3 or v4) before prompting.
    try {
      final v = KdbxHeader.majorVersion(bytes);
      if (v != 3 && v != 4) {
        throw KdbxFormatException('unsupported KDBX major version $v');
      }
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
      if (KdbxHeader.majorVersion(bytes) == 3) {
        _db = await const Kdbx3Reader()
            .read(bytes, cred, compressor: const GzipCompressor());
        // dgvault writes KDBX4; a save() upgrades the legacy file to v4.
        _header = _freshHeader(KdfParams.argon2idDefault(), DatabaseCipher.aes256);
      } else {
        _db = await _codec.read(bytes, cred);
        _header = KdbxHeader.read(bytes);
      }
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

  // ---- mutations ----------------------------------------------------------

  bool get recycleBinEnabled => _db?.meta.recycleBinEnabled ?? true;

  void setRecycleBinEnabled(bool value) {
    final db = _db;
    if (db == null) return;
    db.meta.recycleBinEnabled = value;
    _touch();
  }

  /// The group directly containing [entry], or null.
  Group? findGroupOf(Entry entry) {
    final db = _db;
    if (db == null) return null;
    Group? walk(Group g) {
      if (g.entries.any((e) => identical(e, entry))) return g;
      for (final c in g.groups) {
        final r = walk(c);
        if (r != null) return r;
      }
      return null;
    }

    return walk(db.root);
  }

  /// Add [entry] to [group] (defaults to the first non-trash group, or root).
  void addEntry(Entry entry, {Group? group}) {
    final db = _db;
    if (db == null) return;
    (group ?? _defaultAddGroup(db.root)).entries.add(entry);
    _touch();
  }

  /// History retention policy derived from the database meta (the limits the
  /// user sets in Settings).
  EntryHistoryPolicy get _historyPolicy => EntryHistoryPolicy(
        maxItems: _db?.meta.historyMaxItems ?? 10,
        maxSizeBytes: _db?.meta.historyMaxSize ?? 6 * 1024 * 1024,
      );

  /// Apply [mutate] to [entry], snapshotting the prior version into History and
  /// bumping the modified time.
  void updateEntry(Entry entry, void Function(Entry draft) mutate) {
    if (_db == null) return;
    EntryHistory.record(entry, policy: _historyPolicy);
    mutate(entry);
    entry.modified = DateTime.now().toUtc();
    _touch();
  }

  /// Delete [entry]. With the recycle bin enabled it is moved to the Recycle Bin
  /// group (created if missing); otherwise it is permanently removed.
  void deleteEntry(Entry entry) {
    final db = _db;
    if (db == null) return;
    final owner = findGroupOf(entry);
    if (owner == null) return;
    owner.entries.remove(entry);
    if (db.meta.recycleBinEnabled) {
      final bin = _ensureRecycleBin(db);
      if (!identical(owner, bin)) {
        entry.modified = DateTime.now().toUtc();
        bin.entries.add(entry);
      }
    }
    _touch();
  }

  /// Restore the [index]th history version of [entry] (the pre-restore state is
  /// snapshotted first, so it is itself undoable).
  void restoreHistory(Entry entry, int index) {
    if (_db == null) return;
    EntryHistory.restore(entry, index, policy: _historyPolicy);
    entry.modified = DateTime.now().toUtc();
    _touch();
  }

  // ---- history limits -----------------------------------------------------

  int get historyMaxItems => _db?.meta.historyMaxItems ?? 10;
  int get historyMaxSize => _db?.meta.historyMaxSize ?? 6 * 1024 * 1024;

  void setHistoryMaxItems(int value) {
    final db = _db;
    if (db == null) return;
    db.meta.historyMaxItems = value;
    _touch();
  }

  void setHistoryMaxSize(int bytes) {
    final db = _db;
    if (db == null) return;
    db.meta.historyMaxSize = bytes;
    _touch();
  }

  // ---- KDF (transform rounds) ---------------------------------------------

  KdfParams? get _activeKdf => _header?.kdf;

  /// Whether the active KDF is Argon2 (vs legacy AES-KDF transform rounds).
  bool get kdfIsArgon2 => _activeKdf?.isArgon2 ?? true;

  /// Current KDF iteration / transform-round count (applied on the next save).
  int get kdfIterations => _activeKdf?.iterations ?? 0;

  /// Set the KDF iteration count. Rebuilds the pending header (fresh seeds are
  /// regenerated on save regardless), so the change takes effect on save().
  void setKdfIterations(int iterations) {
    final h = _header;
    if (h == null || iterations < 1) return;
    final cur = h.kdf;
    final next = KdfParams(
      algorithm: cur.algorithm,
      iterations: iterations,
      memoryKib: cur.memoryKib,
      parallelism: cur.parallelism,
      version: cur.version,
    );
    _header = _freshHeader(next, h.cipher);
    _touch();
  }

  /// Measure the active KDF and return the iteration count that takes roughly
  /// [target] to derive a key on this machine (KeePass-style benchmark). Does
  /// not apply the result — the caller decides whether to accept it.
  Future<int> benchmarkKdfIterations({
    Duration target = const Duration(seconds: 1),
  }) async {
    final base = _activeKdf;
    final cred = _cred ?? CompositeCredential(password: _b('benchmark'));
    if (base == null) return kdfIterations;
    // Probe with a fixed sample, time it, then scale to the target. Argon2 cost
    // is dominated by memory*passes; a few passes give a stable per-pass time.
    final probeIters = base.isArgon2 ? 4 : 50000;
    final probe = base.isArgon2
        ? KdfParams(
            algorithm: base.algorithm,
            iterations: probeIters,
            memoryKib: base.memoryKib,
            parallelism: base.parallelism,
            version: base.version,
          )
        : KdfParams(algorithm: base.algorithm, iterations: probeIters);
    const kdf = DefaultKeyDerivation();
    final sw = Stopwatch()..start();
    await kdf.deriveKey(cred, probe, _rand(32));
    sw.stop();
    final perIterUs = sw.elapsedMicroseconds / probeIters;
    if (perIterUs <= 0) return kdfIterations;
    final suggested = (target.inMicroseconds / perIterUs).round();
    return suggested.clamp(1, base.isArgon2 ? 1000 : 100000000);
  }

  // ---- folders ------------------------------------------------------------

  /// The parent group of [group] in the tree, or null for the root / not found.
  Group? findParentOf(Group group) {
    final db = _db;
    if (db == null || identical(group, db.root)) return null;
    Group? walk(Group g) {
      if (g.groups.any((c) => identical(c, group))) return g;
      for (final c in g.groups) {
        final r = walk(c);
        if (r != null) return r;
      }
      return null;
    }

    return walk(db.root);
  }

  /// Create a child folder named [name] under [parent] (defaults to root).
  Group addGroup(String name, {Group? parent}) {
    final db = _db;
    if (db == null) throw StateError('no open database');
    final g = Group(uuid: _uuid(), name: name.trim());
    (parent ?? db.root).groups.add(g);
    _touch();
    return g;
  }

  /// Rename [group].
  void renameGroup(Group group, String name) {
    if (_db == null) return;
    group.name = name.trim();
    _touch();
  }

  /// Delete [group] and its subtree. With the recycle bin enabled (and the
  /// group not already inside it) the subtree is moved to the Recycle Bin;
  /// otherwise it is permanently removed. The root and the bin itself are never
  /// trashed.
  void deleteGroup(Group group) {
    final db = _db;
    if (db == null || identical(group, db.root)) return;
    final parent = findParentOf(group);
    if (parent == null) return;
    parent.groups.remove(group);
    final binUuid = db.meta.recycleBinUuid;
    if (db.meta.recycleBinEnabled && group.uuid != binUuid) {
      final bin = _ensureRecycleBin(db);
      if (!identical(parent, bin) && !_isDescendant(group, bin)) {
        bin.groups.add(group);
      }
    } else if (group.uuid == binUuid) {
      db.meta.recycleBinUuid = null; // deleted the bin itself
    }
    _touch();
  }

  bool _isDescendant(Group ancestor, Group node) {
    for (final c in ancestor.groups) {
      if (identical(c, node) || _isDescendant(c, node)) return true;
    }
    return false;
  }

  Group _defaultAddGroup(Group root) {
    final rb = recycleBinUuid;
    return root.groups.firstWhere(
      (g) => g.uuid != rb,
      orElse: () => root,
    );
  }

  Group _ensureRecycleBin(Database db) {
    final rb = db.meta.recycleBinUuid;
    if (rb != null) {
      final found = _findGroupByUuid(db.root, rb);
      if (found != null) return found;
    }
    final bin = Group(uuid: _uuid(), name: 'Recycle Bin', iconId: 43);
    db.root.groups.add(bin);
    db.meta.recycleBinUuid = bin.uuid;
    return bin;
  }

  Group? _findGroupByUuid(Group g, String uuid) {
    if (g.uuid == uuid) return g;
    for (final c in g.groups) {
      final r = _findGroupByUuid(c, uuid);
      if (r != null) return r;
    }
    return null;
  }

  void _touch() {
    _dirty = true;
    notifyListeners();
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

  /// A fresh KDBX-style (base64 of 16 bytes) UUID for a new entry/group.
  String newUuid() => _uuid();
}
