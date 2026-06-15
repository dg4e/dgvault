import 'dart:convert';
import 'dart:typed_data';

import 'package:dgvault/core/crypto/cipher.dart';
import 'package:dgvault/core/crypto/key_derivation.dart';
import 'package:dgvault/core/crypto/secure_key.dart';
import 'package:dgvault/core/model/database.dart';
import 'package:dgvault/core/model/entry.dart';
import 'package:dgvault/core/model/field.dart';
import 'package:dgvault/core/model/group.dart';
import 'package:dgvault/core/model/kdf_params.dart';
import 'package:dgvault/core/model/protected_value.dart';
import 'package:dgvault/data/import_export/encrypted_csv.dart';
import 'package:test/test.dart';

// --- Test doubles: deterministic, NOT real crypto. They exercise the container
// orchestration + the authenticated-decrypt contract (wrong key / tamper fail).

class _StubKdf implements KeyDerivation {
  @override
  bool supports(KdfAlgorithm algorithm) => true;

  @override
  Future<SecureKey> deriveKey(
      CompositeCredential c, KdfParams p, Uint8List salt) async {
    final pw = c.password ?? Uint8List(0);
    final key = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      final a = pw.isEmpty ? 0 : pw[i % pw.length];
      final b = salt.isEmpty ? 0 : salt[i % salt.length];
      key[i] = (a ^ b ^ i) & 0xff;
    }
    return HeapSecureKey(key);
  }
}

class _StubCipher implements Cipher {
  @override
  DatabaseCipher get algorithm => DatabaseCipher.aes256;
  @override
  int get ivLength => 16;

  Uint8List _xor(Uint8List data, Uint8List key, Uint8List iv) {
    final out = Uint8List(data.length);
    for (var i = 0; i < data.length; i++) {
      out[i] = data[i] ^ key[i % key.length] ^ iv[i % iv.length];
    }
    return out;
  }

  Uint8List _tag(Uint8List key, Uint8List iv, Uint8List pt) {
    var h = 0xcbf29ce484222325; // FNV-1a 64
    void mix(Uint8List b) {
      for (final x in b) {
        h ^= x;
        h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
      }
    }

    mix(key);
    mix(iv);
    mix(pt);
    return (ByteData(8)..setUint64(0, h, Endian.little)).buffer.asUint8List();
  }

  @override
  Future<Uint8List> encrypt(
      {required SecureKey key, required Uint8List iv, required Uint8List plaintext}) async {
    final core = _xor(plaintext, key.bytes(), iv);
    return Uint8List.fromList([...core, ..._tag(key.bytes(), iv, plaintext)]);
  }

  @override
  Future<Uint8List> decrypt(
      {required SecureKey key, required Uint8List iv, required Uint8List ciphertext}) async {
    if (ciphertext.length < 8) throw StateError('truncated');
    final core = Uint8List.sublistView(ciphertext, 0, ciphertext.length - 8);
    final tag = Uint8List.sublistView(ciphertext, ciphertext.length - 8);
    final pt = _xor(core, key.bytes(), iv);
    final expect = _tag(key.bytes(), iv, pt);
    for (var i = 0; i < 8; i++) {
      if (tag[i] != expect[i]) {
        throw StateError('authentication failed'); // wrong key or tampered
      }
    }
    return pt;
  }

  @override
  Stream<Uint8List> decryptStream(
          {required SecureKey key, required Uint8List iv, required Stream<List<int>> ciphertext}) =>
      throw UnimplementedError();
}

EncryptedCsv newCodec() => EncryptedCsv(cipher: _StubCipher(), kdf: _StubKdf());

CompositeCredential cred(String pw) =>
    CompositeCredential(password: Uint8List.fromList(utf8.encode(pw)));

Group sampleRoot() => Group(uuid: 'r', name: 'Root', entries: [
      Entry(uuid: 'e', fields: {
        Field.title: Field(key: Field.title, value: InMemoryProtectedValue.plain('Acme')),
        Field.userName: Field(key: Field.userName, value: InMemoryProtectedValue.plain('alice')),
        Field.password: Field(key: Field.password, value: InMemoryProtectedValue('s3cret')),
      }),
    ]);

final _salt = Uint8List.fromList(List.generate(16, (i) => i));
final _iv = Uint8List.fromList(List.generate(16, (i) => 255 - i));

void main() {
  test('export → import round-trips entries with the right password', () async {
    final codec = newCodec();
    final container = await codec.export(sampleRoot(),
        credential: cred('correct horse'),
        params: KdfParams.argon2idDefault(),
        salt: _salt,
        iv: _iv);
    final result = await codec.import(container, credential: cred('correct horse'));
    final e = result.root.entries.single;
    expect(e.title, 'Acme');
    expect(e.fields[Field.userName]!.value.reveal(), 'alice');
    expect(e.fields[Field.password]!.value.reveal(), 's3cret');
  });

  test('wrong password fails decryption (authenticated)', () async {
    final codec = newCodec();
    final container = await codec.export(sampleRoot(),
        credential: cred('right'), params: KdfParams.argon2idDefault(), salt: _salt, iv: _iv);
    expect(() => codec.import(container, credential: cred('wrong')),
        throwsA(isA<StateError>()));
  });

  test('tampered ciphertext fails decryption', () async {
    final codec = newCodec();
    final container = await codec.export(sampleRoot(),
        credential: cred('pw'), params: KdfParams.argon2idDefault(), salt: _salt, iv: _iv);
    container[container.length - 1] ^= 0xFF; // flip a ciphertext/tag byte
    expect(() => codec.import(container, credential: cred('pw')),
        throwsA(isA<StateError>()));
  });

  test('bad magic is rejected as a malformed container', () async {
    final codec = newCodec();
    final bogus = Uint8List.fromList(List.filled(64, 0));
    expect(() => codec.import(bogus, credential: cred('pw')),
        throwsA(isA<EncryptedCsvException>()));
  });

  test('corrupt KDF-algorithm byte fails as a malformed container, not RangeError',
      () async {
    final codec = newCodec();
    final container = await codec.export(sampleRoot(),
        credential: cred('pw'), params: KdfParams.argon2idDefault(), salt: _salt, iv: _iv);
    // Layout: magic(5) version(1) cipherAlgo(1) kdfAlgo(1) ... — byte 7 is the
    // KDF-algorithm enum index. Force it out of range.
    container[7] = 0xFF;
    expect(() => codec.import(container, credential: cred('pw')),
        throwsA(isA<EncryptedCsvException>()));
  });

  test('non-default KDF params round-trip via the self-describing header', () async {
    final codec = newCodec();
    const params = KdfParams(
        algorithm: KdfAlgorithm.argon2d,
        iterations: 7,
        memoryKib: 32768,
        parallelism: 2,
        version: 0x13);
    final container = await codec.export(sampleRoot(),
        credential: cred('pw'), params: params, salt: _salt, iv: _iv);
    // No params passed to import → must be read back from the container.
    final result = await codec.import(container, credential: cred('pw'));
    expect(result.root.entries.single.title, 'Acme');
  });
}
