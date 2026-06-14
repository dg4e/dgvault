import 'dart:typed_data';

import 'package:dgvault/core/core.dart';
import 'package:test/test.dart';

void main() {
  group('ProtectedValue', () {
    test('reveals and then zeroes on dispose', () {
      final pv = InMemoryProtectedValue('hunter2');
      expect(pv.isProtected, isTrue);
      expect(pv.reveal(), 'hunter2');
      pv.dispose();
      expect(pv.reveal, throwsStateError);
    });

    test('plain factory marks value non-secret', () {
      expect(InMemoryProtectedValue.plain('example.com').isProtected, isFalse);
    });
  });

  group('Field', () {
    test('classifies standard vs custom keys', () {
      final pw = Field(
        key: Field.password,
        value: InMemoryProtectedValue('s3cr3t'),
      );
      final custom = Field(
        key: 'API Token',
        value: InMemoryProtectedValue('abc'),
      );
      expect(pw.isCustom, isFalse);
      expect(custom.isCustom, isTrue);
      expect(Field.isStandardKey(Field.url), isTrue);
    });
  });

  group('Group tree', () {
    test('allEntries walks the subtree depth-first', () {
      final e1 = Entry(uuid: 'e1');
      final e2 = Entry(uuid: 'e2');
      final child = Group(uuid: 'g2', name: 'Work', entries: [e2]);
      final root =
          Group(uuid: 'g1', name: 'Root', groups: [child], entries: [e1]);
      expect(root.allEntries.map((e) => e.uuid), ['e1', 'e2']);
    });
  });

  group('KdfParams', () {
    test('argon2id default is valid and GPU-resistant', () {
      final p = KdfParams.argon2idDefault();
      expect(p.isArgon2, isTrue);
      expect(p.isValid, isTrue);
      expect(p.memoryKib, greaterThanOrEqualTo(64 * 1024));
    });

    test('rejects under-strength argon2 params', () {
      const bad = KdfParams(
        algorithm: KdfAlgorithm.argon2id,
        iterations: 0,
        memoryKib: 1,
        parallelism: 0,
      );
      expect(bad.isValid, isFalse);
    });
  });

  group('SecureKey', () {
    test('zeroes material on destroy', () {
      final key = HeapSecureKey(Uint8ListOf([1, 2, 3, 4]));
      expect(key.length, 4);
      key.destroy();
      expect(key.bytes, throwsStateError);
    });
  });

  group('Database', () {
    test('counts entries across the tree and defaults to argon2id', () {
      final root = Group(
        uuid: 'r',
        name: 'Root',
        entries: [Entry(uuid: 'a'), Entry(uuid: 'b')],
      );
      final db = Database(meta: DatabaseMeta(name: 'Test'), root: root);
      expect(db.entryCount, 2);
      expect(db.kdf.isArgon2, isTrue);
      expect(db.readOnly, isFalse);
    });
  });
}

/// Tiny helper so the test file needs no dart:typed_data import noise.
Uint8List Uint8ListOf(List<int> xs) => Uint8List.fromList(xs);
