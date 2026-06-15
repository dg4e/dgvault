// End-to-end: the encrypted-CSV container wired to REAL crypto (Argon2id KDF +
// AES-256-GCM / ChaCha20-Poly1305), not the stub doubles. Proves the feature
// actually encrypts/decrypts with vetted primitives and that a wrong password is
// rejected by authentication.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dgvault/core/crypto/impl/aead_cipher.dart';
import 'package:dgvault/core/crypto/impl/argon2_kdf.dart';
import 'package:dgvault/core/crypto/key_derivation.dart';
import 'package:dgvault/core/model/entry.dart';
import 'package:dgvault/core/model/field.dart';
import 'package:dgvault/core/model/group.dart';
import 'package:dgvault/core/model/kdf_params.dart';
import 'package:dgvault/core/model/protected_value.dart';
import 'package:dgvault/data/import_export/encrypted_csv.dart';
import 'package:test/test.dart';

CompositeCredential _cred(String pw) =>
    CompositeCredential(password: Uint8List.fromList(utf8.encode(pw)));

Group _root() => Group(uuid: 'r', name: 'Root', entries: [
      Entry(uuid: 'e1', fields: {
        Field.title: Field(key: Field.title, value: InMemoryProtectedValue.plain('Acme')),
        Field.userName: Field(key: Field.userName, value: InMemoryProtectedValue.plain('alice')),
        Field.password: Field(key: Field.password, value: InMemoryProtectedValue('s3cret!')),
      },),
      Entry(uuid: 'e2', fields: {
        Field.title: Field(key: Field.title, value: InMemoryProtectedValue.plain('Béta, "quoted"')),
        Field.password: Field(key: Field.password, value: InMemoryProtectedValue('pø,wörd\nwith newline')),
      },),
    ],);

// Light KDF cost keeps the test fast; the KDF itself is KAT-verified elsewhere.
const _params = KdfParams(
    algorithm: KdfAlgorithm.argon2id, iterations: 2, memoryKib: 64, parallelism: 1,);
final _salt = Uint8List.fromList(List.generate(16, (i) => i * 3 + 1));
final _iv = Uint8List.fromList(List.generate(12, (i) => 0x10 + i));

void main() {
  for (final entry in {
    'AES-256-GCM': AesGcmCipher.new,
    'ChaCha20-Poly1305': ChaCha20Poly1305Cipher.new,
  }.entries) {
    group(entry.key, () {
      EncryptedCsv codec() =>
          EncryptedCsv(cipher: entry.value(), kdf: const Argon2KeyDerivation());

      test('round-trips entries incl. metachars/unicode/newlines', () async {
        final container = await codec().export(_root(),
            credential: _cred('correct horse battery staple'),
            params: _params, salt: _salt, iv: _iv,);
        final result = await codec()
            .import(container, credential: _cred('correct horse battery staple'));

        expect(result.root.entries.length, 2);
        final e1 = result.root.entries.firstWhere((e) => e.title == 'Acme');
        expect(e1.fields[Field.userName]!.value.reveal(), 'alice');
        expect(e1.fields[Field.password]!.value.reveal(), 's3cret!');
        final e2 = result.root.entries.firstWhere((e) => e.title == 'Béta, "quoted"');
        expect(e2.fields[Field.password]!.value.reveal(), 'pø,wörd\nwith newline');
      });

      test('the container bytes are not plaintext', () async {
        final container = await codec().export(_root(),
            credential: _cred('pw'), params: _params, salt: _salt, iv: _iv,);
        final asText = latin1.decode(container, allowInvalid: true);
        expect(asText.contains('alice'), isFalse);
        expect(asText.contains('s3cret'), isFalse);
      });

      test('wrong password fails authenticated decryption', () async {
        final container = await codec().export(_root(),
            credential: _cred('right'), params: _params, salt: _salt, iv: _iv,);
        expect(() => codec().import(container, credential: _cred('wrong')),
            throwsA(isA<CipherAuthenticationException>()),);
      });
    });
  }
}
