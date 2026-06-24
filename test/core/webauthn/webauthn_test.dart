// WebAuthn RP-side verification against an INDEPENDENT vector (Python
// cryptography + cbor2, P-256/ES256). Fixture: test/fixtures/webauthn/.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dgvault/core/webauthn/authenticator_data.dart';
import 'package:dgvault/core/webauthn/cbor.dart';
import 'package:dgvault/core/webauthn/cose_key.dart';
import 'package:dgvault/core/webauthn/webauthn.dart';
import 'package:test/test.dart';

Uint8List _hex(String s) => Uint8List.fromList(
    [for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)],);
String _hexOf(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  final vec = json.decode(
      File('test/fixtures/webauthn/es256_vector.json').readAsStringSync(),) as Map;
  const rp = WebAuthn();

  test('CBOR decoder: round-trips a known map/array/bytes structure', () {
    // map(4): {1:2, 3:-7, -1:1, 9:h'3132'}
    //   a4 | 01 02 | 03 26 | 20 01 | 09 42 3132
    final bytes = _hex('a401020326200109423132');
    final m = cborDecode(bytes) as Map;
    expect(m[1], 2);
    expect(m[3], -7);
    expect(m[-1], 1);
    expect(_hexOf(m[9] as Uint8List), _hexOf('12'.codeUnits)); // "12"
  });

  test('verifyRegistration extracts the credential (fmt=none)', () {
    final cred = rp.verifyRegistration(
      attestationObject: _hex(vec['attestationObject'] as String),
      clientDataJson: _hex(vec['clientDataJson_create'] as String),
      expectedRpId: vec['rpId'] as String,
      requireUserVerification: true,
    );
    expect(cred.fmt, 'none');
    expect(_hexOf(cred.credentialId), vec['credentialId']);
    expect(cred.publicKey.alg, CoseAlg.es256);
    expect(cred.attestationVerified, isFalse); // 'none' = nothing to verify
  });

  test('verifyAssertion accepts a valid ES256 signature', () {
    // Recover the public key from the registration, then verify the assertion.
    final cred = rp.verifyRegistration(
      attestationObject: _hex(vec['attestationObject'] as String),
      clientDataJson: _hex(vec['clientDataJson_create'] as String),
    );
    final count = rp.verifyAssertion(
      publicKey: cred.publicKey,
      authenticatorData: _hex(vec['assertion_authData'] as String),
      clientDataJson: _hex(vec['clientDataJson_get'] as String),
      signature: _hex(vec['assertion_signature'] as String),
      expectedRpId: vec['rpId'] as String,
      requireUserVerification: true,
    );
    expect(count, vec['expected_signCount']);
  });

  test('a tampered clientDataJSON fails the assertion', () {
    final cred = rp.verifyRegistration(
      attestationObject: _hex(vec['attestationObject'] as String),
      clientDataJson: _hex(vec['clientDataJson_create'] as String),
    );
    final bad = _hex(vec['clientDataJson_get'] as String);
    bad[10] ^= 0xFF;
    expect(
        () => rp.verifyAssertion(
              publicKey: cred.publicKey,
              authenticatorData: _hex(vec['assertion_authData'] as String),
              clientDataJson: bad,
              signature: _hex(vec['assertion_signature'] as String),
            ),
        throwsA(isA<WebAuthnException>()),);
  });

  test('a tampered signature fails the assertion', () {
    final cred = rp.verifyRegistration(
      attestationObject: _hex(vec['attestationObject'] as String),
      clientDataJson: _hex(vec['clientDataJson_create'] as String),
    );
    final sig = _hex(vec['assertion_signature'] as String);
    sig[sig.length - 1] ^= 0xFF;
    expect(
        () => rp.verifyAssertion(
              publicKey: cred.publicKey,
              authenticatorData: _hex(vec['assertion_authData'] as String),
              clientDataJson: _hex(vec['clientDataJson_get'] as String),
              signature: sig,
            ),
        throwsA(isA<WebAuthnException>()),);
  });

  test('wrong rpId is rejected', () {
    final cred = rp.verifyRegistration(
      attestationObject: _hex(vec['attestationObject'] as String),
      clientDataJson: _hex(vec['clientDataJson_create'] as String),
    );
    expect(
        () => rp.verifyAssertion(
              publicKey: cred.publicKey,
              authenticatorData: _hex(vec['assertion_authData'] as String),
              clientDataJson: _hex(vec['clientDataJson_get'] as String),
              signature: _hex(vec['assertion_signature'] as String),
              expectedRpId: 'evil.example',
            ),
        throwsA(isA<WebAuthnException>()),);
  });

  test('authenticatorData parsing surfaces flags + signCount', () {
    final ad = AuthenticatorData.parse(_hex(vec['assertion_authData'] as String));
    expect(ad.userPresent, isTrue);
    expect(ad.userVerified, isTrue);
    expect(ad.hasAttestedCredentialData, isFalse);
    expect(ad.signCount, 7);
  });
}
