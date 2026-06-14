// Critic-owned security audit for the local-only database guarantee.
//
// Composer's suite already covers the 3-layer invariant (construct/relocate/
// SyncGuard) thoroughly. This adds the one re-entry gap: the local-only flag is
// protected on *relocate* but not on *re-register* — overwriting an existing
// local-only id with a non-local-only descriptor silently lifts the guarantee.
//
// Toolchain not installed here; assertions traced against source by hand
// (see reviews/Critic-round-19.md).

import 'package:dgvault/data/database_registry.dart';
import 'package:test/test.dart';

StorageLocation _local(String p) =>
    StorageLocation(kind: StorageKind.localFile, identifier: p);
StorageLocation _remote() =>
    const StorageLocation(kind: StorageKind.dropbox, identifier: 'acct/x');

void main() {
  test('relocate protects local-only (baseline) — rejected to remote', () {
    final reg = DatabaseRegistry()
      ..register(DatabaseDescriptor(
          id: 'x', name: 'Vault', location: _local('/v.kdbx'), localOnly: true));
    expect(() => reg.relocate('x', _remote()), throwsA(isA<LocalOnlyViolation>()));
    expect(reg['x']!.location.isLocal, isTrue, reason: 'unchanged after rejection');
  });

  test('FIXED R20: re-registering a local-only id as non-local-only is rejected', () {
    final reg = DatabaseRegistry()
      ..register(DatabaseDescriptor(
          id: 'x', name: 'Vault', location: _local('/v.kdbx'), localOnly: true));
    expect(reg['x']!.localOnly, isTrue);

    // The downgrade attempt now throws instead of silently lifting the guarantee.
    expect(
      () => reg.register(DatabaseDescriptor(
          id: 'x', name: 'Vault', location: _remote(), localOnly: false)),
      throwsA(isA<LocalOnlyViolation>()),
    );

    // The original local-only descriptor is intact; it never becomes syncable.
    expect(reg['x']!.localOnly, isTrue);
    expect(reg.syncableDatabases.map((d) => d.id), isNot(contains('x')));
  });

  test('re-registering local-only as local-only (and upgrades) still work', () {
    final reg = DatabaseRegistry()
      ..register(DatabaseDescriptor(
          id: 'x', name: 'V', location: _local('/a.kdbx'), localOnly: true));
    // Same guarantee, new local path — allowed.
    reg.register(DatabaseDescriptor(
        id: 'x', name: 'V', location: _local('/b.kdbx'), localOnly: true));
    expect(reg['x']!.location.identifier, '/b.kdbx');

    // Upgrading a non-local-only id TO local-only is allowed (more restrictive).
    reg.register(DatabaseDescriptor(id: 'y', name: 'Y', location: _local('/y.kdbx')));
    reg.register(DatabaseDescriptor(
        id: 'y', name: 'Y', location: _local('/y.kdbx'), localOnly: true));
    expect(reg['y']!.localOnly, isTrue);
  });
}
