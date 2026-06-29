// Reads a REAL KDBX 3.1 file (hand-built then validated by pykeepass — see
// test/fixtures/kdbx/generate_kdbx3.py) to prove legacy-format read support.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dgvault/core/core.dart';
import 'package:dgvault/core/crypto/impl/kdbx3_reader.dart';
import 'package:dgvault/core/crypto/impl/kdbx4_body_cipher.dart';
import 'package:dgvault/data/format/gzip_compressor.dart';
import 'package:test/test.dart';

CompositeCredential _cred(String pw) =>
    CompositeCredential(password: Uint8List.fromList(utf8.encode(pw)));

Uint8List _fixture() => File('test/fixtures/kdbx/reference_kdbx3.kdbx').readAsBytesSync();

Iterable<Entry> _all(Group g) sync* {
  yield* g.entries;
  for (final c in g.groups) {
    yield* _all(c);
  }
}

void main() {
  test('reads a KDBX 3.1 file (AES-KDF + AES-CBC + Salsa20 protected values)',
      () async {
    final db = await const Kdbx3Reader().read(
      _fixture(),
      _cred('kdbx3pass'),
      compressor: const GzipCompressor(),
    );

    final e = _all(db.root)
        .firstWhere((e) => e.fields['Title']?.value.reveal() == 'Acme v3');
    expect(e.fields['UserName']!.value.reveal(), 'alice3');
    // password is Salsa20-protected in the inner stream
    expect(e.fields['Password']!.value.reveal(), 's3cret-v3');
    expect(e.fields['Password']!.isProtected, isTrue);
    expect(e.fields['URL']!.value.reveal(), 'https://v3.example');
  });

  test('wrong password fails (stream-start verification)', () async {
    expect(
      () => const Kdbx3Reader()
          .read(_fixture(), _cred('nope'), compressor: const GzipCompressor()),
      throwsA(isA<KdbxIntegrityException>()),
    );
  });
}
