import 'dart:convert';
import 'dart:typed_data';

import 'package:dgvault/core/crypto/impl/aead_cipher.dart';
import 'package:dgvault/core/crypto/impl/argon2_kdf.dart';
import 'package:dgvault/core/crypto/key_derivation.dart';
import 'package:dgvault/core/crypto/secure_key.dart';
import 'package:dgvault/core/model/kdf_params.dart';
import 'package:dgvault/core/security/key_vault.dart';
import 'package:dgvault/core/security/secure_store.dart';
import 'package:test/test.dart';

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

CompositeCredential _pin(String s) =>
    CompositeCredential(password: Uint8List.fromList(utf8.encode(s)));

// Light KDF so PIN wrapping is fast in tests.
const _params = KdfParams(
    algorithm: KdfAlgorithm.argon2id, iterations: 2, memoryKib: 64, parallelism: 1,);
final _salt = Uint8List.fromList(List.generate(16, (i) => i + 5));
final _iv = Uint8List.fromList(List.generate(12, (i) => i + 9));
final _masterKey = Uint8List.fromList(List.generate(32, (i) => i * 7 + 1));

KeyVault _vault(SecureStore store) =>
    KeyVault(store: store, cipher: AesGcmCipher(), kdf: const Argon2KeyDerivation());

Future<void> _enroll(KeyVault v, String pin) => v.enroll(
      masterKey: HeapSecureKey(_masterKey),
      unlockSecret: _pin(pin),
      params: _params,
      salt: _salt,
      iv: _iv,
    );

void main() {
  test('enroll → unlock with the right PIN returns the master key', () async {
    final store = InMemorySecureStore();
    final v = _vault(store);
    expect(await v.isEnrolled, isFalse);
    await _enroll(v, '1234');
    expect(await v.isEnrolled, isTrue);

    final key = await v.unlock(_pin('1234'));
    expect(_hex(key.bytes()), _hex(_masterKey));
  });

  test('wrong PIN fails authenticated decryption (no plaintext leak)', () async {
    final v = _vault(InMemorySecureStore());
    await _enroll(v, '1234');
    expect(() => v.unlock(_pin('9999')),
        throwsA(isA<CipherAuthenticationException>()),);
  });

  test('the stored blob does not contain the master key in the clear', () async {
    final store = InMemorySecureStore();
    await _enroll(_vault(store), '1234');
    final blob = (await store.read('dgvault.masterkey'))!;
    // No 4-byte run of the master key should appear verbatim.
    final hay = _hex(blob);
    expect(hay.contains(_hex(_masterKey)), isFalse);
  });

  test('reset removes the wrapped key; unlock then fails', () async {
    final v = _vault(InMemorySecureStore());
    await _enroll(v, '1234');
    await v.reset();
    expect(await v.isEnrolled, isFalse);
    expect(() => v.unlock(_pin('1234')), throwsA(isA<KeyVaultException>()));
  });

  test('tampered blob fails (auth or format)', () async {
    final store = InMemorySecureStore();
    await _enroll(_vault(store), '1234');
    final blob = (await store.read('dgvault.masterkey'))!;
    blob[blob.length - 1] ^= 0xFF; // flip a ciphertext/tag byte
    await store.write('dgvault.masterkey', blob);
    expect(() => _vault(store).unlock(_pin('1234')),
        throwsA(anyOf(isA<CipherAuthenticationException>(), isA<KeyVaultException>())),);
  });

  test('bad magic is rejected', () async {
    final store = InMemorySecureStore();
    await store.write('dgvault.masterkey', Uint8List.fromList(List.filled(80, 0)));
    expect(() => _vault(store).unlock(_pin('1234')),
        throwsA(isA<KeyVaultException>()),);
  });
}
