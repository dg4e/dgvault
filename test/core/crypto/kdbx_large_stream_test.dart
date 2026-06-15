// Large-DB handling (R4): the KDBX HMAC block stream chunks at 1 MiB, so a body
// spanning several blocks round-trips and every block is integrity-checked.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dgvault/core/core.dart';
import 'package:dgvault/core/crypto/impl/argon2_kdf.dart';
import 'package:dgvault/core/crypto/impl/kdbx4_body_cipher.dart';
import 'package:test/test.dart';

const _kdf = Argon2KeyDerivation();
final _cred = CompositeCredential(password: Uint8List.fromList(utf8.encode('big-db')));

KdbxHeader _header() => KdbxHeader(
      cipher: DatabaseCipher.aes256,
      compressed: false,
      masterSeed: Uint8List.fromList(List.generate(32, (i) => i + 2)),
      encryptionIv: Uint8List.fromList(List.generate(16, (i) => i + 4)),
      kdfParameters: KdfParameters.toVariantDictionary(
        const KdfParams(algorithm: KdfAlgorithm.argon2id, iterations: 2, memoryKib: 64, parallelism: 1),
        Uint8List.fromList(List.generate(16, (i) => i + 1)),
      ),
    );

void main() {
  // ~2.5 MiB inner payload spans 3 blocks (1 MiB + 1 MiB + 0.5 MiB) + terminator.
  Uint8List bigPayload() {
    const n = 1024 * 1024 * 2 + 512 * 1024;
    return Uint8List.fromList(List.generate(n, (i) => (i * 31 + 7) & 0xff));
  }

  test('multi-block (>1 MiB) body round-trips', () async {
    final cipher = Kdbx4BodyCipher(kdf: _kdf);
    final header = _header();
    final inner = bigPayload();
    final body = await cipher.encryptBody(header, inner, _cred);
    final back = await cipher.decryptBody(header, body, _cred);
    expect(back.length, inner.length);
    expect(back, equals(inner));
  });

  test('tampering inside the FIRST block is detected (proves per-block HMAC)',
      () async {
    final cipher = Kdbx4BodyCipher(kdf: _kdf);
    final header = _header();
    final body = await cipher.encryptBody(header, bigPayload(), _cred);
    // Header hash(32)+HMAC(32) then block: HMAC(32)+len(4)+data. Flip a byte
    // ~100 KiB into the first block's DATA (well within block 0).
    body[64 + 32 + 4 + 100 * 1024] ^= 0xFF;
    expect(() => cipher.decryptBody(header, body, _cred),
        throwsA(isA<KdbxIntegrityException>()),);
  });

  test('full pipeline: a multi-megabyte entry value survives', () async {
    final big = 'X' * (1024 * 1024 * 2); // 2 MiB value, uncompressed
    final db = Database(
      meta: DatabaseMeta(name: 'Big'),
      root: Group(uuid: 'R', name: 'Root', entries: [
        Entry(uuid: 'E1', fields: {
          Field.notes: Field(key: Field.notes, value: InMemoryProtectedValue.plain(big)),
        },),
      ],),
    );
    final codec = KdbxCodec(bodyCipher: Kdbx4BodyCipher(kdf: _kdf));
    final back = await codec.read(await codec.write(db, _header(), _cred), _cred);
    expect(back.root.entries.single.fields[Field.notes]!.value.reveal().length,
        big.length,);
  });
}
