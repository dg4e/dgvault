import 'dart:typed_data';

import 'package:dgvault/core/core.dart';
import 'package:test/test.dart';

KdbxHeader _sampleHeader({
  DatabaseCipher cipher = DatabaseCipher.aes256,
  bool compressed = true,
  KdfParams? kdf,
}) {
  final params = kdf ?? KdfParams.argon2idDefault();
  final salt = Uint8List.fromList(List<int>.generate(32, (i) => i));
  return KdbxHeader(
    cipher: cipher,
    compressed: compressed,
    masterSeed: Uint8List.fromList(List<int>.generate(32, (i) => 255 - i)),
    encryptionIv: Uint8List.fromList(List<int>.generate(16, (i) => i * 2)),
    kdfParameters: KdfParameters.toVariantDictionary(params, salt),
  );
}

void main() {
  group('KdfParameters mapping', () {
    test('argon2id round-trips params + salt', () {
      final salt = Uint8List.fromList(List<int>.generate(16, (i) => i));
      final vd =
          KdfParameters.toVariantDictionary(KdfParams.argon2idDefault(), salt);
      final (params, gotSalt) = KdfParameters.fromVariantDictionary(vd);

      expect(params.algorithm, KdfAlgorithm.argon2id);
      expect(params.iterations, 3);
      expect(params.memoryKib, 64 * 1024);
      expect(params.parallelism, 4);
      expect(gotSalt, salt);
      // Memory is persisted in BYTES on the wire.
      expect(vd.getUInt64('M'), 64 * 1024 * 1024);
    });

    test('aes-kdf round-trips rounds + seed', () {
      final seed = Uint8List.fromList(List<int>.filled(32, 7));
      const aes = KdfParams(algorithm: KdfAlgorithm.aesKdf, iterations: 60000);
      final vd = KdfParameters.toVariantDictionary(aes, seed);
      final (params, gotSeed) = KdfParameters.fromVariantDictionary(vd);
      expect(params.algorithm, KdfAlgorithm.aesKdf);
      expect(params.iterations, 60000);
      expect(gotSeed, seed);
    });

    test(r'throws when $UUID is missing', () {
      expect(() => KdfParameters.fromVariantDictionary(VariantDictionary()),
          throwsA(isA<KdbxFormatException>()));
    });
  });

  group('KdbxHeader binary round-trip', () {
    test('serialize → read preserves all header fields (AES)', () {
      final header = _sampleHeader();
      final bytes = header.serialize();
      final back = KdbxHeader.read(bytes);

      expect(back.versionMajor, 4);
      expect(back.cipher, DatabaseCipher.aes256);
      expect(back.compressed, isTrue);
      expect(back.masterSeed, header.masterSeed);
      expect(back.encryptionIv, header.encryptionIv);
      expect(back.length, bytes.length);

      final kdf = back.kdf;
      expect(kdf.algorithm, KdfAlgorithm.argon2id);
      expect(kdf.memoryKib, 64 * 1024);
    });

    test('preserves ChaCha20 cipher + no-compression flag', () {
      final header =
          _sampleHeader(cipher: DatabaseCipher.chacha20, compressed: false);
      final back = KdbxHeader.read(header.serialize());
      expect(back.cipher, DatabaseCipher.chacha20);
      expect(back.compressed, isFalse);
    });

    test('rejects a bad magic signature', () {
      final bad = Uint8List(32); // all zeros
      expect(() => KdbxHeader.read(bad), throwsA(isA<KdbxFormatException>()));
    });

    test('rejects an unsupported major version', () {
      final bytes = _sampleHeader().serialize();
      // major version lives at offset 10 (little-endian uint16).
      bytes[10] = 3;
      expect(() => KdbxHeader.read(bytes),
          throwsA(isA<KdbxFormatException>()));
    });
  });
}
