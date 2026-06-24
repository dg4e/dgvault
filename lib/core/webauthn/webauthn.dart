// dgvault — WebAuthn relying-party verification (passkeys), pure logic.
//
// The registration-response and assertion-response checks a relying party
// performs (WebAuthn §7.1/§7.2), minus the transport: parse the attestation
// object / authenticator data, and verify the ES256 signature. The actual
// passkey private-key operation lives in the platform authenticator (Secure
// Enclave / TPM); this is the verify side, which is pure and testable.
//
// Scope: ES256 (P-256). Attestation: 'none' (accepted) and 'packed' self-
// attestation (signature-verified). Full attestation-certificate-chain
// validation (basic/AttCA with x5c) is out of scope here.

import 'dart:typed_data';

import 'package:pointycastle/export.dart' as pc;

import 'authenticator_data.dart';
import 'cbor.dart';
import 'cose_key.dart';

class WebAuthnException implements Exception {
  WebAuthnException(this.message);
  final String message;
  @override
  String toString() => 'WebAuthnException: $message';
}

/// A registered passkey credential, extracted from a registration response.
class RegisteredCredential {
  RegisteredCredential({
    required this.credentialId,
    required this.publicKey,
    required this.signCount,
    required this.aaguid,
    required this.fmt,
    required this.attestationVerified,
  });

  final Uint8List credentialId;
  final CredentialPublicKey publicKey;
  final int signCount;
  final Uint8List aaguid;
  final String fmt;

  /// True when the attestation statement was cryptographically verified ('none'
  /// is reported as false — there is nothing to verify, the credential is still
  /// usable). x5c chains are not validated here.
  final bool attestationVerified;
}

class WebAuthn {
  const WebAuthn();

  /// Parse + verify a registration response (attestationObject + clientDataJSON)
  /// and return the credential to store. [expectedRpId] is checked against the
  /// authenticator data's rpIdHash when provided.
  RegisteredCredential verifyRegistration({
    required Uint8List attestationObject,
    required Uint8List clientDataJson,
    String? expectedRpId,
    bool requireUserVerification = false,
  }) {
    final obj = cborDecode(attestationObject);
    if (obj is! Map) throw WebAuthnException('attestationObject is not a map');
    final fmt = obj['fmt'];
    final authDataBytes = obj['authData'];
    final attStmt = obj['attStmt'];
    if (fmt is! String || authDataBytes is! Uint8List) {
      throw WebAuthnException('attestationObject missing fmt/authData');
    }

    final authData = AuthenticatorData.parse(authDataBytes);
    if (!authData.userPresent) {
      throw WebAuthnException('user-present flag not set');
    }
    if (requireUserVerification && !authData.userVerified) {
      throw WebAuthnException('user verification required but not performed');
    }
    if (expectedRpId != null) {
      _checkRpId(authData, expectedRpId);
    }
    final acd = authData.attestedCredentialData;
    if (acd == null) {
      throw WebAuthnException('registration has no attested credential data');
    }

    final clientDataHash = _sha256(clientDataJson);
    var verified = false;
    if (fmt == 'none') {
      verified = false; // nothing to verify; credential still valid
    } else if (fmt == 'packed' && attStmt is Map) {
      verified =
          _verifyPackedSelf(attStmt, authDataBytes, clientDataHash, acd.credentialPublicKey);
    } else {
      throw WebAuthnException('unsupported attestation format "$fmt"');
    }

    return RegisteredCredential(
      credentialId: acd.credentialId,
      publicKey: acd.credentialPublicKey,
      signCount: authData.signCount,
      aaguid: acd.aaguid,
      fmt: fmt,
      attestationVerified: verified,
    );
  }

  /// Verify an authentication assertion against a stored credential public key.
  /// Returns the new signature counter on success (callers should enforce that
  /// it is greater than the stored one to detect cloned authenticators).
  int verifyAssertion({
    required CredentialPublicKey publicKey,
    required Uint8List authenticatorData,
    required Uint8List clientDataJson,
    required Uint8List signature,
    String? expectedRpId,
    bool requireUserVerification = false,
  }) {
    final authData = AuthenticatorData.parse(authenticatorData);
    if (!authData.userPresent) {
      throw WebAuthnException('user-present flag not set');
    }
    if (requireUserVerification && !authData.userVerified) {
      throw WebAuthnException('user verification required but not performed');
    }
    if (expectedRpId != null) {
      _checkRpId(authData, expectedRpId);
    }

    // Signed data = authenticatorData ‖ SHA-256(clientDataJSON).
    final signed = Uint8List.fromList(
        [...authenticatorData, ..._sha256(clientDataJson)],);
    if (!publicKey.verify(signed, signature)) {
      throw WebAuthnException('assertion signature is invalid');
    }
    return authData.signCount;
  }

  bool _verifyPackedSelf(
    Map<Object?, Object?> attStmt,
    Uint8List authDataBytes,
    Uint8List clientDataHash,
    CredentialPublicKey credentialPublicKey,
  ) {
    if (attStmt.containsKey('x5c')) {
      // Basic/AttCA attestation: chain validation is out of scope.
      throw WebAuthnException('packed x5c attestation not validated here');
    }
    final sig = attStmt['sig'];
    if (sig is! Uint8List) throw WebAuthnException('packed attStmt missing sig');
    // Self-attestation: sig over authData ‖ clientDataHash with the credential key.
    final signed = Uint8List.fromList([...authDataBytes, ...clientDataHash]);
    return credentialPublicKey.verify(signed, sig);
  }

  void _checkRpId(AuthenticatorData authData, String rpId) {
    final want = _sha256(Uint8List.fromList(rpId.codeUnits));
    if (!_constEq(authData.rpIdHash, want)) {
      throw WebAuthnException('rpIdHash does not match "$rpId"');
    }
  }

  static Uint8List _sha256(Uint8List b) => pc.SHA256Digest().process(b);

  static bool _constEq(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var d = 0;
    for (var i = 0; i < a.length; i++) {
      d |= a[i] ^ b[i];
    }
    return d == 0;
  }
}
