// dgvault — local database registry + local-only enforcement.
//
// Tracks the databases the app knows about and where each is stored, and
// enforces the "Local Only Databases" guarantee: a database marked local-only
// must never be given a remote storage target or be handed to a sync engine.
// This is the pure policy layer; the actual file I/O and provider clients live
// in the platform layer and consult this guard before doing anything.

/// Where a database lives. Only [localFile] is "local"; every other kind is a
/// remote/sync target that a local-only database must never use.
enum StorageKind {
  localFile,
  iCloud,
  googleDrive,
  dropbox,
  oneDrive,
  sharePoint,
  sftp,
  webdav,
  nextcloud,
}

extension StorageKindX on StorageKind {
  bool get isLocal => this == StorageKind.localFile;
  bool get isRemote => !isLocal;
}

class StorageLocation {
  const StorageLocation({
    required this.kind,
    required this.identifier,
    this.displayName,
  });

  /// Where the database is stored.
  final StorageKind kind;

  /// Path (local) or URI/account-scoped id (remote).
  final String identifier;

  final String? displayName;

  bool get isLocal => kind.isLocal;
  bool get isRemote => kind.isRemote;
}

/// Thrown when an operation would violate a database's local-only guarantee.
class LocalOnlyViolation implements Exception {
  LocalOnlyViolation(this.message);
  final String message;
  @override
  String toString() => 'LocalOnlyViolation: $message';
}

class DatabaseDescriptor {
  DatabaseDescriptor({
    required this.id,
    required this.name,
    required this.location,
    this.localOnly = false,
  }) {
    if (localOnly && location.isRemote) {
      throw LocalOnlyViolation(
        'database "$name" is local-only but has a ${location.kind.name} location',
      );
    }
  }

  final String id;
  final String name;
  final StorageLocation location;

  /// When true, the database may only ever live in local storage and must never
  /// be synced to a remote provider.
  final bool localOnly;

  DatabaseDescriptor withLocation(StorageLocation newLocation) =>
      DatabaseDescriptor(
        id: id,
        name: name,
        location: newLocation,
        localOnly: localOnly,
      );
}

class DatabaseRegistry {
  final Map<String, DatabaseDescriptor> _byId = {};

  Iterable<DatabaseDescriptor> get all => _byId.values;

  /// Databases stored on the local device.
  Iterable<DatabaseDescriptor> get localDatabases =>
      _byId.values.where((d) => d.location.isLocal);

  /// Databases that are eligible to sync (remote location AND not local-only).
  Iterable<DatabaseDescriptor> get syncableDatabases =>
      _byId.values.where((d) => !d.localOnly && d.location.isRemote);

  DatabaseDescriptor? operator [](String id) => _byId[id];
  bool contains(String id) => _byId.containsKey(id);

  /// Registers (or replaces) a descriptor. Beyond the construct-time invariant,
  /// this refuses to **downgrade** an existing local-only database: re-registering
  /// the same id with `localOnly == false` (or any remote location) would
  /// silently lift the local-only guarantee and make a once-local-only vault
  /// eligible to sync out. Such a re-register is rejected.
  void register(DatabaseDescriptor descriptor) {
    final existing = _byId[descriptor.id];
    if (existing != null && existing.localOnly && !descriptor.localOnly) {
      throw LocalOnlyViolation(
        're-registering local-only database "${existing.name}" as non-local-only '
        'is not allowed (would lift the local-only guarantee)',
      );
    }
    _byId[descriptor.id] = descriptor;
  }

  bool unregister(String id) => _byId.remove(id) != null;

  /// Moves a database to [location], rejecting a remote target for a local-only
  /// database. Returns the updated descriptor.
  DatabaseDescriptor relocate(String id, StorageLocation location) {
    final existing = _byId[id];
    if (existing == null) {
      throw StateError('relocate: no database with id "$id"');
    }
    final updated = existing.withLocation(location); // throws if it would violate
    _byId[id] = updated;
    return updated;
  }
}

/// Gate the sync engine must pass before touching a database.
class SyncGuard {
  const SyncGuard();

  /// Throws when [descriptor] must not be synced: either it is local-only, or it
  /// has no remote location to sync with.
  void ensureSyncAllowed(DatabaseDescriptor descriptor) {
    if (descriptor.localOnly) {
      throw LocalOnlyViolation(
        'refusing to sync local-only database "${descriptor.name}"',
      );
    }
    if (descriptor.location.isLocal) {
      throw LocalOnlyViolation(
        'database "${descriptor.name}" has no remote target to sync with',
      );
    }
  }

  bool isSyncAllowed(DatabaseDescriptor descriptor) {
    if (descriptor.localOnly) return false;
    return descriptor.location.isRemote;
  }
}
