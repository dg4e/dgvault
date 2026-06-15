import 'dart:convert';
import 'dart:typed_data';

import 'package:dgvault/core/crypto/impl/aead_cipher.dart';
import 'package:dgvault/core/crypto/impl/argon2_kdf.dart';
import 'package:dgvault/core/crypto/key_derivation.dart';
import 'package:dgvault/core/crypto/secure_key.dart';
import 'package:dgvault/core/model/kdf_params.dart';
import 'package:dgvault/core/security/app_lock_policy.dart';
import 'package:dgvault/core/security/key_vault.dart';
import 'package:dgvault/core/security/pin_unlock.dart';
import 'package:dgvault/core/security/secure_store.dart';
import 'package:test/test.dart';

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
Uint8List _pin(String s) => Uint8List.fromList(utf8.encode(s));

const _params = KdfParams(
    algorithm: KdfAlgorithm.argon2id, iterations: 2, memoryKib: 64, parallelism: 1,);
final _masterKey = Uint8List.fromList(List.generate(32, (i) => i + 3));

Future<PinUnlock> _setup({int maxAttempts = 3, bool wipe = true}) async {
  final vault = KeyVault(
      store: InMemorySecureStore(),
      cipher: AesGcmCipher(),
      kdf: const Argon2KeyDerivation(),);
  await vault.enroll(
    masterKey: HeapSecureKey(_masterKey),
    unlockSecret: CompositeCredential(password: _pin('1234')),
    params: _params,
    salt: Uint8List.fromList(List.generate(16, (i) => i + 1)),
    iv: Uint8List.fromList(List.generate(12, (i) => i + 2)),
  );
  final lock = AppLockPolicy(
      store: InMemoryFailedAttemptStore(),
      maxAttempts: maxAttempts,
      wipeOnExhaustion: wipe,);
  return PinUnlock(vault: vault, lock: lock);
}

void main() {
  test('correct PIN unlocks and returns the master key', () async {
    final pin = await _setup();
    final r = await pin.attempt(_pin('1234'));
    expect(r.unlocked, isTrue);
    expect(_hex(r.masterKey!.bytes()), _hex(_masterKey));
    expect(r.remainingAttempts, 3);
    expect(r.shouldWipe, isFalse);
  });

  test('wrong PIN decrements remaining attempts', () async {
    final pin = await _setup();
    final r = await pin.attempt(_pin('0000'));
    expect(r.unlocked, isFalse);
    expect(r.masterKey, isNull);
    expect(r.remainingAttempts, 2);
    expect(r.lockedOut, isFalse);
  });

  test('a correct PIN after failures resets the counter', () async {
    final pin = await _setup();
    await pin.attempt(_pin('0000'));
    final ok = await pin.attempt(_pin('1234'));
    expect(ok.unlocked, isTrue);
    expect(ok.remainingAttempts, 3, reason: 'counter reset on success');
  });

  test('exhausting attempts locks out and signals a wipe (delete-on-fail)', () async {
    final pin = await _setup(maxAttempts: 3);
    await pin.attempt(_pin('x'));
    await pin.attempt(_pin('y'));
    final third = await pin.attempt(_pin('z'));
    expect(third.lockedOut, isTrue);
    expect(third.shouldWipe, isTrue);

    // A further attempt does not even try to unwrap; still reports wipe pending.
    final after = await pin.attempt(_pin('1234'));
    expect(after.unlocked, isFalse);
    expect(after.lockedOut, isTrue);
    expect(after.shouldWipe, isTrue);
    expect(pin.isWipePending, isTrue);
  });

  test('lock-out without delete-on-fail does not signal a wipe', () async {
    final pin = await _setup(maxAttempts: 2, wipe: false);
    await pin.attempt(_pin('x'));
    final second = await pin.attempt(_pin('y'));
    expect(second.lockedOut, isTrue);
    expect(second.shouldWipe, isFalse);
    expect(pin.isWipePending, isFalse);
  });

  test('a corrupt/missing blob surfaces without consuming an attempt', () async {
    final vault = KeyVault(
        store: InMemorySecureStore(),
        cipher: AesGcmCipher(),
        kdf: const Argon2KeyDerivation(),);
    final lock = AppLockPolicy(store: InMemoryFailedAttemptStore(), maxAttempts: 3);
    final pin = PinUnlock(vault: vault, lock: lock);
    expect(() => pin.attempt(_pin('1234')), throwsA(isA<KeyVaultException>()));
    expect(lock.failedCount, 0, reason: 'not a wrong-PIN guess');
  });
}
