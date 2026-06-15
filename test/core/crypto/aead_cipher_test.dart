import 'dart:typed_data';

import 'package:dgvault/core/crypto/impl/aead_cipher.dart';
import 'package:dgvault/core/crypto/secure_key.dart';
import 'package:dgvault/core/model/database.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:test/test.dart';

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
Uint8List _h(String s) => Uint8List.fromList(
    [for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)],);

SecureKey _key([int fill = 0]) =>
    HeapSecureKey(Uint8List.fromList(List.generate(32, (i) => (i + fill) & 0xff)));
Uint8List _iv() => Uint8List.fromList(List.generate(12, (i) => 0xA0 + i));
Uint8List _msg() =>
    Uint8List.fromList('dgvault aead cross-check payload 0123456789'.codeUnits);

void main() {
  test('ChaCha20-Poly1305 primitive matches RFC 8439 §2.8.2 KAT', () {
    final key = Uint8List.fromList(List.generate(32, (i) => 0x80 + i));
    final nonce = _h('070000004041424344454647');
    final aad = _h('50515253c0c1c2c3c4c5c6c7');
    final pt = Uint8List.fromList(
        "Ladies and Gentlemen of the class of '99: If I could offer you only one "
                "tip for the future, sunscreen would be it."
            .codeUnits,);
    final c = pc.ChaCha20Poly1305(pc.ChaCha7539Engine(), pc.Poly1305())
      ..init(true, pc.AEADParameters(pc.KeyParameter(key), 128, nonce, aad));
    final out = Uint8List(c.getOutputSize(pt.length));
    var n = c.processBytes(pt, 0, pt.length, out, 0);
    n += c.doFinal(out, n);
    expect(
        _hex(out.sublist(0, n)),
        'd31a8d34648e60db7b86afbc53ef7ec2a4aded51296e08fea9e2b5a736ee62d6'
        '3dbea45e8ca9671282fafb69da92728b1a71de0a9e060b2905d6a5b67ecd3b36'
        '92ddbd7f2d778b8c9803aee328091b58fab324e4fad675945585808b4831d7bc'
        '3ff4def08e4b7a9de576d26586cec64b61161ae10b594f09e26a7e902ecbd0600691');
  });

  group('AesGcmCipher', () {
    final cipher = AesGcmCipher();

    test('algorithm = aes256, ivLength = 12', () {
      expect(cipher.algorithm, DatabaseCipher.aes256);
      expect(cipher.ivLength, 12);
    });

    test('regression KAT (pins cross-checked output vs cryptography pkg)', () async {
      final ct = await cipher.encrypt(key: _key(), iv: _iv(), plaintext: _msg());
      expect(
          _hex(ct),
          '827f0a4c30a7769f0300e6b72719b2b103df7473fad22107bc7e47ff13c41465'
          'f24676cd9c16660b68a43d03f47027a73ab28e4eb6a1344db4d3bb');
    });

    test('round-trips', () async {
      final ct = await cipher.encrypt(key: _key(), iv: _iv(), plaintext: _msg());
      final pt = await cipher.decrypt(key: _key(), iv: _iv(), ciphertext: ct);
      expect(_hex(pt), _hex(_msg()));
    });

    test('wrong key fails authentication', () async {
      final ct = await cipher.encrypt(key: _key(), iv: _iv(), plaintext: _msg());
      expect(() => cipher.decrypt(key: _key(1), iv: _iv(), ciphertext: ct),
          throwsA(isA<CipherAuthenticationException>()),);
    });

    test('tampered ciphertext fails authentication', () async {
      final ct = await cipher.encrypt(key: _key(), iv: _iv(), plaintext: _msg());
      ct[0] ^= 0xFF;
      expect(() => cipher.decrypt(key: _key(), iv: _iv(), ciphertext: ct),
          throwsA(isA<CipherAuthenticationException>()),);
    });

    test('wrong IV length is rejected', () async {
      expect(
          () => cipher.encrypt(
              key: _key(), iv: Uint8List(16), plaintext: _msg(),),
          throwsA(isA<ArgumentError>()),);
    });
  });

  group('ChaCha20Poly1305Cipher', () {
    final cipher = ChaCha20Poly1305Cipher();

    test('algorithm = chacha20', () {
      expect(cipher.algorithm, DatabaseCipher.chacha20);
    });

    test('regression KAT (pins cross-checked output vs cryptography pkg)', () async {
      final ct = await cipher.encrypt(key: _key(), iv: _iv(), plaintext: _msg());
      expect(
          _hex(ct),
          '68cc0e3e388ab68dc16a9270dc998f94ee2dfedc2b0f03c894a8bac81d0da268'
          '4cb027b89dfdcabcf1f4cc56eba106bd0b91f18aba84e70a2978ff');
    });

    test('round-trips', () async {
      final ct = await cipher.encrypt(key: _key(), iv: _iv(), plaintext: _msg());
      final pt = await cipher.decrypt(key: _key(), iv: _iv(), ciphertext: ct);
      expect(_hex(pt), _hex(_msg()));
    });

    test('tampered tag fails authentication', () async {
      final ct = await cipher.encrypt(key: _key(), iv: _iv(), plaintext: _msg());
      ct[ct.length - 1] ^= 0xFF;
      expect(() => cipher.decrypt(key: _key(), iv: _iv(), ciphertext: ct),
          throwsA(isA<CipherAuthenticationException>()),);
    });

    test('decryptStream reassembles chunks', () async {
      final ct = await cipher.encrypt(key: _key(), iv: _iv(), plaintext: _msg());
      // feed in two chunks
      final stream = Stream<List<int>>.fromIterable(
          [ct.sublist(0, 7), ct.sublist(7)],);
      final out = await cipher
          .decryptStream(key: _key(), iv: _iv(), ciphertext: stream)
          .expand((c) => c)
          .toList();
      expect(_hex(out), _hex(_msg()));
    });
  });
}
