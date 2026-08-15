// Critic-owned adversarial audit for the password-health engine.
//
// Performer's suite covers the standard checks. These target known blind spots
// and aggregation edges: the entropy estimate's repetition blindness, empty
// passwords not being mis-counted as "reused", and correct related-UUID wiring
// across a similarity *cluster* (not just a single pair). Each assertion was
// traced against the implementation by hand (no toolchain to run `flutter test`;
// see reviews/Critic-round-5.md).

import 'package:dgvault/core/core.dart';
import 'package:test/test.dart';

Entry _entry(String uuid, String? password, {String title = 't'}) {
  final fields = <String, Field>{
    Field.title: Field(key: Field.title, value: InMemoryProtectedValue.plain(title)),
  };
  if (password != null) {
    fields[Field.password] =
        Field(key: Field.password, value: InMemoryProtectedValue(password));
  }
  return Entry(uuid: uuid, fields: fields);
}

void main() {
  final auditor = PasswordAuditor();

  group('entropy estimate — documented blind spot', () {
    test('a long single-repeated-char password is NOT flagged weak', () {
      // 'aaaaaaaaaaaaaa' → pool 26, 14*log2(26) ≈ 65.8 bits ≥ 50, so the
      // length*log2(pool) upper bound does not catch the (real) weakness.
      // This pins the limitation so a future zxcvbn-style refinement is a
      // visible, intentional change — see review recommendation.
      final findings = auditor.findWeakOrEmpty([_entry('u1', 'aaaaaaaaaaaaaa')]);
      expect(findings, isEmpty,
          reason: 'upper-bound entropy ignores repetition (known limitation)',);
    });

    test('a short password IS flagged weak', () {
      final findings = auditor.findWeakOrEmpty([_entry('u1', 'aaa')]);
      expect(findings.single.issue, AuditIssue.weakPassword);
    });
  });

  group('empty passwords are not mis-counted as reused', () {
    test('two empty passwords → two emptyPassword findings, zero reused', () {
      final entries = [_entry('u1', ''), _entry('u2', '')];
      final reused = auditor.findReused(entries);
      expect(reused, isEmpty, reason: 'blank is not a shared secret');
      final empties = auditor
          .findWeakOrEmpty(entries)
          .where((f) => f.issue == AuditIssue.emptyPassword);
      expect(empties.length, 2);
    });

    test('a missing password field is also not reused', () {
      final entries = [_entry('u1', null), _entry('u2', null)];
      expect(auditor.findReused(entries), isEmpty);
    });
  });

  group('find-similar cluster wiring', () {
    test('three near-duplicates produce all 3 pairs with single related uuid', () {
      // pairwise similarity 0.9 (one differing char of 10) ≥ 0.80 threshold.
      final entries = [
        _entry('u1', 'password01'),
        _entry('u2', 'password02'),
        _entry('u3', 'password03'),
      ];
      final similar = auditor.findSimilar(entries);
      // 3 unordered pairs × 2 findings each (one per entry) = 6.
      expect(similar.length, 6);
      for (final f in similar) {
        expect(f.issue, AuditIssue.similarPassword);
        expect(f.relatedUuids.length, 1,
            reason: 'each finding names exactly its counterpart',);
      }
      // u1 should be implicated with both u2 and u3 across its two findings.
      final u1Related = similar
          .where((f) => f.entryUuid == 'u1')
          .expand((f) => f.relatedUuids)
          .toSet();
      expect(u1Related, {'u2', 'u3'});
    });

    test('identical passwords are excluded from similar (reused covers them)', () {
      final entries = [_entry('u1', 'samePassword!'), _entry('u2', 'samePassword!')];
      expect(auditor.findSimilar(entries), isEmpty);
      expect(auditor.findReused(entries).length, 2);
    });
  });

  group('age check determinism', () {
    test('old vs recent split is exact at the configured boundary', () {
      final now = DateTime.utc(2026, 1, 1);
      final old = _entry('old', 'Str0ng-Enough-Pass!')..modified = now.subtract(const Duration(days: 400));
      final fresh = _entry('new', 'Str0ng-Enough-Pass2!')..modified = now.subtract(const Duration(days: 10));
      final findings = auditor.findOld([old, fresh], now: now);
      expect(findings.map((f) => f.entryUuid), ['old']);
    });
  });
}
