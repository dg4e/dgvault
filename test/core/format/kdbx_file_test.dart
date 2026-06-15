import 'dart:convert';
import 'dart:typed_data';

import 'package:dgvault/core/core.dart';
import 'package:test/test.dart';

/// Reversible XOR stand-in for the real KDF→cipher→HMAC body transform. Proves
/// the orchestrator actually round-trips through an encrypt/decrypt boundary
/// (and that the on-disk body is not plaintext). NOT cryptography.
class _XorBodyCipher implements KdbxBodyCipher {
  const _XorBodyCipher();

  int _key(CompositeCredential c) =>
      (c.password != null && c.password!.isNotEmpty) ? c.password!.first : 0x5A;

  Uint8List _xor(Uint8List data, int k) =>
      Uint8List.fromList([for (final b in data) b ^ k]);

  @override
  Future<Uint8List> encryptBody(
          KdbxHeader h, Uint8List inner, CompositeCredential c,) async =>
      _xor(inner, _key(c));

  @override
  Future<Uint8List> decryptBody(
          KdbxHeader h, Uint8List body, CompositeCredential c,) async =>
      _xor(body, _key(c));
}

/// Reversible marker-framing stand-in for gzip, to exercise the compress path.
class _MarkerCompressor implements Compressor {
  const _MarkerCompressor();
  static const int _marker = 0xC0;
  @override
  Uint8List compress(Uint8List data) =>
      Uint8List.fromList([_marker, ...data]);
  @override
  Uint8List decompress(Uint8List data) {
    if (data.isEmpty || data.first != _marker) {
      throw StateError('not marker-compressed');
    }
    return Uint8List.fromList(data.sublist(1));
  }
}

KdbxHeader _header({bool compressed = false}) => KdbxHeader(
      cipher: DatabaseCipher.aes256,
      compressed: compressed,
      masterSeed: Uint8List.fromList(List<int>.generate(32, (i) => i)),
      encryptionIv: Uint8List.fromList(List<int>.generate(16, (i) => i)),
      kdfParameters: KdfParameters.toVariantDictionary(
        KdfParams.argon2idDefault(),
        Uint8List(16),
      ),
    );

Database _db() {
  final entry = Entry(
    uuid: 'E1',
    fields: {
      Field.title: Field(
          key: Field.title, value: InMemoryProtectedValue.plain('GitHub'),),
      Field.password:
          Field(key: Field.password, value: InMemoryProtectedValue('p@ss')),
    },
    tags: ['dev'],
  );
  return Database(
    meta: DatabaseMeta(name: 'Vault'),
    root: Group(uuid: 'R', name: 'Root', entries: [entry]),
  );
}

void main() {
  final cred = CompositeCredential(password: utf8.encode('master'));

  test('write → read round-trips the database through the full pipeline', () async {
    final codec = KdbxCodec(bodyCipher: const _XorBodyCipher());
    final bytes = await codec.write(_db(), _header(), cred);
    final back = await codec.read(bytes, cred);

    expect(back.meta.name, 'Vault');
    final e = back.root.entries.single;
    expect(e.fields[Field.title]!.value.reveal(), 'GitHub');
    expect(e.fields[Field.password]!.value.reveal(), 'p@ss');
    expect(e.tags, ['dev']);
  });

  test('output begins with the KDBX magic and body is not plaintext', () async {
    final codec = KdbxCodec(bodyCipher: const _XorBodyCipher());
    final bytes = await codec.write(_db(), _header(), cred);

    final bd = ByteData.sublistView(bytes);
    expect(bd.getUint32(0, Endian.little), KdbxHeader.sig1);
    expect(bd.getUint32(4, Endian.little), KdbxHeader.sig2);
    // The plaintext XML must not appear verbatim in the encrypted body.
    expect(utf8.decode(bytes, allowMalformed: true), isNot(contains('GitHub')));
  });

  test('compression path is exercised when header.compressed is set', () async {
    final codec = KdbxCodec(
      bodyCipher: const _XorBodyCipher(),
      compressor: const _MarkerCompressor(),
    );
    final bytes = await codec.write(_db(), _header(compressed: true), cred);
    final back = await codec.read(bytes, cred);
    expect(back.root.entries.single.fields[Field.title]!.value.reveal(),
        'GitHub',);
  });

  test('a wrong credential fails to recover valid XML', () async {
    final codec = KdbxCodec(bodyCipher: const _XorBodyCipher());
    final bytes = await codec.write(_db(), _header(), cred);
    final wrong = CompositeCredential(password: utf8.encode('different'));
    // XOR with the wrong key yields bytes that are not valid KeePass XML.
    expect(() => codec.read(bytes, wrong), throwsA(anything));
  });
}
