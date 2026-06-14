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

  test('🟠 GAP: re-registering a local-only id as non-local-only lifts the guard', () {
    final reg = DatabaseRegistry()
      ..register(DatabaseDescriptor(
          id: 'x', name: 'Vault', location: _local('/v.kdbx'), localOnly: true));
    expect(reg['x']!.localOnly, isTrue);

    // Same id, now syncable+remote. The constructor doesn't object (localOnly is
    // false here), and register() overwrites silently — the local-only promise on
    // id 'x' is gone, and it becomes eligible to sync OUT.
    reg.register(DatabaseDescriptor(
        id: 'x', name: 'Vault', location: _remote(), localOnly: false));

    expect(reg['x']!.localOnly, isFalse, reason: 'CURRENT behaviour pinned');
    expect(reg.syncableDatabases.map((d) => d.id), contains('x'),
        reason: 'a once-local-only db can now sync out — see review hardening rec');
  });
}
