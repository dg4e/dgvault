import 'package:dgvault/data/database_registry.dart';
import 'package:test/test.dart';

StorageLocation _local([String path = '/vault.kdbx']) =>
    StorageLocation(kind: StorageKind.localFile, identifier: path);

StorageLocation _remote(
        [StorageKind kind = StorageKind.dropbox, String id = 'db:/v.kdbx',]) =>
    StorageLocation(kind: kind, identifier: id);

DatabaseDescriptor _desc(
  String id, {
  StorageLocation? location,
  bool localOnly = false,
}) =>
    DatabaseDescriptor(
      id: id,
      name: id,
      location: location ?? _local(),
      localOnly: localOnly,
    );

void main() {
  group('local-only invariant', () {
    test('local-only descriptor with a local location is fine', () {
      expect(() => _desc('a', localOnly: true), returnsNormally);
    });

    test('local-only descriptor with a remote location throws', () {
      expect(
        () => _desc('a', localOnly: true, location: _remote()),
        throwsA(isA<LocalOnlyViolation>()),
      );
    });

    test('relocating a local-only db to a remote target is rejected', () {
      final reg = DatabaseRegistry()..register(_desc('a', localOnly: true));
      expect(() => reg.relocate('a', _remote()),
          throwsA(isA<LocalOnlyViolation>()),);
      // Original location is untouched after the rejected relocate.
      expect(reg['a']!.location.isLocal, isTrue);
    });

    test('relocating a local-only db to another local path is allowed', () {
      final reg = DatabaseRegistry()..register(_desc('a', localOnly: true));
      final updated = reg.relocate('a', _local('/new/path.kdbx'));
      expect(updated.location.identifier, '/new/path.kdbx');
    });
  });

  group('registry views', () {
    final reg = DatabaseRegistry()
      ..register(_desc('localA', localOnly: true))
      ..register(_desc('localB', location: _local('/b.kdbx')))
      ..register(_desc('cloud', location: _remote(StorageKind.googleDrive)));

    test('localDatabases lists every locally-stored db', () {
      expect(reg.localDatabases.map((d) => d.id).toSet(),
          {'localA', 'localB'},);
    });

    test('syncableDatabases excludes local-only and local-stored dbs', () {
      expect(reg.syncableDatabases.map((d) => d.id), ['cloud']);
    });

    test('register replaces and unregister removes', () {
      final r = DatabaseRegistry()..register(_desc('x'));
      expect(r.contains('x'), isTrue);
      expect(r.unregister('x'), isTrue);
      expect(r.contains('x'), isFalse);
      expect(r.unregister('x'), isFalse);
    });
  });

  group('SyncGuard', () {
    const guard = SyncGuard();

    test('allows a remote, non-local-only database', () {
      final d = _desc('c', location: _remote(StorageKind.webdav));
      expect(guard.isSyncAllowed(d), isTrue);
      expect(() => guard.ensureSyncAllowed(d), returnsNormally);
    });

    test('refuses a local-only database', () {
      final d = _desc('a', localOnly: true);
      expect(guard.isSyncAllowed(d), isFalse);
      expect(() => guard.ensureSyncAllowed(d),
          throwsA(isA<LocalOnlyViolation>()),);
    });

    test('refuses a purely-local database (no remote target)', () {
      final d = _desc('b'); // local file, not local-only
      expect(guard.isSyncAllowed(d), isFalse);
      expect(() => guard.ensureSyncAllowed(d),
          throwsA(isA<LocalOnlyViolation>()),);
    });
  });
}
