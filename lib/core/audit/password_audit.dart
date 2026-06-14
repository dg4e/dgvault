// dgvault — password health audit ("Find Weaknesses" + "Find Similar").
//
// Pure Dart. Operates on the decrypted in-memory model only — no crypto, no
// network (online breach checks are a separate, optional online feature). All
// thresholds are configurable and `now` is injectable so the audit is fully
// deterministic and unit-testable.
//
// Checks:
//   • emptyPassword   — entry has no / blank password.
//   • weakPassword    — estimated entropy below [AuditConfig.weakEntropyBits].
//   • reusedPassword  — the exact same password is used by >1 entry.
//   • similarPassword — two entries' passwords are near-duplicates
//                       (normalized edit-distance ≥ [AuditConfig.similarityThreshold])
//                       without being identical.
//   • oldPassword     — last modified longer ago than [AuditConfig.maxPasswordAge].

import 'dart:math';

import '../model/entry.dart';
import '../model/field.dart';

enum AuditIssue {
  emptyPassword,
  weakPassword,
  reusedPassword,
  similarPassword,
  oldPassword,
}

/// Relative severity, useful for sorting/UI grouping.
enum AuditSeverity { info, low, medium, high }

class AuditFinding {
  AuditFinding({
    required this.issue,
    required this.severity,
    required this.entryUuid,
    required this.entryTitle,
    required this.detail,
    this.metric,
    this.relatedUuids = const <String>[],
  });

  final AuditIssue issue;
  final AuditSeverity severity;
  final String entryUuid;
  final String entryTitle;
  final String detail;

  /// Entropy bits (weak) or similarity score (similar), when applicable.
  final double? metric;

  /// Other entries implicated (reused/similar groups).
  final List<String> relatedUuids;

  @override
  String toString() =>
      '[$severity] ${issue.name} "$entryTitle" ($entryUuid): $detail';
}

class AuditConfig {
  const AuditConfig({
    this.weakEntropyBits = 50,
    this.maxPasswordAge = const Duration(days: 365),
    this.similarityThreshold = 0.80,
    this.checkAge = true,
  });

  /// Passwords with estimated entropy below this are flagged weak.
  final double weakEntropyBits;

  /// Passwords last modified longer ago than this are flagged old.
  final Duration maxPasswordAge;

  /// Normalized similarity (0..1) at/above which two passwords are "similar".
  final double similarityThreshold;

  /// Disable age checks when entries lack reliable timestamps.
  final bool checkAge;
}

/// Estimate password entropy as `length * log2(poolSize)`, where the pool is the
/// union of character classes present. This is the standard upper-bound estimate
/// — it does not detect dictionary words; a future zxcvbn pass can refine it.
double estimatePasswordEntropyBits(String pw) {
  if (pw.isEmpty) return 0;
  var pool = 0;
  if (RegExp(r'[a-z]').hasMatch(pw)) pool += 26;
  if (RegExp(r'[A-Z]').hasMatch(pw)) pool += 26;
  if (RegExp(r'[0-9]').hasMatch(pw)) pool += 10;
  if (RegExp(r'[^a-zA-Z0-9]').hasMatch(pw)) pool += 33; // printable-symbol approx
  if (pool == 0) return 0;
  return pw.length * (log(pool) / log(2));
}

/// Levenshtein edit distance.
int levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  var curr = List<int>.filled(b.length + 1, 0);
  for (var i = 0; i < a.length; i++) {
    curr[0] = i + 1;
    for (var j = 0; j < b.length; j++) {
      final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
      curr[j + 1] = [
        curr[j] + 1, // insertion
        prev[j + 1] + 1, // deletion
        prev[j] + cost, // substitution
      ].reduce(min);
    }
    final tmp = prev;
    prev = curr;
    curr = tmp;
  }
  return prev[b.length];
}

/// Normalized similarity in 0..1 (1 = identical).
double passwordSimilarity(String a, String b) {
  if (a.isEmpty && b.isEmpty) return 1;
  final maxLen = max(a.length, b.length);
  if (maxLen == 0) return 1;
  return 1 - levenshtein(a, b) / maxLen;
}

class PasswordAuditor {
  PasswordAuditor({this.config = const AuditConfig()});

  final AuditConfig config;

  String? _password(Entry e) => e.fields[Field.password]?.value.reveal();
  String _title(Entry e) => e.title ?? '(untitled)';

  /// Run every enabled check over [entries].
  List<AuditFinding> audit(Iterable<Entry> entries, {DateTime? now}) {
    final list = entries.toList(growable: false);
    return <AuditFinding>[
      ...findWeakOrEmpty(list),
      ...findReused(list),
      ...findSimilar(list),
      if (config.checkAge) ...findOld(list, now: now ?? _epochFallback(list)),
    ];
  }

  // Fallback only used if caller omits `now` and entries carry timestamps; we
  // avoid Date.now() (non-deterministic) — callers should pass `now` explicitly.
  DateTime _epochFallback(List<Entry> entries) {
    DateTime? latest;
    for (final e in entries) {
      final m = e.modified;
      if (m != null && (latest == null || m.isAfter(latest))) latest = m;
    }
    return latest ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  List<AuditFinding> findWeakOrEmpty(Iterable<Entry> entries) {
    final out = <AuditFinding>[];
    for (final e in entries) {
      final pw = _password(e);
      if (pw == null || pw.isEmpty) {
        out.add(AuditFinding(
          issue: AuditIssue.emptyPassword,
          severity: AuditSeverity.high,
          entryUuid: e.uuid,
          entryTitle: _title(e),
          detail: 'Entry has no password set.',
        ));
        continue;
      }
      final bits = estimatePasswordEntropyBits(pw);
      if (bits < config.weakEntropyBits) {
        out.add(AuditFinding(
          issue: AuditIssue.weakPassword,
          severity: bits < config.weakEntropyBits / 2
              ? AuditSeverity.high
              : AuditSeverity.medium,
          entryUuid: e.uuid,
          entryTitle: _title(e),
          detail: 'Estimated entropy ${bits.toStringAsFixed(1)} bits '
              '(< ${config.weakEntropyBits.toStringAsFixed(0)}).',
          metric: bits,
        ));
      }
    }
    return out;
  }

  List<AuditFinding> findReused(Iterable<Entry> entries) {
    final byPw = <String, List<Entry>>{};
    for (final e in entries) {
      final pw = _password(e);
      if (pw == null || pw.isEmpty) continue;
      byPw.putIfAbsent(pw, () => <Entry>[]).add(e);
    }
    final out = <AuditFinding>[];
    for (final group in byPw.values) {
      if (group.length < 2) continue;
      final uuids = group.map((e) => e.uuid).toList();
      for (final e in group) {
        out.add(AuditFinding(
          issue: AuditIssue.reusedPassword,
          severity: AuditSeverity.high,
          entryUuid: e.uuid,
          entryTitle: _title(e),
          detail: 'Password reused across ${group.length} entries.',
          relatedUuids: uuids.where((u) => u != e.uuid).toList(),
        ));
      }
    }
    return out;
  }

  /// Flag pairs of near-duplicate (but not identical) passwords. Identical
  /// passwords are covered by [findReused] and excluded here.
  List<AuditFinding> findSimilar(Iterable<Entry> entries) {
    final withPw = <Entry>[];
    for (final e in entries) {
      final pw = _password(e);
      if (pw != null && pw.isNotEmpty) withPw.add(e);
    }
    final out = <AuditFinding>[];
    for (var i = 0; i < withPw.length; i++) {
      for (var j = i + 1; j < withPw.length; j++) {
        final a = _password(withPw[i])!;
        final b = _password(withPw[j])!;
        if (a == b) continue; // identical → reused, not similar
        final sim = passwordSimilarity(a, b);
        if (sim >= config.similarityThreshold) {
          final ei = withPw[i], ej = withPw[j];
          final detail =
              'Password ${(sim * 100).toStringAsFixed(0)}% similar to '
              'another entry.';
          out.add(AuditFinding(
            issue: AuditIssue.similarPassword,
            severity: AuditSeverity.medium,
            entryUuid: ei.uuid,
            entryTitle: _title(ei),
            detail: detail,
            metric: sim,
            relatedUuids: [ej.uuid],
          ));
          out.add(AuditFinding(
            issue: AuditIssue.similarPassword,
            severity: AuditSeverity.medium,
            entryUuid: ej.uuid,
            entryTitle: _title(ej),
            detail: detail,
            metric: sim,
            relatedUuids: [ei.uuid],
          ));
        }
      }
    }
    return out;
  }

  List<AuditFinding> findOld(Iterable<Entry> entries, {required DateTime now}) {
    final out = <AuditFinding>[];
    for (final e in entries) {
      final pw = _password(e);
      if (pw == null || pw.isEmpty) continue;
      final modified = e.modified;
      if (modified == null) continue;
      final age = now.difference(modified);
      if (age > config.maxPasswordAge) {
        out.add(AuditFinding(
          issue: AuditIssue.oldPassword,
          severity: AuditSeverity.low,
          entryUuid: e.uuid,
          entryTitle: _title(e),
          detail: 'Password unchanged for ${age.inDays} days.',
          metric: age.inDays.toDouble(),
        ));
      }
    }
    return out;
  }
}
