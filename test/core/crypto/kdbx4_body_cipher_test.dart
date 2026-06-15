// Real KDBX4 body: Argon2id KDF + AES-256-CBC / ChaCha20 + HMAC-SHA-256 block
// stream + gzip, driven end-to-end through the KdbxCodec pipeline. This realises
// the Phase 1 "Argon2/AES body" that was previously stubbed (see
// kdbx_file_audit_test.dart's XOR stand-in).

import 'dart:convert';
import 'dart:typed_data';

import 'package:dgvault/core/core.dart';
import 'package:dgvault/core/crypto/impl/argon2_kdf.dart';
import 'package:dgvault/core/crypto/impl/kdbx4_body_cipher.dart';
import 'package:dgvault/data/format/gzip_compressor.dart';
import 'package:test/test.dart';

const _kdf = Argon2KeyDerivation();
// Light Argon2 cost for test speed; correctness of the KDF is KAT-verified in
// argon2_kdf_test.dart.
const _params = KdfParams(
    algorithm: KdfAlgorithm.argon2id, iterations: 2, memoryKib: 64, parallelism: 1,);

KdbxHeader _header(DatabaseCipher cipher, {bool compressed = true}) => KdbxHeader(
      cipher: cipher,
      compressed: compressed,
      masterSeed: Uint8List.fromList(List.generate(32, (i) => i + 7)),
      encryptionIv: Uint8List.fromList(List.generate(
          cipher == DatabaseCipher.chacha20 ? 12 : 16, (i) => i * 2 + 1,),),
      kdfParameters: KdfParameters.toVariantDictionary(
          _params, Uint8List.fromList(List.generate(16, (i) => i + 1)),),
    );

Database _rich() {
  final entry = Entry(
    uuid: 'E1',
    fields: {
      Field.title: Field(key: Field.title, value: InMemoryProtectedValue.plain('Acme <Corp> & "Co"')),
      Field.password: Field(key: Field.password, value: InMemoryProtectedValue('p@ss\nword  ')),
      'Recovery': Field(key: 'Recovery', value: InMemoryProtectedValue('RC-001', isProtected: true)),
    },
    tags: ['wörk', 'vip'],
  );
  entry.history.add(Entry(uuid: 'E1', fields: {
    Field.password: Field(key: Field.password, value: InMemoryProtectedValue('old-pass')),
  },),);
  final sub = Group(uuid: 'G2', name: 'Sub Wörk', entries: [entry]);
  final root = Group(uuid: 'R', name: 'Root')..groups.add(sub);
  return Database(meta: DatabaseMeta(name: 'Vault — 日本'), root: root);
}

void main() {
  final cred = CompositeCredential(password: utf8.encode('master-password'));

  for (final cipher in DatabaseCipher.values) {
    group(cipher.name, () {
      KdbxCodec codec() => KdbxCodec(
            bodyCipher: Kdbx4BodyCipher(kdf: _kdf),
            compressor: const GzipCompressor(),
          );

      test('rich database round-trips with real crypto + gzip', () async {
        final bytes = await codec().write(_rich(), _header(cipher), cred);
        final back = await codec().read(bytes, cred);

        expect(back.meta.name, 'Vault — 日本');
        final e = back.root.groups.single.entries.single;
        expect(e.fields[Field.title]!.value.reveal(), 'Acme <Corp> & "Co"');
        expect(e.fields[Field.password]!.value.reveal(), 'p@ss\nword  ');
        expect(e.fields['Recovery']!.value.reveal(), 'RC-001');
        expect(e.fields['Recovery']!.isProtected, isTrue);
        expect(e.tags, containsAll(['wörk', 'vip']));
        expect(e.history.single.fields[Field.password]!.value.reveal(), 'old-pass');
      });

      test('starts with the KDBX magic and the body is not plaintext', () async {
        final bytes = await codec().write(_rich(), _header(cipher), cred);
        final bd = ByteData.sublistView(bytes);
        expect(bd.getUint32(0, Endian.little), KdbxHeader.sig1);
        expect(bd.getUint32(4, Endian.little), KdbxHeader.sig2);
        final asText = latin1.decode(bytes, allowInvalid: true);
        expect(asText.contains('Acme'), isFalse);
        expect(asText.contains('RC-001'), isFalse);
      });

      test('wrong password fails the header HMAC', () async {
        final bytes = await codec().write(_rich(), _header(cipher), cred);
        expect(
            () => codec().read(
                bytes, CompositeCredential(password: utf8.encode('wrong')),),
            throwsA(isA<KdbxIntegrityException>()),);
      });

      test('tampering with the encrypted body is detected', () async {
        final bytes = await codec().write(_rich(), _header(cipher), cred);
        // Flip a byte well past the header + header hash/MAC, inside the stream.
        final i = bytes.length - 5;
        bytes[i] ^= 0xFF;
        expect(() => codec().read(bytes, cred),
            throwsA(isA<KdbxIntegrityException>()),);
      });

      test('empty database round-trips', () async {
        final empty = Database(
            meta: DatabaseMeta(name: 'Empty'), root: Group(uuid: 'R', name: 'Root'),);
        final back = await codec()
            .read(await codec().write(empty, _header(cipher), cred), cred);
        expect(back.meta.name, 'Empty');
        expect(back.root.entries, isEmpty);
      });
    });
  }
}
