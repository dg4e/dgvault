// dgvault — Rolling local backups: retention / rotation policy (pure logic).
//
// Decides which backup snapshots to keep vs delete given a retention policy, and
// mints the next backup name. Pure and deterministic — the actual file copy,
// write, and delete are the platform/data layer's job; this only decides, so it
// is fully unit-testable with no I/O.
//
// Retention rules (evaluated newest-first):
//   • keepLast      — always keep the N most recent, regardless of age/count.
//   • maxTotalCount — hard cap; never retain more than this many.
//   • maxAge        — beyond keepLast, delete snapshots older than this.

class BackupEntry {
  BackupEntry({required this.id, required this.createdAt});

  /// Stable identifier (typically the backup file name).
  final String id;
  final DateTime createdAt;
}

class BackupRetentionPolicy {
  const BackupRetentionPolicy({
    this.keepLast = 5,
    this.maxAge,
    this.maxTotalCount,
  })  : assert(keepLast >= 0),
        assert(maxTotalCount == null || maxTotalCount >= keepLast,
            'maxTotalCount must be >= keepLast');

  /// Always retain this many most-recent snapshots.
  final int keepLast;

  /// Delete snapshots (beyond [keepLast]) older than this. Null disables.
  final Duration? maxAge;

  /// Absolute cap on retained snapshots. Null disables.
  final int? maxTotalCount;
}

class BackupRotator {
  const BackupRotator({this.policy = const BackupRetentionPolicy()});

  final BackupRetentionPolicy policy;

  /// Snapshots that should be deleted under [policy], evaluated at [now].
  List<BackupEntry> selectForDeletion(
    Iterable<BackupEntry> existing, {
    required DateTime now,
  }) {
    final sorted = existing.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt)); // newest first
    final toDelete = <BackupEntry>[];
    for (var i = 0; i < sorted.length; i++) {
      if (i < policy.keepLast) continue; // protected: most recent N
      final e = sorted[i];
      final overCount =
          policy.maxTotalCount != null && i >= policy.maxTotalCount!;
      final tooOld =
          policy.maxAge != null && now.difference(e.createdAt) > policy.maxAge!;
      if (overCount || tooOld) toDelete.add(e);
    }
    return toDelete;
  }

  /// Snapshots retained after applying [policy] (complement of deletion).
  List<BackupEntry> retained(
    Iterable<BackupEntry> existing, {
    required DateTime now,
  }) {
    final del = selectForDeletion(existing, now: now).map((e) => e.id).toSet();
    return existing.where((e) => !del.contains(e.id)).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// Deterministic, sortable backup name: `<base>.<UTC-timestamp>.kdbx.bak`,
  /// timestamp `yyyyMMddTHHmmssSSS` (millisecond resolution) so lexical order
  /// matches chronological order. An optional [sequence] suffix (`-NN`)
  /// guarantees uniqueness when two backups land in the same millisecond
  /// (Critic R15 minor: second-granularity name collision).
  String nextBackupName(String base, DateTime now, {int? sequence}) {
    final u = now.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    final ms = u.millisecond.toString().padLeft(3, '0');
    final ts = '${u.year.toString().padLeft(4, '0')}${two(u.month)}'
        '${two(u.day)}T${two(u.hour)}${two(u.minute)}${two(u.second)}$ms';
    final seq = sequence == null ? '' : '-${two(sequence)}';
    return '$base.$ts$seq.kdbx.bak';
  }
}
