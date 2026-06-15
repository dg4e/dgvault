// Critic-owned audit for rolling-backup rotation (my Phase 5 backup-rotation task).
//
// The safety property that matters most for backups is the opposite of most
// delete logic: NEVER over-delete. `keepLast` must be a hard floor — the N most
// recent snapshots survive regardless of age or count caps — else a misconfig or
// a clock skew could wipe the user's only recovery point. These tests pin that
// floor plus the age/count rules and the sortable-name contract.
//
// Toolchain not installed here; assertions traced against source by hand
// (see reviews/Critic-round-15.md).

import 'package:dgvault/core/backup/backup_rotation.dart';
import 'package:test/test.dart';

final _now = DateTime.utc(2026, 6, 14, 12, 0, 0);

List<BackupEntry> _entries(int n, {Duration spacing = const Duration(days: 1)}) => [
      for (var i = 0; i < n; i++)
        BackupEntry(id: 'b$i', createdAt: _now.subtract(spacing * i)),
    ];

Set<String> _delIds(BackupRotator r, List<BackupEntry> e) =>
    r.selectForDeletion(e, now: _now).map((x) => x.id).toSet();

void main() {
  test('keepLast is a hard floor: the N most recent survive even when all are stale', () {
    // 10 snapshots, all ~years old, aggressive caps — keepLast must still win.
    final old = [
      for (var i = 0; i < 10; i++)
        BackupEntry(id: 'b$i', createdAt: _now.subtract(Duration(days: 400 + i))),
    ];
    const rot = BackupRotator(
      policy: BackupRetentionPolicy(keepLast: 5, maxAge: Duration(days: 7), maxTotalCount: 5),
    );
    final retained = rot.retained(old, now: _now);
    expect(retained.length, 5, reason: 'never delete the safety net');
    expect(retained.map((e) => e.id), ['b0', 'b1', 'b2', 'b3', 'b4']); // newest first
  });

  test('maxAge only deletes snapshots beyond keepLast', () {
    final e = _entries(8); // b0 (today) .. b7 (7 days ago)
    const rot = BackupRotator(
      policy: BackupRetentionPolicy(keepLast: 3, maxAge: Duration(days: 4)),
    );
    // protected: b0,b1,b2. Beyond that, older than 4 days → b5(5d),b6(6d),b7(7d).
    // b3(3d),b4(4d) are within maxAge (>4d is the cutoff; 4d is not >4d).
    expect(_delIds(rot, e), {'b5', 'b6', 'b7'});
  });

  test('maxTotalCount caps retention beyond keepLast', () {
    final e = _entries(10);
    const rot = BackupRotator(
      policy: BackupRetentionPolicy(keepLast: 4, maxTotalCount: 7),
    );
    // indices >= 7 deleted → b7,b8,b9.
    expect(_delIds(rot, e), {'b7', 'b8', 'b9'});
  });

  test('empty input deletes nothing', () {
    const rot = BackupRotator(policy: BackupRetentionPolicy(keepLast: 5));
    expect(rot.selectForDeletion(const [], now: _now), isEmpty);
  });

  group('nextBackupName', () {
    test('uses a zero-padded UTC timestamp so lexical order = chronological', () {
      final earlier = const BackupRotator().nextBackupName('vault', DateTime.utc(2026, 1, 2, 3, 4, 5));
      final later = const BackupRotator().nextBackupName('vault', DateTime.utc(2026, 1, 2, 3, 4, 6));
      expect(earlier, 'vault.20260102T030405000.kdbx.bak'); // ms resolution
      expect(earlier.compareTo(later) < 0, isTrue, reason: 'sortable by name');
    });

    test('R15 FIX: millisecond granularity disambiguates same-second backups', () {
      // The R15 minor (second-granularity collision) is fixed: ms resolution
      // means two backups in the same second mint distinct, still-sortable names.
      final a = const BackupRotator().nextBackupName('v', DateTime.utc(2026, 1, 1, 0, 0, 0, 100));
      final b = const BackupRotator().nextBackupName('v', DateTime.utc(2026, 1, 1, 0, 0, 0, 900));
      expect(a, isNot(b), reason: 'ms-resolved names no longer collide');
      expect(a.compareTo(b) < 0, isTrue, reason: 'earlier ms sorts first');
    });
  });
}
