import 'dart:convert';
import 'dart:typed_data';

import 'package:dgvault/core/core.dart';
import 'package:dgvault/core/crypto/impl/aes_kdf.dart';
import 'package:dgvault/core/crypto/impl/kdbx4_body_cipher.dart';
import 'package:dgvault/data/format/gzip_compressor.dart';
import 'package:test/test.dart';

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
Uint8List _pw(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  const kdf = AesKdfKeyDerivation();

  test('KAT: matches an independent pyca AES-ECB oracle (1000 rounds)', () async {
    // seed[i] = (i*9+5)&0xff; password 'legacy-pass'; rounds 1000.
    // Verified equal to: SHA256( AES256-ECB(seed)^1000 ( SHA256(SHA256(pw)) ) ).
    final seed = Uint8List.fromList(List.generate(32, (i) => (i * 9 + 5) & 0xff));
    const params = KdfParams(algorithm: KdfAlgorithm.aesKdf, iterations: 1000);
    final key = await kdf.deriveKey(CompositeCredential(password: _pw('legacy-pass')),
        params, seed,);
    expect(_hex(key.bytes()),
        '76e7f3d36a443b5a4694dcd47adbdd5f2fa1342583d12876b0511e3aff75ef8a',);
  });

  test('more rounds → different key; deterministic; 32 bytes', () async {
    final seed = Uint8List.fromList(List.filled(32, 0x11));
    final a = await kdf.deriveKey(CompositeCredential(password: _pw('x')),
        const KdfParams(algorithm: KdfAlgorithm.aesKdf, iterations: 10), seed,);
    final a2 = await kdf.deriveKey(CompositeCredential(password: _pw('x')),
        const KdfParams(algorithm: KdfAlgorithm.aesKdf, iterations: 10), seed,);
    final b = await kdf.deriveKey(CompositeCredential(password: _pw('x')),
        const KdfParams(algorithm: KdfAlgorithm.aesKdf, iterations: 11), seed,);
    expect(a.length, 32);
    expect(_hex(a.bytes()), _hex(a2.bytes()));
    expect(_hex(a.bytes()), isNot(_hex(b.bytes())));
  });

  test('supports only aesKdf; rejects bad seed length and rounds < 1', () async {
    expect(kdf.supports(KdfAlgorithm.aesKdf), isTrue);
    expect(kdf.supports(KdfAlgorithm.argon2id), isFalse);
    expect(
        () => kdf.deriveKey(CompositeCredential(password: _pw('x')),
            const KdfParams(algorithm: KdfAlgorithm.aesKdf, iterations: 1), Uint8List(16),),
        throwsA(isA<ArgumentError>()),);
    expect(
        () => kdf.deriveKey(CompositeCredential(password: _pw('x')),
            const KdfParams(algorithm: KdfAlgorithm.aesKdf, iterations: 0), Uint8List(32),),
        throwsA(isA<ArgumentError>()),);
  });

  test('full KDBX round-trip with AES-KDF (dispatched by DefaultKeyDerivation)',
      () async {
    final cred = CompositeCredential(password: _pw('legacy master'));
    final header = KdbxHeader(
      cipher: DatabaseCipher.aes256,
      compressed: true,
      masterSeed: Uint8List.fromList(List.generate(32, (i) => i + 3)),
      encryptionIv: Uint8List.fromList(List.generate(16, (i) => i + 9)),
      kdfParameters: KdfParameters.toVariantDictionary(
        const KdfParams(algorithm: KdfAlgorithm.aesKdf, iterations: 600),
        Uint8List.fromList(List.generate(32, (i) => i + 1)),
      ),
    );
    final db = Database(
      meta: DatabaseMeta(name: 'Legacy'),
      root: Group(uuid: 'R', name: 'Root', entries: [
        Entry(uuid: 'E1', fields: {
          Field.title: Field(key: Field.title, value: InMemoryProtectedValue.plain('Old Site')),
          Field.password: Field(key: Field.password, value: InMemoryProtectedValue('legacy-pw', isProtected: true)),
        },),
      ],),
    );
    // Default body cipher uses the dispatching KDF (Argon2 + AES-KDF).
    final codec = KdbxCodec(bodyCipher: Kdbx4BodyCipher(), compressor: const GzipCompressor());
    final bytes = await codec.write(db, header, cred);
    final back = await codec.read(bytes, cred);

    final e = back.root.entries.single;
    expect(e.fields[Field.title]!.value.reveal(), 'Old Site');
    expect(e.fields[Field.password]!.value.reveal(), 'legacy-pw');
    expect(() => codec.read(bytes, CompositeCredential(password: _pw('bad'))),
        throwsA(isA<KdbxIntegrityException>()),);
  });
}
