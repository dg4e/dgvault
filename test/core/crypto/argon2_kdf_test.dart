import 'dart:convert';
import 'dart:typed_data';

import 'package:dgvault/core/crypto/impl/argon2_kdf.dart';
import 'package:dgvault/core/crypto/key_derivation.dart';
import 'package:dgvault/core/model/kdf_params.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:test/test.dart';

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

Uint8List _pw(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  const kdf = Argon2KeyDerivation();
  // Light params keep the suite fast; the heavy lifting is the primitive, which
  // the RFC 9106 KAT below verifies at the standard 32-KiB cost.
  final salt = Uint8List.fromList(List.generate(16, (i) => i + 1));
  const params = KdfParams(
    algorithm: KdfAlgorithm.argon2id,
    iterations: 2,
    memoryKib: 64,
    parallelism: 1,
  );

  group('primitive correctness', () {
    test('pointycastle Argon2id matches the RFC 9106 §5.3 test vector', () {
      // P=32×01, S=16×02, K(secret)=8×03, X(AD)=12×04, t=3, m=32, p=4, v=0x13.
      final p = pc.Argon2Parameters(
        pc.Argon2Parameters.ARGON2_id,
        Uint8List.fromList(List.filled(16, 0x02)),
        desiredKeyLength: 32,
        iterations: 3,
        memory: 32,
        lanes: 4,
        version: 0x13,
        secret: Uint8List.fromList(List.filled(8, 0x03)),
        additional: Uint8List.fromList(List.filled(12, 0x04)),
      );
      final gen = pc.Argon2BytesGenerator()..init(p);
      final out = Uint8List(32);
      gen.deriveKey(Uint8List.fromList(List.filled(32, 0x01)), 0, out, 0);
      expect(_hex(out),
          '0d640df58d78766c08c037a34a8b53c9d01ef0452d75b65eb52520e96b01e659',);
    });
  });

  group('hostile-parameter rejection (DoS hardening)', () {
    test('deriveKey rejects multi-GiB Argon2 memory instead of OOMing', () {
      // A malicious header could demand ~4 GiB of Argon2 memory; deriveKey must
      // reject it up front (before allocating), not attempt the allocation.
      const hostile = KdfParams(
        algorithm: KdfAlgorithm.argon2id,
        iterations: 3,
        memoryKib: 4 * 1024 * 1024, // 4 GiB
        parallelism: 4,
      );
      expect(
        () => kdf.deriveKey(
          CompositeCredential(password: _pw('password')),
          hostile,
          salt,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('composite-key wiring', () {
    test('password-only == Argon2(SHA256(SHA256(pw)), salt) computed independently',
        () async {
      final key = await kdf.deriveKey(CompositeCredential(password: _pw('password')),
          params, salt,);

      // Rebuild the KeePass composite by hand: SHA256( SHA256(password) ).
      final pwHash = pc.SHA256Digest().process(_pw('password'));
      final composite = pc.SHA256Digest().process(pwHash);
      final p = pc.Argon2Parameters(pc.Argon2Parameters.ARGON2_id, salt,
          desiredKeyLength: 32, iterations: 2, memory: 64, lanes: 1, version: 0x13,);
      final gen = pc.Argon2BytesGenerator()..init(p);
      final expected = Uint8List(32);
      gen.deriveKey(composite, 0, expected, 0);

      expect(_hex(key.bytes()), _hex(expected));
    });

    test('a 32-byte key file is concatenated verbatim (not re-hashed)', () async {
      final keyFile = Uint8List.fromList(List.filled(32, 0x07));
      final key = await kdf.deriveKey(
          CompositeCredential(password: _pw('password'), keyFile: keyFile),
          params, salt,);

      final pwHash = pc.SHA256Digest().process(_pw('password'));
      final composite =
          pc.SHA256Digest().process(Uint8List.fromList([...pwHash, ...keyFile]));
      final p = pc.Argon2Parameters(pc.Argon2Parameters.ARGON2_id, salt,
          desiredKeyLength: 32, iterations: 2, memory: 64, lanes: 1, version: 0x13,);
      final gen = pc.Argon2BytesGenerator()..init(p);
      final expected = Uint8List(32);
      gen.deriveKey(composite, 0, expected, 0);

      expect(_hex(key.bytes()), _hex(expected));
    });
  });

  group('regression KATs (pin the full deriveKey path)', () {
    test('password-only', () async {
      final key = await kdf.deriveKey(CompositeCredential(password: _pw('password')),
          params, salt,);
      expect(_hex(key.bytes()),
          '71f3fc8f5304457696c3a3a2fd623bf2df14ec9e8b8cc108684b2e9e0207355e',);
    });

    test('password + key file', () async {
      final key = await kdf.deriveKey(
          CompositeCredential(
              password: _pw('password'),
              keyFile: Uint8List.fromList(List.filled(32, 0x07)),),
          params, salt,);
      expect(_hex(key.bytes()),
          'fb9f72d530cdf54cc4655c8bf096f4644d94699cf022cd6c77a0aa03b0daa547',);
    });
  });

  group('properties', () {
    test('deterministic and 32 bytes', () async {
      final a = await kdf.deriveKey(CompositeCredential(password: _pw('x')), params, salt);
      final b = await kdf.deriveKey(CompositeCredential(password: _pw('x')), params, salt);
      expect(a.length, 32);
      expect(_hex(a.bytes()), _hex(b.bytes()));
    });

    test('different password / salt / type / cost → different key', () async {
      final base = await kdf.deriveKey(CompositeCredential(password: _pw('x')), params, salt);
      final byPw = await kdf.deriveKey(CompositeCredential(password: _pw('y')), params, salt);
      final bySalt = await kdf.deriveKey(CompositeCredential(password: _pw('x')), params,
          Uint8List.fromList(List.filled(16, 0xAB)),);
      final byType = await kdf.deriveKey(CompositeCredential(password: _pw('x')),
          const KdfParams(algorithm: KdfAlgorithm.argon2d, iterations: 2, memoryKib: 64, parallelism: 1),
          salt,);
      final byCost = await kdf.deriveKey(CompositeCredential(password: _pw('x')),
          const KdfParams(algorithm: KdfAlgorithm.argon2id, iterations: 3, memoryKib: 64, parallelism: 1),
          salt,);
      final keys = {
        _hex(base.bytes()), _hex(byPw.bytes()), _hex(bySalt.bytes()),
        _hex(byType.bytes()), _hex(byCost.bytes()),
      };
      expect(keys.length, 5, reason: 'every varied input must change the key');
    });

    test('supports argon2d/id but not aesKdf', () {
      expect(kdf.supports(KdfAlgorithm.argon2d), isTrue);
      expect(kdf.supports(KdfAlgorithm.argon2id), isTrue);
      expect(kdf.supports(KdfAlgorithm.aesKdf), isFalse);
    });

    test('rejects no-factor credential and invalid params', () async {
      expect(() => kdf.deriveKey(CompositeCredential(), params, salt),
          throwsA(isA<ArgumentError>()),);
      expect(
          () => kdf.deriveKey(CompositeCredential(password: _pw('x')),
              const KdfParams(algorithm: KdfAlgorithm.argon2id, iterations: 0, memoryKib: 64, parallelism: 1),
              salt,),
          throwsA(isA<ArgumentError>()),);
    });
  });
}
