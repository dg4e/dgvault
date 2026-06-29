// Builds a real (lightly-encrypted) KDBX byte blob for the UI tests, so they
// exercise the genuine open/unlock path without the cost of production Argon2.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dgvault/core/core.dart';
import 'package:dgvault/core/crypto/impl/argon2_kdf.dart';
import 'package:dgvault/core/crypto/impl/kdbx4_body_cipher.dart';
import 'package:dgvault/data/format/gzip_compressor.dart';

const testVaultPassword = 'open sesame';

Entry _e(String uuid, String title,
    {String? user, String? pass, String? url, List<String> tags = const [],}) {
  return Entry(
    uuid: uuid,
    fields: {
      Field.title:
          Field(key: Field.title, value: InMemoryProtectedValue.plain(title)),
      if (user != null)
        Field.userName: Field(
            key: Field.userName, value: InMemoryProtectedValue.plain(user),),
      if (pass != null)
        Field.password:
            Field(key: Field.password, value: InMemoryProtectedValue(pass)),
      if (url != null)
        Field.url:
            Field(key: Field.url, value: InMemoryProtectedValue.plain(url)),
    },
    tags: tags,
    modified: DateTime.utc(2026, 6, 1),
  );
}

Database buildTestDatabase() => Database(
      meta: DatabaseMeta(name: 'test', recycleBinUuid: 'rb'),
      root: Group(uuid: 'root', name: 'Root', groups: [
        Group(uuid: 'g', name: 'Personal', entries: [
          _e('e1', 'GitHub',
              user: 'realytcracker',
              pass: 'h4ck-the-pl4net!',
              url: 'https://github.com',
              tags: ['dev', 'vip'],),
          _e('e2', 'Proton Mail',
              user: 'ytcracker@proton.me',
              pass: 'pw2',
              url: 'https://proton.me',
              tags: ['email'],),
        ],),
        Group(uuid: 'w', name: 'Work', entries: [
          _e('e3', 'Jira', user: 'ytc', pass: 'pw3', url: 'https://jira.example'),
        ],),
        // Recycle Bin — its entry must NOT show in the default (All) view.
        Group(uuid: 'rb', name: 'Recycle Bin', entries: [
          _e('e4', 'Deleted Thing', user: 'old', pass: 'pw4'),
        ],),
      ],),
    );

KdbxCodec testCodec() => KdbxCodec(
      bodyCipher: Kdbx4BodyCipher(kdf: const Argon2KeyDerivation()),
      compressor: const GzipCompressor(),
    );

KdbxHeader testHeader() => KdbxHeader(
      cipher: DatabaseCipher.aes256,
      compressed: true,
      masterSeed: Uint8List.fromList(List.generate(32, (i) => i + 1)),
      encryptionIv: Uint8List.fromList(List.generate(16, (i) => i + 2)),
      kdfParameters: KdfParameters.toVariantDictionary(
        const KdfParams(
            algorithm: KdfAlgorithm.argon2id,
            iterations: 2,
            memoryKib: 64,
            parallelism: 1,),
        Uint8List.fromList(List.generate(16, (i) => i + 3)),
      ),
    );

/// Encrypted bytes for a test vault (password [testVaultPassword]).
Future<Uint8List> buildTestVaultBytes() => testCodec().write(
      buildTestDatabase(),
      testHeader(),
      CompositeCredential(
          password: Uint8List.fromList(utf8.encode(testVaultPassword)),),
    );
