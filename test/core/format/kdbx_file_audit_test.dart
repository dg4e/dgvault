// Critic-owned end-to-end round-trip audit for the KDBX pipeline orchestrator.
//
// Composer's suite proves the happy-path round-trip, magic bytes, body-not-
// plaintext, compression, and wrong-credential. This drives a *rich* database —
// nested groups, protected custom fields, entry history, unicode, XML
// metacharacters, and whitespace-significant values — through the FULL pipeline
// (XML encode → compress → encrypt → header framing → decrypt → decompress →
// decode). It is my Phase 1 "golden round-trip" task realised with a stub cipher;
// the only piece still pending is the REAL Argon2/AES body + KeePassXC reference
// fixtures (toolchain-gated). See reviews/Critic-round-13.md.
//
// Toolchain not installed here; assertions traced against source by hand.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dgvault/core/core.dart';
import 'package:test/test.dart';

/// Reversible XOR stand-in for the real body transform (NOT cryptography) — just
/// enough of an encrypt/decrypt boundary to exercise the orchestrator.
class _XorCipher implements KdbxBodyCipher {
  const _XorCipher();
  int _k(CompositeCredential c) =>
      (c.password != null && c.password!.isNotEmpty) ? c.password!.first : 0x5A;
  Uint8List _xor(Uint8List d, int k) => Uint8List.fromList([for (final b in d) b ^ k]);
  @override
  Future<Uint8List> encryptBody(KdbxHeader h, Uint8List i, CompositeCredential c) async =>
      _xor(i, _k(c));
  @override
  Future<Uint8List> decryptBody(KdbxHeader h, Uint8List b, CompositeCredential c) async =>
      _xor(b, _k(c));
}

class _MarkerCompressor implements Compressor {
  const _MarkerCompressor();
  @override
  Uint8List compress(Uint8List d) => Uint8List.fromList([0xC0, ...d]);
  @override
  Uint8List decompress(Uint8List d) => Uint8List.fromList(d.sublist(1));
}

KdbxHeader _header({bool compressed = false}) => KdbxHeader(
      cipher: DatabaseCipher.aes256,
      compressed: compressed,
      masterSeed: Uint8List.fromList(List<int>.generate(32, (i) => i)),
      encryptionIv: Uint8List.fromList(List<int>.generate(16, (i) => i)),
      kdfParameters:
          KdfParameters.toVariantDictionary(KdfParams.argon2idDefault(), Uint8List(16)),
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
  // a prior version in history
  entry.history.add(Entry(uuid: 'E1', fields: {
    Field.password: Field(key: Field.password, value: InMemoryProtectedValue('old-pass')),
  }));

  final sub = Group(uuid: 'G2', name: 'Sub Wörk', entries: [entry]);
  final root = Group(uuid: 'R', name: 'Root');
  root.groups.add(sub);
  return Database(meta: DatabaseMeta(name: 'Vault — 日本'), root: root);
}

void main() {
  final cred = CompositeCredential(password: utf8.encode('master'));

  test('rich database round-trips through the full pipeline (stub crypto)', () async {
    final codec = KdbxCodec(bodyCipher: const _XorCipher(), compressor: const _MarkerCompressor());
    final bytes = await codec.write(_rich(), _header(compressed: true), cred);
    final back = await codec.read(bytes, cred);

    expect(back.meta.name, 'Vault — 日本');

    final sub = back.root.groups.single;
    expect(sub.name, 'Sub Wörk');
    final e = sub.entries.single;

    // XML metacharacters survive end-to-end.
    expect(e.fields[Field.title]!.value.reveal(), 'Acme <Corp> & "Co"');
    // whitespace-significant value survives encode(pretty:true) + the pipeline.
    expect(e.fields[Field.password]!.value.reveal(), 'p@ss\nword  ');
    // protected custom field: value + flag preserved.
    expect(e.fields['Recovery']!.value.reveal(), 'RC-001');
    expect(e.fields['Recovery']!.isProtected, isTrue);
    // tags (unicode) preserved.
    expect(e.tags, containsAll(['wörk', 'vip']));
    // entry history preserved through the pipeline.
    expect(e.history.single.fields[Field.password]!.value.reveal(), 'old-pass');
  });

  test('empty database round-trips (no entries/groups)', () async {
    final codec = KdbxCodec(bodyCipher: const _XorCipher());
    final empty = Database(meta: DatabaseMeta(name: 'Empty'), root: Group(uuid: 'R', name: 'Root'));
    final back = await codec.read(await codec.write(empty, _header(), cred), cred);
    expect(back.meta.name, 'Empty');
    expect(back.root.entries, isEmpty);
    expect(back.root.groups, isEmpty);
  });

  test('body framing: re-reading uses header.length and survives a larger payload', () async {
    // 50 entries → header is fixed-size, body grows; proves no fixed-offset
    // framing assumption in the header.length split.
    final root = Group(uuid: 'R', name: 'Root');
    for (var i = 0; i < 50; i++) {
      root.entries.add(Entry(uuid: 'E$i', fields: {
        Field.title: Field(key: Field.title, value: InMemoryProtectedValue.plain('entry-$i')),
      }));
    }
    final db = Database(meta: DatabaseMeta(name: 'Big'), root: root);
    final codec = KdbxCodec(bodyCipher: const _XorCipher());
    final back = await codec.read(await codec.write(db, _header(), cred), cred);
    expect(back.root.entries.length, 50);
    expect(back.root.entries.last.fields[Field.title]!.value.reveal(), 'entry-49');
  });
}
