import 'dart:convert';
import 'dart:typed_data';

import 'package:dgvault/core/crypto/key_derivation.dart';
import 'package:dgvault/core/security/challenge_response.dart';
import 'package:test/test.dart';

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
Uint8List _h(String s) => Uint8List.fromList(
    [for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)],);

void main() {
  group('HMAC-SHA1 (RFC 2202 vectors)', () {
    test('case 1: 20-byte 0x0b key, "Hi There"', () {
      final mac = hmacSha1(_h('0b' * 20), Uint8List.fromList(utf8.encode('Hi There')));
      expect(_hex(mac), 'b617318655057264e28bc0b6fb378c8ef146be00');
    });

    test('case 2: key "Jefe", "what do ya want for nothing?"', () {
      final mac = hmacSha1(Uint8List.fromList(utf8.encode('Jefe')),
          Uint8List.fromList(utf8.encode('what do ya want for nothing?')),);
      expect(_hex(mac), 'effcdf6ae5eb2fa2d27416d5f184df9c259a7c79');
    });

    test('case 3: 20-byte 0xaa key, 50 bytes of 0xdd', () {
      final mac = hmacSha1(_h('aa' * 20), _h('dd' * 50));
      expect(_hex(mac), '125d7342b9ac11cd91a39af48aa17b4f63f175d3');
    });
  });

  test('SoftwareChallengeResponse computes HMAC-SHA1(secret, challenge)', () async {
    final cr = SoftwareChallengeResponse(_h('0b' * 20));
    final resp = await cr.respond(Uint8List.fromList(utf8.encode('Hi There')));
    expect(_hex(resp), 'b617318655057264e28bc0b6fb378c8ef146be00');
  });

  test('the response feeds CompositeCredential.challengeResponse', () async {
    final cr = SoftwareChallengeResponse(_h('aabbccddeeff00112233'));
    final challenge = Uint8List.fromList(List.generate(32, (i) => i));
    final resp = await cr.respond(challenge);
    final cred = CompositeCredential(
      password: Uint8List.fromList(utf8.encode('pw')),
      challengeResponse: resp,
    );
    expect(cred.hasAnyFactor, isTrue);
    expect(cred.challengeResponse, resp);
    expect(resp.length, 20);
  });
}
