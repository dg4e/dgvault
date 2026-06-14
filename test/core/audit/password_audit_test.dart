import 'package:dgvault/core/model/entry.dart';
import 'package:dgvault/core/model/field.dart';
import 'package:dgvault/core/model/protected_value.dart';
import 'package:dgvault/core/audit/password_audit.dart';
import 'package:test/test.dart';

Entry pwEntry(String uuid, String? password,
    {String title = 't', DateTime? modified}) {
  final fields = <String, Field>{
    Field.title: Field(key: Field.title, value: InMemoryProtectedValue.plain(title)),
  };
  if (password != null) {
    fields[Field.password] =
        Field(key: Field.password, value: InMemoryProtectedValue(password));
  }
  return Entry(uuid: uuid, fields: fields, modified: modified);
}

void main() {
  group('entropy + distance helpers', () {
    test('entropy grows with length and pool', () {
      expect(estimatePasswordEntropyBits(''), 0);
      final lower = estimatePasswordEntropyBits('abcdef'); // pool 26
      final mixed = estimatePasswordEntropyBits('Abc123!x'); // pool 95
      expect(lower, greaterThan(0));
      expect(mixed, greaterThan(lower));
    });

    test('levenshtein classic vectors', () {
      expect(levenshtein('kitten', 'sitting'), 3);
      expect(levenshtein('', 'abc'), 3);
      expect(levenshtein('same', 'same'), 0);
    });

    test('similarity is 1 for identical, lower for edits', () {
      expect(passwordSimilarity('abc', 'abc'), 1.0);
      expect(passwordSimilarity('Summer2023!', 'Summer2024!'),
          closeTo(1 - 1 / 11, 1e-9));
    });
  });

  group('weak / empty passwords', () {
    final auditor = PasswordAuditor();

    test('flags empty password as high severity', () {
      final f = auditor.findWeakOrEmpty([pwEntry('e1', '')]);
      expect(f, hasLength(1));
      expect(f.first.issue, AuditIssue.emptyPassword);
      expect(f.first.severity, AuditSeverity.high);
    });

    test('flags missing password field', () {
      final f = auditor.findWeakOrEmpty([pwEntry('e1', null)]);
      expect(f.single.issue, AuditIssue.emptyPassword);
    });

    test('flags low-entropy password as weak', () {
      final f = auditor.findWeakOrEmpty([pwEntry('e1', 'abc123')]); // ~31 bits
      expect(f.single.issue, AuditIssue.weakPassword);
      expect(f.single.metric, lessThan(50));
    });

    test('does not flag a strong password', () {
      final f = auditor.findWeakOrEmpty(
          [pwEntry('e1', 'Tr0ub4dour-&3-XtraLongPhrase!')]);
      expect(f, isEmpty);
    });
  });

  group('reused passwords', () {
    final auditor = PasswordAuditor();

    test('flags every entry sharing an identical password', () {
      final f = auditor.findReused([
        pwEntry('a', 'Shared-Pass-99!'),
        pwEntry('b', 'Shared-Pass-99!'),
        pwEntry('c', 'unique-different-one'),
      ]);
      final reused = f.where((x) => x.issue == AuditIssue.reusedPassword);
      expect(reused.map((x) => x.entryUuid).toSet(), {'a', 'b'});
      expect(reused.first.relatedUuids, isNotEmpty);
    });

    test('no finding when all passwords differ', () {
      final f = auditor.findReused([
        pwEntry('a', 'one-distinct-pw'),
        pwEntry('b', 'two-distinct-pw'),
      ]);
      expect(f, isEmpty);
    });
  });

  group('find similar', () {
    final auditor = PasswordAuditor();

    test('flags near-duplicate (but not identical) passwords', () {
      final f = auditor.findSimilar([
        pwEntry('a', 'Summer2023!'),
        pwEntry('b', 'Summer2024!'),
      ]);
      expect(f.map((x) => x.entryUuid).toSet(), {'a', 'b'});
      expect(f.first.metric, greaterThanOrEqualTo(0.80));
    });

    test('identical passwords are NOT reported as similar (reused covers them)',
        () {
      final f = auditor.findSimilar([
        pwEntry('a', 'Identical-1!'),
        pwEntry('b', 'Identical-1!'),
      ]);
      expect(f, isEmpty);
    });

    test('dissimilar passwords are not flagged', () {
      final f = auditor.findSimilar([
        pwEntry('a', 'aaaaaaaaaa'),
        pwEntry('b', 'ZZZZ!!9999'),
      ]);
      expect(f, isEmpty);
    });
  });

  group('old passwords', () {
    final auditor = PasswordAuditor();
    final now = DateTime.utc(2026, 1, 1);

    test('flags passwords older than maxAge', () {
      final f = auditor.findOld(
        [pwEntry('a', 'strong-enough-pw', modified: DateTime.utc(2024, 1, 1))],
        now: now,
      );
      expect(f.single.issue, AuditIssue.oldPassword);
      expect(f.single.metric, greaterThan(365));
    });

    test('recent passwords are not flagged', () {
      final f = auditor.findOld(
        [pwEntry('a', 'strong-enough-pw', modified: DateTime.utc(2025, 12, 1))],
        now: now,
      );
      expect(f, isEmpty);
    });

    test('entries without a timestamp are skipped', () {
      final f = auditor.findOld([pwEntry('a', 'pw')], now: now);
      expect(f, isEmpty);
    });
  });

  group('combined audit', () {
    test('aggregates findings across checks', () {
      final auditor = PasswordAuditor();
      final now = DateTime.utc(2026, 1, 1);
      final findings = auditor.audit([
        pwEntry('weak', 'abc'), // weak
        pwEntry('dup1', 'Repeated-9!'), // reused
        pwEntry('dup2', 'Repeated-9!'), // reused
        pwEntry('old', 'Tr0ub4dour-&3-XtraLong!',
            modified: DateTime.utc(2020, 1, 1)), // old
      ], now: now);
      final issues = findings.map((f) => f.issue).toSet();
      expect(issues, containsAll([
        AuditIssue.weakPassword,
        AuditIssue.reusedPassword,
        AuditIssue.oldPassword,
      ]));
    });
  });
}
