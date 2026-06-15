import 'package:dgvault/core/backup/backup_rotation.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 6, 14, 12, 0, 0);

  // Helper: a backup created [daysAgo] days before `now`.
  BackupEntry old(String id, int daysAgo) =>
      BackupEntry(id: id, createdAt: now.subtract(Duration(days: daysAgo)));

  group('keepLast', () {
    test('keepLast alone is a floor, not a cap: nothing deleted without age/count rules', () {
      // Safety semantics (Critic R15): keepLast only protects the N newest; it
      // never triggers deletion on its own. Capping requires maxTotalCount.
      final entries = [old('a', 0), old('b', 1), old('c', 2), old('d', 3)];
      const r = BackupRotator(policy: BackupRetentionPolicy(keepLast: 2));
      expect(r.selectForDeletion(entries, now: now), isEmpty);
      expect(r.retained(entries, now: now).map((e) => e.id), ['a', 'b', 'c', 'd']);
    });

    test('keepLast protects recent snapshots even when maxAge would drop them', () {
      final entries = [old('a', 400), old('b', 401)];
      const r = BackupRotator(
        policy: BackupRetentionPolicy(keepLast: 2, maxAge: Duration(days: 30)),
      );
      // both are ancient, but keepLast=2 protects both
      expect(r.selectForDeletion(entries, now: now), isEmpty);
    });
  });

  group('maxAge', () {
    test('deletes snapshots older than maxAge beyond keepLast', () {
      final entries = [old('a', 1), old('b', 10), old('c', 40), old('d', 80)];
      const r = BackupRotator(
        policy: BackupRetentionPolicy(keepLast: 1, maxAge: Duration(days: 30)),
      );
      final del = r.selectForDeletion(entries, now: now).map((e) => e.id).toSet();
      // 'a' protected (keepLast); 'b' within 30d; 'c','d' too old
      expect(del, {'c', 'd'});
    });
  });

  group('maxTotalCount', () {
    test('caps the total number retained', () {
      final entries = [old('a', 0), old('b', 1), old('c', 2), old('d', 3), old('e', 4)];
      const r = BackupRotator(
        policy: BackupRetentionPolicy(keepLast: 1, maxTotalCount: 3),
      );
      final del = r.selectForDeletion(entries, now: now).map((e) => e.id).toSet();
      // indices >=3 deleted → 'd','e'
      expect(del, {'d', 'e'});
      expect(r.retained(entries, now: now).length, 3);
    });

    test('rejects maxTotalCount below keepLast', () {
      expect(
        () => BackupRetentionPolicy(keepLast: 5, maxTotalCount: 3),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('combined + edges', () {
    test('empty input yields no deletions', () {
      const r = BackupRotator();
      expect(r.selectForDeletion(const [], now: now), isEmpty);
    });

    test('unsorted input is handled newest-first', () {
      final entries = [old('mid', 2), old('new', 0), old('old', 5)];
      // keepLast=1 floor + a count cap of 1 so deletion actually fires; the
      // point is that unsorted input is still resolved newest-first.
      const r = BackupRotator(
          policy: BackupRetentionPolicy(keepLast: 1, maxTotalCount: 1),);
      expect(r.retained(entries, now: now).map((e) => e.id).first, 'new');
      expect(r.selectForDeletion(entries, now: now).map((e) => e.id).toSet(),
          {'mid', 'old'},);
    });
  });

  group('nextBackupName', () {
    test('emits a lexically-sortable UTC timestamped name (ms resolution)', () {
      final name = const BackupRotator().nextBackupName('vault', now);
      expect(name, 'vault.20260614T120000000.kdbx.bak');
    });

    test('lexical order matches chronological order', () {
      const r = BackupRotator();
      final earlier = r.nextBackupName('v', DateTime.utc(2026, 1, 1, 0, 0, 0));
      final later = r.nextBackupName('v', DateTime.utc(2026, 12, 31, 23, 59, 59));
      expect(earlier.compareTo(later) < 0, isTrue);
    });

    test('sequence suffix disambiguates same-instant backups (R15 minor)', () {
      const r = BackupRotator();
      final a = r.nextBackupName('v', now, sequence: 0);
      final b = r.nextBackupName('v', now, sequence: 1);
      expect(a, isNot(b));
      expect(a.compareTo(b) < 0, isTrue, reason: 'sequence preserves order');
    });
  });
}
