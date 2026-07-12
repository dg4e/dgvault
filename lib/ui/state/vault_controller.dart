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

import 'package:dgvault/core/backup/backup_rotation.dart';
import 'package:dgvault/core/core.dart';
import 'package:dgvault/core/crypto/impl/argon2_kdf.dart';
import 'package:dgvault/core/crypto/impl/kdbx3_reader.dart';
import 'package:dgvault/core/crypto/impl/kdbx4_body_cipher.dart';
import 'package:dgvault/core/crypto/impl/kdf_registry.dart';
import 'package:dgvault/data/format/gzip_compressor.dart';

import 'documents.dart';

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

  /// Wipe any auto-clearing clipboard secret when the vault locks. Wired to the
  /// app-wide ClipboardService; null in tests / headless use. The service guards
  /// the wipe so it only clears if the clipboard still holds our copied secret.
  Future<void> Function()? onLockClearClipboard;

  /// Invoked when a MANUAL lock is requested while the vault has unsaved edits,
  /// so the UI can surface a save/discard/cancel decision instead of silently
  /// destroying the edits. Wired by the app; when null (tests / headless) the
  /// controller falls back to saving-before-lock if a writable path is known,
  /// so data is never lost by default. Return true to proceed with the lock
  /// (the caller has handled the edits, e.g. saved or the user chose discard),
  /// false to abort the lock and stay unlocked.
  Future<bool> Function()? onManualLockWhileDirty;

  /// Fired when a reopenable vault is opened/created, with its location token
  /// (filesystem path or mobile in-place document token) and display name. The
  /// app wires this to the recent-vaults store; null in tests / read-only opens.
  void Function(String location, String name)? onVaultAccessed;

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
  bool get isDirty => _dirty;
  bool _dirty = false;

  // Monotonic counter bumped on every mutation; save() uses it to detect edits
  // that land while an async write is in flight (so they aren't marked clean).
  int _mutationSeq = 0;
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
    // A path means the file can be reopened later → offer it as a recent.
    if (path != null) onVaultAccessed?.call(path, name);
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
    if (status == VaultStatus.saving) return; // reentrancy guard
    // Snapshot the mutation count: serialize/write awaits below let the UI run,
    // so an edit can land mid-save. If one does, the vault stays dirty (and the
    // edit is re-saved) rather than being silently marked clean.
    final seqAtStart = _mutationSeq;
    status = VaultStatus.saving;
    notifyListeners();
    try {
      final header = _freshHeader(h.kdf, h.cipher);
      final out = await _codec.write(db, header, cred);
      await _writeLocation(p, out);
      _bytes = out;
      _header = header;
      _dirty = _mutationSeq != seqAtStart; // edited during the write → still dirty
      error = null;
    } catch (e) {
      error = 'save failed: $e';
    }
    status = VaultStatus.unlocked;
    notifyListeners();
  }

  /// Create a new empty vault at [location] protected by [password], and open
  /// it. [location] is a filesystem path or a mobile in-place document token
  /// (Android SAF URI / iOS bookmark); [displayName] is the human-readable name
  /// for the latter.
  Future<void> createNew(String location, String password,
      {String? displayName,}) async {
    status = VaultStatus.unlocking;
    notifyListeners();
    try {
      final name = displayName ?? location.split(Platform.pathSeparator).last;
      final db = Database(
        meta: DatabaseMeta(name: name.replaceAll('.kdbx', '')),
        root: Group(uuid: _uuid(), name: 'Root'),
      );
      final cred = CompositeCredential(password: _b(password));
      final header =
          _freshHeader(KdfParams.argon2idDefault(), DatabaseCipher.aes256);
      final out = await _codec.write(db, header, cred);
      await _writeLocation(location, out);

      _bytes = out;
      _header = header;
      _cred = cred;
      _db = db;
      path = location;
      fileName = name;
      _dirty = false;
      error = null;
      status = VaultStatus.unlocked;
      onVaultAccessed?.call(location, name);
    } catch (e) {
      status = VaultStatus.noVault;
      error = 'create failed: $e';
    }
    notifyListeners();
  }

  /// Write vault bytes to [location] — a mobile in-place document token (Android
  /// SAF URI / iOS security-scoped bookmark, via the [Documents] bridge) or a
  /// plain filesystem path.
  ///
  /// Mobile document-bridge tokens are opaque handles that cannot be temp-file +
  /// renamed, so they keep the existing in-place write. Plain filesystem paths
  /// (desktop) get a crash-safe atomic write with a pre-overwrite backup.
  Future<void> _writeLocation(String location, Uint8List bytes) async {
    if (Documents.isDocumentUri(location)) {
      // The bridge owns the file; it can't be renamed over. Write in place.
      await Documents.write(location, bytes);
    } else {
      await _writeFileAtomic(location, bytes);
    }
  }

  /// Backup-rotation policy for pre-overwrite safety copies (keep the last 5).
  static const _backupRotator = BackupRotator();

  /// Crash-safe write for a filesystem path: snapshot the current file as a
  /// timestamped backup, write the new bytes to a temp file (fsync'd), then
  /// atomically rename it over the target so a crash / disk-full mid-write can
  /// never leave a truncated or partial vault. Old backups are rotated.
  Future<void> _writeFileAtomic(String location, Uint8List bytes) async {
    final target = File(location);

    // 1. Pre-overwrite backup of the existing vault (best effort — a missing
    //    target just means there's nothing to back up yet, e.g. createNew).
    if (target.existsSync()) {
      try {
        final now = DateTime.now();
        final name = _backupRotator.nextBackupName(location, now);
        await target.copy(name);
        await _rotateBackups(target, now);
      } catch (_) {
        // A failed backup must not block the save itself.
      }
    }

    // 2. Write to a sibling temp file and fsync it before the rename.
    final tmp = File('$location.tmp-${_rand(6).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');
    try {
      await tmp.writeAsBytes(bytes, flush: true);
      // 3. Atomic replace: rename over the target on the same filesystem.
      await tmp.rename(location);
    } catch (e) {
      if (tmp.existsSync()) {
        try {
          await tmp.delete();
        } catch (_) {/* best effort cleanup */}
      }
      rethrow;
    }
  }

  /// Delete backups beyond the retention policy for [target].
  Future<void> _rotateBackups(File target, DateTime now) async {
    final dir = target.parent;
    final base = target.path.split(Platform.pathSeparator).last;
    final prefix = '$base.';
    final entries = <BackupEntry>[];
    for (final f in dir.listSync().whereType<File>()) {
      final name = f.path.split(Platform.pathSeparator).last;
      if (name.startsWith(prefix) && name.endsWith('.kdbx.bak')) {
        entries.add(BackupEntry(id: f.path, createdAt: f.statSync().modified));
      }
    }
    for (final e in _backupRotator.selectForDeletion(entries, now: now)) {
      try {
        await File(e.id).delete();
      } catch (_) {/* best effort */}
    }
  }

  // ---- lifecycle ----------------------------------------------------------

  /// Surface a user-facing error (e.g. a failed file picker) on the UI.
  void reportError(String message) {
    error = message;
    notifyListeners();
  }

  /// Lock the open database (keep the file loaded for re-unlock). Wipes any
  /// auto-clearing clipboard secret (guarded, so it won't clobber a value the
  /// user has since copied).
  ///
  /// Unsaved edits are never silently lost:
  ///   • AUTO lock (idle / refocus, driven by AutoLockGate): if the vault is
  ///     dirty and a writable location is known, it is saved before locking.
  ///     If the save fails the lock is aborted (the vault stays unlocked) so the
  ///     edits survive rather than being wiped.
  ///   • MANUAL lock while dirty: the UI hook (onManualLockWhileDirty) decides
  ///     save/discard/cancel; with no hook the controller saves-before-lock when
  ///     a writable path is known (never discards by default). A cancel aborts.
  ///
  /// Returns true if the vault locked, false if the lock was aborted (still
  /// unlocked, edits preserved).
  Future<bool> lock({bool auto = false}) async {
    // Nothing open → just clear clipboard and settle state.
    if (_db == null) {
      _finishLock();
      return true;
    }
    if (_dirty) {
      final proceed = auto ? await _saveBeforeAutoLock() : await _resolveDirtyManualLock();
      if (!proceed) {
        // Abort: keep the vault unlocked so the unsaved edits are not lost.
        notifyListeners();
        return false;
      }
    }
    _finishLock();
    return true;
  }

  /// Save the dirty vault before an automatic lock. Auto-lock is a SECURITY
  /// control (idle / refocus timeout), so it always proceeds to lock; it just
  /// persists the edits first when a writable location is known. If the save
  /// fails the lock is aborted so the in-memory edits are not wiped along with
  /// the secrets — the user gets another chance to save.
  Future<bool> _saveBeforeAutoLock() async {
    if (path == null) {
      // No writable location (e.g. a pathless/imported load): nothing to persist
      // to. A security timeout must still lock — proceed.
      return true;
    }
    await save();
    return error == null; // save() reports failures via `error`
  }

  /// Resolve a manual lock on a dirty vault. Defers to the UI hook if wired
  /// (save/discard/cancel); otherwise saves-before-lock when a writable path is
  /// known and never silently discards edits — if it can't save, it aborts.
  Future<bool> _resolveDirtyManualLock() async {
    final hook = onManualLockWhileDirty;
    if (hook != null) return hook();
    if (path == null) return false; // can't save & won't discard → abort
    await save();
    return error == null;
  }

  void _finishLock() {
    onLockClearClipboard?.call();
    _wipeSecrets();
    _db = null;
    _cred = null;
    error = null;
    status = _bytes != null ? VaultStatus.locked : VaultStatus.noVault;
    notifyListeners();
  }

  /// Close the file entirely (back to the landing screen).
  void close() {
    _wipeSecrets();
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

  @override
  void dispose() {
    _wipeSecrets();
    super.dispose();
  }

  /// Best-effort zeroing of plaintext secrets before dropping the database, per
  /// the ProtectedValue memory-protection contract. Disposes every field value
  /// (live entries and their history) and zeroes the credential bytes.
  void _wipeSecrets() {
    final db = _db;
    if (db != null) {
      for (final entry in db.root.allEntries) {
        for (final field in entry.fields.values) {
          field.value.dispose();
        }
        for (final version in entry.history) {
          for (final field in version.fields.values) {
            field.value.dispose();
          }
        }
      }
    }
    final cred = _cred;
    if (cred != null) {
      _zero(cred.password);
      _zero(cred.keyFile);
      _zero(cred.challengeResponse);
    }
  }

  void _zero(Uint8List? bytes) {
    if (bytes == null) return;
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = 0;
    }
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

  /// Free-text notes/description stored on the vault itself (KDBX Meta).
  String get databaseDescription => _db?.meta.description ?? '';

  void setDatabaseDescription(String value) {
    final db = _db;
    if (db == null) return;
    db.meta.description = value.trim().isEmpty ? null : value;
    _touch();
  }

  // ---- auto-lock (minutes; 0 = off) — persisted in the vault's custom data ---

  static const _kIdleLock = 'dgvault.idleLockMinutes';
  static const _kFocusLock = 'dgvault.focusLockMinutes';

  int _customInt(String key) =>
      int.tryParse(_db?.meta.customData[key] ?? '') ?? 0;

  void _setCustomInt(String key, int value) {
    final db = _db;
    if (db == null) return;
    if (value <= 0) {
      db.meta.customData.remove(key);
    } else {
      db.meta.customData[key] = '$value';
    }
    _touch();
  }

  /// Lock after this many idle minutes (0 = off).
  int get idleLockMinutes => _customInt(_kIdleLock);
  set idleLockMinutes(int m) => _setCustomInt(_kIdleLock, m);

  /// Lock after this many minutes away once focus returns (0 = off).
  int get focusLockMinutes => _customInt(_kFocusLock);
  set focusLockMinutes(int m) => _setCustomInt(_kFocusLock, m);

  /// The active auto-lock policy derived from the current settings.
  AutoLockPolicy get autoLockPolicy => AutoLockPolicy(
        idleTimeout: Duration(minutes: idleLockMinutes),
        focusTimeout: Duration(minutes: focusLockMinutes),
      );

  bool get isUnlocked =>
      status == VaultStatus.unlocked || status == VaultStatus.saving;

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

  /// Reorder [group]'s direct entries (drag-and-drop). [newIndex] follows the
  /// Flutter ReorderableListView convention (index into the pre-removal list).
  void reorderEntries(Group group, int oldIndex, int newIndex) {
    if (_db == null) return;
    if (oldIndex < 0 || oldIndex >= group.entries.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    final e = group.entries.removeAt(oldIndex);
    group.entries.insert(newIndex.clamp(0, group.entries.length), e);
    _touch();
  }

  /// Reorder [parent]'s child folders (already resolved sibling indices).
  void reorderGroups(Group parent, int oldIndex, int newIndex) {
    if (_db == null) return;
    if (oldIndex < 0 || oldIndex >= parent.groups.length) return;
    final g = parent.groups.removeAt(oldIndex);
    parent.groups.insert(newIndex.clamp(0, parent.groups.length), g);
    _touch();
  }

  /// Move [entry] into [target] (no-op if it is already there).
  void moveEntry(Entry entry, Group target) {
    if (_db == null) return;
    final owner = findGroupOf(entry);
    if (owner == null || identical(owner, target)) return;
    owner.entries.remove(entry);
    target.entries.add(entry);
    entry.modified = DateTime.now().toUtc();
    _touch();
  }

  /// Re-parent [group] under [target]. Refused for the root, for moves into the
  /// group's own subtree (would create a cycle), and for no-op moves.
  void moveGroup(Group group, Group target) {
    final db = _db;
    if (db == null || identical(group, db.root) || identical(group, target)) {
      return;
    }
    if (_isDescendant(group, target)) return; // can't move into own subtree
    final parent = findParentOf(group);
    if (parent == null || identical(parent, target)) return;
    parent.groups.remove(group);
    target.groups.add(group);
    _touch();
  }

  /// Whether [group] may be moved under [target] (used to filter the picker).
  bool canMoveGroupInto(Group group, Group target) {
    final db = _db;
    if (db == null || identical(group, db.root)) return false;
    if (identical(group, target) || _isDescendant(group, target)) return false;
    return !identical(findParentOf(group), target);
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
    _mutationSeq++;
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
